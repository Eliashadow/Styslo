from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from contextlib import asynccontextmanager
from apscheduler.schedulers.background import BackgroundScheduler
import ollama 
from sqlalchemy.orm import Session
from database import get_db, Category, Source, Article, Digest, SessionLocal, init_db
from sqlalchemy import func
from parser import parse_rss_sources


scheduler = BackgroundScheduler()

def run_background_parser():
    print("[Scheduler] Запуск автоматичного парсингу новин за розкладом...")
    db = SessionLocal()  
    try:
        parse_rss_sources(db)  
        print("[Scheduler] Фоновий парсинг успішно завершено.")
    except Exception as e:
        print(f"[Scheduler] Помилка планувальника: {e}")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print("[БД] Базу даних успішно ініціалізовано.")
    

    scheduler.add_job(run_background_parser, 'interval', seconds=900, id='news_parser_job')
    scheduler.start()
    print("[FastAPI] Фоновий планувальник задач запущено (тестовий інтервал: 900 сек).")
    
    yield  
    

    scheduler.shutdown()
    print("[FastAPI] Фоновий планувальник задач зупинено.")

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

# Ендпоінти API
@app.get("/")
def read_root():
    return {"status": "Styslo Backend is running"}

def summarize_news(news_text: str, compression_level: str) -> str:
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
        print(f"Помилка Ollama: {e}")
        return "Не вдалося згенерувати підсумок ШІ."

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
        print(f"[БД] Категорії '{incoming_category}' не знайдено. Створюємо на льоту...")
        category = Category(name=incoming_category)
        db.add(category)
        db.commit()
        db.refresh(category)

    existing_source = db.query(Source).filter(
        Source.url_or_credentials == request.url.strip(),
        Source.category_id == category.id
    ).first()
    
    if existing_source:
        return {"status": "exists", "message": f"Джерело вже прив'язане до категорії {category.name}"}

    new_source = Source(
        category_id=category.id,
        name=request.name.strip(),
        source_type="rss", 
        url_or_credentials=request.url.strip(),
        is_active=True
    )
    db.add(new_source)
    db.commit()
    
    print(f"[БД] Успішно додано джерело '{new_source.name}' до категорії '{category.name}'")
    return {
        "status": "success",
        "message": f"Джерело '{new_source.name}' додано до категорії '{category.name}'"
    }  

@app.post("/api/news")
async def get_news(request: Request, db: Session = Depends(get_db)):
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON format")
        
    print(f"\n[DEBUG] Отримано дані від Flutter: {data}\n")

    req_category = data.get("category", "General")
    req_compression = data.get("compression", "Compressed(only main thought)")
    incoming_category = str(req_category).strip()
    
    category = None
    all_categories = db.query(Category).all()
    for cat in all_categories:
        if incoming_category.lower() in cat.name.lower() or cat.name.lower() in incoming_category.lower():
            category = cat
            break
            
    if not category:
        print(f"[БД] Категорії '{incoming_category}' немає. Створюємо...")
        category = Category(name=incoming_category)
        db.add(category)
        db.commit()
        db.refresh(category)
        return {"title": category.name, "content": f"Створено нову категорію '{category.name}'. Додайте RSS-джерела."}

    source_ids = [source.id for source in category.sources if source.is_active]
    if not source_ids:
        return {"title": category.name, "content": "Немає активних джерел у цій категорії."}

    latest_articles = db.query(Article).filter(Article.source_id.in_(source_ids)).order_by(Article.published_at.desc()).limit(3).all()

    if not latest_articles:
        return {"title": category.name, "content": "Новин в базі немає. Зачекайте фонового оновлення парсера."}

    main_title = latest_articles[0].title
    combined_news_text = "\n\n".join([f"Новина: {a.title}. {a.raw_text}" for a in latest_articles])
    final_content = summarize_news(combined_news_text, req_compression)

    return {
        "title": main_title,
        "content": final_content,
        "category": category.name
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
        raise HTTPException(status_code=404, detail="Джерело не знайдено")
    db.delete(source)
    db.commit()
    return {"status": "success", "message": f"Джерело {source_id} успішно видалено"}

@app.post("/api/categories", status_code=201)
def create_category(request: CategoryRequest, db: Session = Depends(get_db)):
    name_clean = request.name.strip()
    existing = db.query(Category).filter(func.lower(Category.name) == func.lower(name_clean)).first()
    if existing:
        raise HTTPException(status_code=400, detail="Така категорія вже існує")
        
    new_cat = Category(name=name_clean)
    db.add(new_cat)
    db.commit()
    return {"status": "success", "message": f"Категорію '{name_clean}' успішно створено"}

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
        raise HTTPException(status_code=404, detail=f"Категорію не знайдено.")
        
    db.delete(category)
    db.commit()
    return {"status": "success", "message": f"Категорію '{category.name}' успішно видалено"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)