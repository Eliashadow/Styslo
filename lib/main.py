from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import re
import ollama 
from sqlalchemy.orm import Session
from database import get_db, Category, Source, Article, Digest, init_db

app = FastAPI(title="Styslo Backend API")

@app.on_event("startup")
def on_startup():
    init_db()

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


@app.post("/api/news")
async def get_news(request: Request, db: Session = Depends(get_db)):
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON format")
        

    print(f"\n[DEBUG] Отримано сирі дані від Flutter: {data}\n")

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
        
        return {"title": category.name, "content": f"Створено нову категорію '{category.name}'. Додайте до неї RSS-джерела або запустіть парсер."}

    source_ids = [source.id for source in category.sources if source.is_active]
    if not source_ids:
        return {"title": category.name, "content": "Немає активних джерел."}

    latest_articles = db.query(Article).filter(Article.source_id.in_(source_ids)).order_by(Article.published_at.desc()).limit(3).all()

    if not latest_articles:
        return {"title": category.name, "content": "Новин в базі немає. Спочатку запустіть parser.py"}

    main_title = latest_articles[0].title
    combined_news_text = "\n\n".join([f"Новина: {a.title}. {a.raw_text}" for a in latest_articles])

    final_content = summarize_news(combined_news_text, req_compression)

    return {
        "title": main_title,
        "content": final_content,
        "category": category.name
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)