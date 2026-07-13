from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from contextlib import asynccontextmanager
from apscheduler.schedulers.background import BackgroundScheduler
import ollama 
from sqlalchemy.orm import Session
from database import (get_db, Category, Source, Article, Digest, DigestArticle, SessionLocal, init_db)
from sqlalchemy import func
from parser import parse_rss_sources


scheduler = BackgroundScheduler()

def run_background_parser():
    print("[Scheduler] Automated startup of parsing by schedule...")
    db = SessionLocal()  
    try:
        parse_rss_sources(db)  
        print("[Scheduler] Background parsing completed successfully.")
    except Exception as e:
        print(f"[Scheduler] Помилка планувальника: {e}")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print("[DB] Data base initialized successfully")
    seconds = 900
    scheduler.add_job(run_background_parser, 'interval', seconds=seconds, id='news_parser_job')
    scheduler.start()
    print(f"[FastAPI] Background scheduler started (test interval: {seconds} seconds).")
    
    yield  
    

    scheduler.shutdown()
    print("[FastAPI] Background scheduler stopped.")

app = FastAPI(
    title="Styslo Backend API",
    lifespan=lifespan
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class NewsRequest(BaseModel):
    category: str       
    compression: str  

class SourceRequest(BaseModel):
    name: str        
    url: str         
    category: str    

class CategoryRequest(BaseModel):
    name: str

@app.get("/")
def read_root():
    return {"status": "Styslo Backend is running"}

async def summarize_news(news_text: str, compression_level: str) -> str:
    if compression_level == "Compressed(only main thought)":
        prompt = f"Стислий підсумок українською мовою строго в 1 коротке речення (головна думка) для радіо-дайджесту: {news_text}"
    else:
        prompt = f"Детальний підсумок українською мовою в 3-4 реченнях для радіо-дайджесту: {news_text}"
        
    try:
        response = ollama.generate(
            model='llama3',
            prompt=prompt
        )
        return response['response'].strip()
    except Exception as e:
        print(f"Error Ollama: {e}")
        return "Cant generate summary due to an error."

@app.get("/api/config")
def get_config(db: Session = Depends(get_db)):
               
    categories = db.query(Category).all()

    config = {}

    for cat in categories:
        config[cat.name] = [cat.name.lower()]

    return {
        'categories': config,
        'compression_levels': ["Compressed(only main thought)", "Detailed(3-4 sentences)"]
    }


@app.post("/api/sources", status_code=201)
async def add_source(request: SourceRequest, db: Session = Depends(get_db)):
    incoming_category = request.category.strip()
    category = None
    all_categories = db.query(Category).all()
    
    for cat in all_categories:
        if incoming_category.lower() in cat.name.lower() or cat.name.lower() in incoming_category.lower():
            category = cat
            break
            
    if not category:
        print(f"[DB] Category '{incoming_category}' not found. Creating on the fly...")
        category = Category(name=incoming_category)
        db.add(category)
        db.commit()
        db.refresh(category)

    existing_source = db.query(Source).filter(
        Source.url_or_credentials == request.url.strip(),
        Source.category_id == category.id
    ).first()
    
    if existing_source:
        return {"status": "exists", "message": f"Source is already linked to the category {category.name}"}

    new_source = Source(
        category_id=category.id,
        name=request.name.strip(),
        source_type="rss", 
        url_or_credentials=request.url.strip(),
        is_active=True
    )
    db.add(new_source)
    db.commit()
    
    print(f"[DB] Successfully added source '{new_source.name}' to category '{category.name}'")
    return {
        "status": "success",
        "message": f"Source '{new_source.name}' added to category '{category.name}'"
    }  

@app.post("/api/news")
async def get_news(request: NewsRequest, db: Session = Depends(get_db)):
    incoming_category = request.category.strip()
    req_compression = request.compression

    category = db.query(Category).filter(
        func.lower(Category.name) == func.lower(incoming_category)
    ).first()

    if not category:
        raise HTTPException(
            status_code=404,
            detail=f"Category '{incoming_category}' not found."
        )

    sources = db.query(Source).filter(
        Source.category_id == category.id,
        Source.is_active.is_(True)
    ).all()

    source_ids = [source.id for source in sources]

    if not source_ids:
        return {
            "title": category.name,
            "content": "No active sources in this category."
        }

    latest_articles = db.query(Article).filter(
        Article.source_id.in_(source_ids)
    ).order_by(
        Article.published_at.desc(),
        Article.id.desc()
    ).limit(3).all()

    if not latest_articles:
        return {
            "title": category.name,
            "content": "No news available in the database. Run parser.py or wait for the scheduler."
        }

    combined_news_text = "\n\n".join(
        [
            f"Новина {position}: {article.title}\n{article.raw_text}"
            for position, article in enumerate(latest_articles, start=1)
        ]
    )

    final_content = await summarize_news(
        combined_news_text,
        req_compression
    )

    new_digest = Digest(
        category_id=category.id,
        compression_level=req_compression,
        summary_text=final_content
    )

    try:
        db.add(new_digest)
        db.flush()
        
        for position, article in enumerate(latest_articles, start=1):
            digest_article = DigestArticle(
                digest_id=new_digest.id,
                article_id=article.id,
                position=position
            )

            db.add(digest_article)

        db.commit()

        db.refresh(new_digest)

    except Exception as error:
        db.rollback()
        print(f"[DB] Cannot save digest: {error}")

        raise HTTPException(
            status_code=500,
            detail="Digest was generated but could not be saved to database."
        )

    return {
        "digest_id": new_digest.id,
        "title": latest_articles[0].title,
        "content": final_content,
        "category": category.name,
        "used_articles": [
            {
                "id": article.id,
                "title": article.title,
                "url": article.source_url
            }
            for article in latest_articles
        ]
    }

@app.get("/api/sources")
def get_all_sources(db: Session = Depends(get_db)):
    categories = db.query(Category).all()
    result = []
    for cat in categories:
        result.append({
            "category_name": cat.name,
            "sources": [
                {
                    "id": src.id,
                    "name": src.name,
                    "url": src.url_or_credentials,
                    "is_active": src.is_active
                } for src in cat.sources
            ]
        })
    return result

@app.delete("/api/sources/{source_id}")
def delete_source(source_id: int, db: Session = Depends(get_db)):
    source = db.query(Source).filter(Source.id == source_id).first()
    if not source:
        raise HTTPException(status_code=404, detail="Sources not found")
    db.delete(source)
    db.commit()
    return {"status": "success", "message": f"Source {source_id} deleted successfully"}

@app.post("/api/categories", status_code=201)
def create_category(request: CategoryRequest, db: Session = Depends(get_db)):
    name_clean = request.name.strip()
    existing = db.query(Category).filter(func.lower(Category.name) == func.lower(name_clean)).first()
    if existing:
        raise HTTPException(status_code=400, detail="Such category already exists.")
        
    new_cat = Category(name=name_clean)
    db.add(new_cat)
    db.commit()
    return {"status": "success", "message": f"Category '{name_clean}' created successfully"}

@app.delete("/api/categories/{cat_name}")
def delete_category(cat_name: str, db: Session = Depends(get_db)):
    target_name = cat_name.strip().lower()
    all_categories = db.query(Category).all()
    category = None
    for cat in all_categories:
        if target_name in cat.name.lower() or cat.name.lower() in target_name:
            category = cat
            break

    if not category:
        raise HTTPException(status_code=404, detail=f"Category not found.")
        
    db.delete(category)
    db.commit()
    return {"status": "success", "message": f"Category '{category.name}' deleted successfully"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)