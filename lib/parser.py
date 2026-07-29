import feedparser
from datetime import datetime
import time
import re
import requests
from telethon import TelegramClient
from sqlalchemy.orm import Session
from database import SessionLocal, Source, Article  
from logger import Logger, Timer, LogLevel

version = 'test'

l = Logger(colors = True, frame = 100, version=version, min_level=LogLevel.DEBUG)

API_ID = 1234567 
API_HASH = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

def clean_html(raw_html):
    if not raw_html:
        return ""
    clean_re = re.compile('<.*?>')
    text = re.sub(clean_re, '', raw_html)
    text = " ".join(text.split())
    return text

async def parse_telegram_sources_async(db: Session):
    try:
        tg_sources = db.query(Source).filter(Source.source_type == "telegram", Source.is_active == True).all()
        l.info(f"Found {len(tg_sources)} active Telegram sources for polling via Telethon.")

        if not tg_sources:
            return

        async with TelegramClient('styslo_session', API_ID, API_HASH) as client:
            for source in tg_sources:
                channel_username = getattr(source, "url_or_credentials", "").strip()
                if not channel_username:
                    continue
                
                l.info(f"Parsing Telegram source via Telethon: {source.name} ({channel_username})")
                new_articles_count = 0
                
                try:
                    async for message in client.iter_messages(channel_username, limit=10):
                        if not message.text:
                            continue
                            
                        title = message.text.split('\n')[0][:100]  
                        link = f"https://t.me/{channel_username.replace('@', '')}/{message.id}"
                        cleaned_text = clean_html(message.text)
                        
                        published_at = message.date.replace(tzinfo=None) if message.date else datetime.utcnow()

                        exists = db.query(Article).filter(Article.source_url == link).first()
                        if exists:
                            continue 

                        new_article = Article(
                            source_id=source.id,
                            title=title,
                            source_url=link,
                            raw_text=cleaned_text,
                            published_at=published_at
                        )
                        db.add(new_article)
                        new_articles_count += 1
                        
                    db.commit()
                    l.info(f"Successfully added {new_articles_count} new posts from Telegram source {source.name}.")
                    
                except Exception as ex:
                    l.error(f"Error parsing channel {channel_username}: {ex}")
                    db.rollback()
            
    except Exception as e:
        l.error(f"Error occurred while initializing Telethon client: {e}")
        db.rollback()

def parse_telegram_sources(db: Session):
    import asyncio
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.create_task(parse_telegram_sources_async(db))
        else:
            loop.run_until_complete(parse_telegram_sources_async(db))
    except RuntimeError:
        asyncio.run(parse_telegram_sources_async(db))

def parse_rss_sources(db: Session):
    try:
        rss_sources = db.query(Source).filter(Source.source_type == "rss", Source.is_active == True).all()
        l.info(f"Found {len(rss_sources)} active RSS sources for polling.")

        for source in rss_sources:

            url = getattr(source, "url_or_credentials", getattr(source, "url", ""))
            l.info(f"Parsing source: {source.name} ({url})")
            
            feed = feedparser.parse(url)
            new_articles_count = 0
            
            for entry in feed.entries:
                title = entry.get("title", "Without title")
                link = entry.get("link", "")
                
                raw_text = ""
                if "content" in entry:
                    raw_text = entry.content[0].value
                elif "summary" in entry:
                    raw_text = entry.summary
                
                cleaned_text = clean_html(raw_text)
                if not cleaned_text:
                    cleaned_text = title 

                published_at = None
                if "published_parsed" in entry and entry.published_parsed:
                    published_at = datetime.fromtimestamp(time.mktime(entry.published_parsed))
                elif "updated_parsed" in entry and entry.updated_parsed:
                    published_at = datetime.fromtimestamp(time.mktime(entry.updated_parsed))
                else:
                    published_at = datetime.utcnow()


                exists = db.query(Article).filter(Article.source_url == link).first()
                if exists:
                    continue 

                new_article = Article(
                    source_id=source.id,
                    title=title,
                    source_url=link,
                    raw_text=cleaned_text,
                    published_at=published_at
                )
                db.add(new_article)
                new_articles_count += 1
            
            db.commit() 
            l.info(f"Successfully added {new_articles_count} new articles from source {source.name}.")
            
    except Exception as e:
        l.info(f"Error occurred while parsing: {e}")
        db.rollback()

def parse_api_sources(db: Session):
    try:
        api_sources = db.query(Source).filter(Source.source_type == "api", Source.is_active == True).all()
        l.info(f"Found {len(api_sources)} active API sources for polling.")

        for source in api_sources:
            api_url = getattr(source, "url_or_credentials", "")
            l.info(f"Fetching from API source: {source.name} ({api_url})")
            
            headers = {"User-Agent": "Mozilla/5.0"}
            response = requests.get(api_url, headers=headers, timeout=10)
            
            if response.status_code != 200:
                l.info(f"Failed to fetch API data for {source.name}, status code: {response.status_code}")
                continue
                
            data = response.json()
            new_articles_count = 0
            
            all_items = []
            if isinstance(data, dict):
                for key, value in data.items():
                    if key != "status" and isinstance(value, list):
                        all_items.extend(value)
            elif isinstance(data, list):
                all_items = data

            for item in all_items:
                if not isinstance(item, dict):
                    continue
                    
                title = item.get("title")
                if not title:
                    continue
                    
                link = item.get("news_link") or item.get("url") or item.get("link", "")
                raw_text = item.get("summary") or item.get("description") or item.get("content") or ""
                
                cleaned_text = clean_html(raw_text)
                if not cleaned_text:
                    cleaned_text = title
                    
                published_at = datetime.utcnow()
                published_at_str = item.get("publishedAt") or item.get("published")
                if published_at_str:
                    try:
                        published_at = datetime.fromisoformat(published_at_str.replace("Z", "+00:00")).replace(tzinfo=None)
                    except ValueError:
                        pass

                if not link:
                    continue

                exists = db.query(Article).filter(Article.source_url == link).first()
                if exists:
                    continue 

                new_article = Article(
                    source_id=source.id,
                    title=title,
                    source_url=link,
                    raw_text=cleaned_text,
                    published_at=published_at
                )
                db.add(new_article)
                new_articles_count += 1
            
            db.commit()
            l.info(f"Successfully added {new_articles_count} new articles from API source {source.name}.")
            
    except Exception as e:
        l.error(f"Error occurred while parsing API sources: {e}")
        db.rollback()

if __name__ == "__main__":
    l.info("Starting news collection manually...")
    standalone_db = SessionLocal()
    try:
        parse_rss_sources(standalone_db)
        parse_telegram_sources(standalone_db)
        parse_api_sources(standalone_db)
    finally:
        standalone_db.close()
    l.info("News collection completed.")