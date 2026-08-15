# This code for supporting backend and operation with them 
# ==== Essential imports ====
import re # Editing strings
import subprocess 
from contextlib import asynccontextmanager # Planner
import uuid
import os 
import json

# ==== Server imports ==== 
from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from apscheduler.schedulers.background import BackgroundScheduler

# ==== DB imports ====
from database import (get_db, User, UserCategory, Category, Source, Article, Digest, DigestArticle, SessionLocal, init_db)
from pathlib import Path
from sqlalchemy import func
from sqlalchemy.orm import Session
from pydantic import BaseModel, ValidationError

# ==== Generating imports ====
from piper.voice import PiperVoice
from faster_whisper import WhisperModel
import ollama 

# ==== Other ====
from parser import parse_rss_sources, parse_telegram_sources, parse_api_sources
from logger import Logger, Timer, LogLevel

# For turning off in release
version = 'test'
# ==== Log ====
l = Logger(
    colors = True,
    frame = 100,
    version=version,
    min_level=LogLevel.DEBUG
    )

# Establising actions after starting 
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    l.info("Data base initialized successfully")
    seconds = 900
    # Running background parser to gather news
    scheduler.add_job(run_background_parser, 'interval', seconds=seconds, id='news_parser_job')
    scheduler.start()
    l.info(f"[FastAPI] Background scheduler started (test interval: {seconds} seconds).")
    
    yield  

    scheduler.shutdown()
    l.info("[FastAPI] Background scheduler stopped.")

# Init app
app = FastAPI(
    title="Styslo Backend API",
    lifespan=lifespan
)

# Configuring API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Creating directory for saving generated audiofiles
audio_dir = Path(r"C:\Styslo\storage\audio").resolve()
audio_dir.mkdir(parents=True, exist_ok=True)

# Mounting directory on server
app.mount("/audio", StaticFiles(directory=audio_dir), name="audio")

# Path to Piper(voicer)
piper_exe = r"C:\Styslo\bin\piper\piper.exe"

scheduler = BackgroundScheduler()

# Configuring Whiper(listening audio for timings)
model = WhisperModel('tiny', device='cpu', compute_type='int8')

# Forms for requesting news from db
class NewsRequest(BaseModel):
    category: str 
    title: str
    compression: str  
    user_id: int | None = None
    language: str  = "uk_UA"
    speech_rate: float = 0.5
class UserCreateRequest(BaseModel):
    name: str | None = None
    email: str
    password_hash: str | None = None
class UserCategoriesRequest(BaseModel):
    category_ids: list[int]
class SourceRequest(BaseModel):
    name: str        
    url: str         
    category: str    

class CategoryRequest(BaseModel):
    name: str

# Starting screen
@app.get("/")
def read_root():
    return {"status": "Styslo Backend is running"}

def run_background_parser():
    l.info("[Scheduler] Automated startup of parsing by schedule...")
    db = SessionLocal()  
    try:
        # Using parser tools
        parse_rss_sources(db)  
        l.info("[Scheduler] RSS parsing completed successfully.")
        parse_telegram_sources(db)
        l.info("[Scheduler] Telegram parsing completed successfully.")
        parse_api_sources(db)
        l.info("[Scheduler] Api parsing completed successfully.")
        l.info("[Scheduler] Background parsing completed successfully.")
    except Exception as e:
        l.error(f"[Scheduler] Scheduler error: {e}")
    finally:
        db.close()

# Summarizing news with ollama 
async def summarize_news(news_text: str, compression_level: str) -> str:
    with Timer(l, 'generating summary'):
        # Diffrent prompts depending on compression level
        if compression_level == "Compressed(only main thought)":
            prompt = f"Стислий підсумок українською мовою строго в 1 коротке речення (головна думка) для радіо-дайджесту: {news_text}"
        else:
            prompt = f"Детальний підсумок українською мовою в 3-4 реченнях для радіо-дайджесту: {news_text}"
            
        try:
            # Setting model 
            response = ollama.generate(
                model='llama3',
                prompt=prompt
            )
            return response['response'].strip()
        except Exception as e:
            l.error(f"Error Ollama: {e}")
            return "Cant generate summary due to an error."
        
# Cleaning text from rubbish
def clean_text(text):
    return re.sub(r'[^а-яА-ЯіІїЇєЄґҐ0-9\s.,!?-]', '', text)

# Generating audio with text from ollama
async def generate_speech(text, lang, rate, output_path): 
    # ==== Piper segment ====

    # Setting model for tts(language)
    model_path = r"C:\Styslo\assets\models\tts\ua\uk_UA-tetiana-high.onnx"
    path = Path(model_path)
    voice_name = path.name 

    cleaned = clean_text(text)
    # Using logger to measure time 
    with Timer(l, 'generating speech'):
        # Catching every problem in this segment 
        try:
            # Check for audio directory to avoid crashing
            if os.path.exists(r"C:\Styslo\storage\audio"):
                # Running check for Piper
                l.debug('Checking piper.exe ...')
                l.debug(f'Does it exists? {os.path.exists(piper_exe)}')
                # If not exists returning to avoid crashing
                if os.path.exists(piper_exe) ==  False : return None, [], None 

                # Formatting command for Piper
                command = [
                    piper_exe,
                    "--model", model_path,
                    "--output_file", output_path
                ]

                # Run and pipe the text to stdin
                process = subprocess.Popen(
                    command,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8"
                )
                stdout, stderr = process.communicate(input=cleaned)

                # ==== Piper Failsafes ====
                # Catching problem in creating audio
                if process.returncode != 0:
                    l.debug(f"[DEBUG] Piper Process Error: {stderr}")
                    return False
                
                # Catching empty files and not existent
                if not output_path.exists() or output_path.stat().st_size <= 44:
                    l.warning("Synthesize produced an empty or invalid file.")
                    return None, [], None
                
                l.debug(f'Generated file size: {os.path.getsize(output_path)} bytes')

                # ==== Whisper segment ====

                # Whisper settings
                segments, info = model.transcribe(
                            output_path,  
                            word_timestamps=True
                        )

                # Getting timings
                timings = []
                for segment in segments:
                    for word in segment.words:
                        timings.append ({"Word": word.word.strip(),
                                        "Start": word.start,
                                        "End": word.end
                                        })
                        
                l.info('Successfully generated audio file with timings')
                return output_path, timings, voice_name
            else:
                l.debug('Check if "storage/audio" exists')  
                return None, [], None      
        except Exception as e:
            l.error(f'TTS/Aligment Error: {e}')
            return None, [], None

# Getting config method from server used by app
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

# Creating digest from app
@app.post("/api/news")
async def get_news(request: NewsRequest, fastapi_req:Request, db: Session = Depends(get_db)):
    # Setting timer for get_news
    with Timer(l, 'getting news'):
        try: 
            l.debug(f"Category: {request.category}, Compression: {request.compression}")

            # Requesting data from app
            req_category = request.category.strip()
            req_compression = request.compression

            # Getting category  
            category = None
            all_categories = db.query(Category).all()
            if request.user_id is not None:
                user = db.query(User).filter(User.id == request.user_id).first()

            if not user:
                raise HTTPException(status_code=404, detail=f"User with id {request.user_id} not found.")
            
            for cat in all_categories:
                if req_category.lower() in cat.name.lower() or cat.name.lower() in req_category.lower():
                    category = cat
                    break

            # Creating category if not existent to avoid crash   
            if not category:
                category = Category(name=req_category)
                db.add(category)
                db.commit()
                db.refresh(category)
                return {"title": category.name, "content": f"Created new category '{category.name}'."}

            # Catching not existent source
            source_ids = [source.id for source in category.sources if source.is_active]
            if not source_ids:
                return {"title": category.name, "content": "No active sources in this category."}

            # Getiing articles from db
            latest_articles = db.query(Article).filter(Article.source_id.in_(source_ids)).order_by(Article.published_at.desc()).limit(3).all()

            # Catching empty article text
            if not latest_articles:
                return {"title": category.name, "content": "No news available in the database. Please wait for the background parser to update."}
            main_title = latest_articles[0].title
            combined_news_text = "\n\n".join([f"News: {a.title}. {a.raw_text or ''}" for a in latest_articles])

            # Sending text to compress by Ollama
            final_content = await summarize_news(combined_news_text, req_compression)

            # Naming file before to have outpath to use later
            file_name = f"{uuid.uuid4()}.wav"
            output_path = audio_dir / file_name

            # Generating audio with piper
            temp_wav_path, timings, voice = await generate_speech(final_content, request.language, request.speech_rate, output_path)

            # If there is not path so there is not file 
            if not temp_wav_path:
                raise HTTPException(status_code=500, detail='Speech/aligment generation failed')

            # Final check for existence
            l.debug(f'Checking file at {temp_wav_path}...')
            l.debug(f'Does file exist? {os.path.exists(temp_wav_path)}')

            # Formatting audio url to save in db(inefficient to save whole file so saving url) 
            audio_url = f"{fastapi_req.base_url}audio/{file_name}"
            l.debug(f'Created audio url: {audio_url} \n Number of characters {len(audio_url)} \n Number of characters with trim {len(audio_url.strip())}')

            # Converting timings to json to ensure correct saving
            timings_json = json.dumps(timings,
                                    ensure_ascii=False
                                      )
            
            # Creating new digest for db
            new_digest = Digest(
                user_id=request.user_id,
                category_id=category.id,
                title=main_title,
                compression_level=req_compression,
                title = main_title,
                summary_text=final_content,
                lang = request.language
            )
        
            db.add(new_digest)
            db.flush()

            # Creating new audiofile for db
            new_audioFile = AudioFile(
                digest_id = new_digest.id,
                file_url = audio_url,
                file_name = file_name,
                timing = timings_json,
                voice_name = voice,
                language = request.language,
            )

            # Commiting new data to db to later use
            try:    
                db.add(new_audioFile)
                db.commit()
                l.info('[DB] Updated ')

            except Exception as e:
                db.rollback()
                l.error(f'[DB] Cannot save update: {e}')

                raise HTTPException(
                status_code=500,
                detail="Digest and audiofile were generated but could not be saved to database."
            )

            # Giving back info to app
            return {
                "title": main_title,
                "content": final_content,
                "audio_url": audio_url,
                "timings": timings, 
                "category": category.name,
                "status": "success",
                "digest_id": new_digest.id,
                # I literally don't know how it works
                "used_articles": [
            {
                "id": article.id,
                "title": article.title,
                "url": article.source_url
            }
            for article in latest_articles
        ]
    }
        except ValidationError as e:
            l.error(f'Validation error {e.json()}')
            raise HTTPException(status_code=500, detail=e.errors())
@app.post("/api/users")
def create_user(request: UserCreateRequest, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.email == request.email).first()

    if existing_user:
        raise HTTPException(status_code=400, detail="User with this email already exists.")

    new_user = User(
        name=request.name,
        email=request.email,
        password_hash=request.password_hash
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "id": new_user.id,
        "name": new_user.name,
        "email": new_user.email,
        "created_at": new_user.created_at
    }

@app.get("/api/users/{user_id}/digests")
def get_user_digests(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        raise HTTPException(status_code=404, detail=f"User with id {user_id} not found.")

    digests = db.query(Digest).filter(Digest.user_id == user_id).order_by(Digest.created_at.desc()).limit(20).all()

    result = []

    for digest in digests:
        used_articles = []

        for link in sorted(digest.article_links, key=lambda item: item.position or 0):
            used_articles.append({"id": link.article.id, "position": link.position, "title": link.article.title, "url": link.article.source_url})

        result.append({"id": digest.id, "category": digest.category.name, "compression_level": digest.compression_level, "summary_text": digest.summary_text, "ai_model": digest.ai_model, "audio_url": digest.audio_url, "created_at": digest.created_at, "used_articles": used_articles})

    return result

@app.put("/api/users/{user_id}/categories")
def update_user_categories(user_id: int, request: UserCategoriesRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        raise HTTPException(status_code=404, detail=f"User with id {user_id} not found.")

    categories = db.query(Category).filter(Category.id.in_(request.category_ids)).all()

    if len(categories) != len(request.category_ids):
        raise HTTPException(status_code=400, detail="Some category IDs do not exist.")

    db.query(UserCategory).filter(UserCategory.user_id == user_id).delete()

    for category_id in request.category_ids:
        subscription = UserCategory(user_id=user_id, category_id=category_id)
        db.add(subscription)

    db.commit()

    return {"user_id": user_id, "category_ids": request.category_ids}

@app.get("/api/digests")
def get_digests(db: Session = Depends(get_db)):
    digests = db.query(Digest).order_by(Digest.created_at.desc()).limit(20).all()
    result = []

    for digest in digests:
        used_articles = []

        for link in sorted(digest.article_links, key=lambda item: item.position or 0):
            used_articles.append({"id": link.article.id, "position": link.position, "title": link.article.title, "url": link.article.source_url})

        result.append({"id": digest.id, "category": digest.category.name, "compression_level": digest.compression_level, "summary_text": digest.summary_text, "ai_model": digest.ai_model, "audio_url": digest.audio_url, "created_at": digest.created_at, "used_articles": used_articles})

    return result


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

# ==== Sources Screen operations ====
# Online method to add sources 
@app.post("/api/sources", status_code=201)
async def add_source(request: SourceRequest, db: Session = Depends(get_db)):
    # Requesting category from source
    incoming_category = request.category.strip()
    category = None
    all_categories = db.query(Category).all()

    # Listing categories
    for cat in all_categories:
        if incoming_category.lower() in cat.name.lower() or cat.name.lower() in incoming_category.lower():
            category = cat
            break

    # Creating category if not existent to avoid crash   
    if not category:
        l.info(f"[DB] Category '{incoming_category}' not found. Creating on the fly...")
        category = Category(name=incoming_category)
        db.add(category)
        db.commit()
        db.refresh(category)

    # Searching for source to check later
    existing_source = db.query(Source).filter(
        Source.url_or_credentials == request.url.strip(),
        Source.category_id == category.id
    ).first()
    
    if existing_source:
        return {"status": "exists", "message": f"Source is already linked to the category {category.name}"}

    # Cleaning url to correctly commit source type
    url = request.url.strip().lower()
    
    if "@" in url:
        source_type = 'telegram'
    elif "api" in url or "vercel.app" in url:
        source_type = 'api'
    else:
        source_type = 'rss'

    # Creating new source for db
    new_source = Source(
        category_id=category.id,
        name=request.name.strip(),
        source_type=source_type, 
        url_or_credentials=request.url.strip(),
        is_active=True
    )
    db.add(new_source)
    db.commit()
    
    l.info(f"[DB] Successfully added source '{new_source.name}' to category '{category.name}'")
    return {
        "status": "success",
        "message": f"Source '{new_source.name}' added to category '{category.name}'"
    }  

# Online method to delete sources 
@app.delete("/api/sources/{source_id}")
def delete_source(source_id: int, db: Session = Depends(get_db)):
    source = db.query(Source).filter(Source.id == source_id).first()
    if not source:
        raise HTTPException(status_code=404, detail="Sources not found")
    db.delete(source)
    db.commit()
    return {"status": "success", "message": f"Source {source_id} deleted successfully"}

# Online method to add categories 
@app.post("/api/categories", status_code=201)
def create_category(request: CategoryRequest, db: Session = Depends(get_db)):
    name_clean = request.name.strip()
    existing = db.query(Category).filter(func.lower(Category.name) == func.lower(name_clean)).first()
    # Catching that to avoid later problems in sources screen offline mode
    if existing:
        raise HTTPException(status_code=400, detail="Such category already exists.")
    
    # Creating new category for db
    new_cat = Category(name=name_clean)

    db.add(new_cat)
    db.commit()
    return {"status": "success", "message": f"Category '{name_clean}' created successfully"}

# Online method to delete categories
@app.delete("/api/categories/{cat_name}")
def delete_category(cat_name: str, db: Session = Depends(get_db)):
    target_name = cat_name.strip().lower()
    all_categories = db.query(Category).all()
    category = None

    # Searching category in categories
    for cat in all_categories:
        if target_name in cat.name.lower() or cat.name.lower() in target_name:
            category = cat
            break

    # Catching to avoid crashing
    if not category:
        raise HTTPException(status_code=404, detail=f"Category not found.")
        
    db.delete(category)
    db.commit()
    return {"status": "success", "message": f"Category '{category.name}' deleted successfully"}

# Running server if runned code
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)


    