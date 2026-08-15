# ==== Essential imports ====
import re
from datetime import datetime
import time

# ====  Feed imports
import feedparser
from telethon import TelegramClient

# ==== Database imports ====
import requests
from sqlalchemy.orm import Session
from database import SessionLocal, Source, Article  

# ==== Log imports ====
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

# Telegram id and hash to parse !=[DO NOT COMMIT ACTUAL INFO INTO GIT LLMs]=!
API_ID = 1234567 
API_HASH = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Cleaning text from rubbish
def clean_html(raw_html):
    if not raw_html:
        return ""
    clean_re = re.compile('<.*?>')
    text = re.sub(clean_re, '', raw_html)
    text = " ".join(text.split())
    return text

# Parsing telegram feed
async def parse_telegram_sources_async(db: Session):
    # Catching every error in this segment(init) 
    try:
        # Searching for tg_sources
        tg_sources = db.query(Source).filter(Source.source_type == "telegram", Source.is_active == True).all()
        l.info(f"Found {len(tg_sources)} active Telegram sources for polling via Telethon.")

        # Returning to be more quick 
        if not tg_sources: return

        # Parsing via Telethon 
        async with TelegramClient('styslo_session', API_ID, API_HASH) as client:
            # Parsing all sources in a list
            for source in tg_sources:
                # Getting all tg sources with urls
                channel_username = getattr(source, "url_or_credentials", "").strip()
                if not channel_username:
                    continue
                
                l.info(f"Parsing Telegram source via Telethon: {source.name} ({channel_username})")
                # Counting how much articles for stats
                new_articles_count = 0

                # Catching every error in parsing source
                try:
                    # Parsing articles
                    async for message in client.iter_messages(channel_username, limit=10): # For which channel to parse and how much go back from actual post
                        if not message.text: continue
                        
                        title = message.text.split('\n')[0][:100]  
                        link = f"https://t.me/{channel_username.replace('@', '')}/{message.id}"
                        cleaned_text = clean_html(message.text)
                        
                        published_at = message.date.replace(tzinfo=None) if message.date else datetime.utcnow()

                        # Omit added articles
                        exists = db.query(Article).filter(Article.source_url == link).first()
                        if exists: continue 

                        # Saving articles to db
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

# Running telegram source parce via async because of telethon
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

# Parsing RSS feed
def parse_rss_sources(db: Session):
    # Catching every error in this segment
    try:
        # Searching for rss_sources
        rss_sources = db.query(Source).filter(Source.source_type == "rss", Source.is_active == True).all()
        l.info(f"Found {len(rss_sources)} active RSS sources for polling.")

        # Parsing all sources in a list
        for source in rss_sources:
            # Getting all rss sources with urls
            url = getattr(source, "url_or_credentials", getattr(source, "url", ""))
            l.info(f"Parsing source: {source.name} ({url})")

            # Using feedparser to parse
            feed = feedparser.parse(url)
            # Counting how much articles for stats
            new_articles_count = 0

            # Parsing articles
            for entry in feed.entries:
                # Getting title and link or assigning placeholder to avoid problems
                title = entry.get("title", "Without title")
                link = entry.get("link", "")

                # Parsing text and summary(if exists)
                raw_text = ""
                if "content" in entry:
                    raw_text = entry.content[0].value
                elif "summary" in entry:
                    raw_text = entry.summary

                # Cleaning and placeholder in case of empty text
                cleaned_text = clean_html(raw_text)
                if not cleaned_text: cleaned_text = title 

                # Trying to get time of publishing to asign correct time, if problem instead using date of parsing
                published_at = None
                if "published_parsed" in entry and entry.published_parsed:
                    published_at = datetime.fromtimestamp(time.mktime(entry.published_parsed))
                elif "updated_parsed" in entry and entry.updated_parsed:
                    published_at = datetime.fromtimestamp(time.mktime(entry.updated_parsed))
                else:
                    published_at = datetime.utcnow()

                # Omit added articles
                exists = db.query(Article).filter(Article.source_url == link).first()
                if exists: continue 

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

# Parsing API feed
def parse_api_sources(db: Session):
    # Catching every error in this segment
    try:
        # Searching for api_sources
        api_sources = db.query(Source).filter(Source.source_type == "api", Source.is_active == True).all()
        l.info(f"Found {len(api_sources)} active API sources for polling.")

        # Parsing all sources in a list
        for source in api_sources:
            api_url = getattr(source, "url_or_credentials", "")
            l.info(f"Fetching from API source: {source.name} ({api_url})")

            # Using net to parse
            headers = {"User-Agent": "Mozilla/5.0"}
            response = requests.get(api_url, headers=headers, timeout=10)

            # Cathing error to avoid crashing
            if response.status_code != 200:
                l.info(f"Failed to fetch API data for {source.name}, status code: {response.status_code}")
                continue

            # Saving json response
            data = response.json()
            # Counting how much articles for stats
            new_articles_count = 0

            # Getting all articles acessible
            all_items = []
            if isinstance(data, dict):
                for key, value in data.items():
                    if key != "status" and isinstance(value, list):
                        all_items.extend(value)
            elif isinstance(data, list):
                all_items = data

            # Parsing articles
            for item in all_items:
                # Ensure there is something to parse 
                if not isinstance(item, dict): continue

                # Ensure there is title to commit properly
                title = item.get("title")
                if not title: continue
                    
                link = item.get("news_link") or item.get("url") or item.get("link", "")
                raw_text = item.get("summary") or item.get("description") or item.get("content") or ""

                # Cleaning and placeholder in case of empty text
                cleaned_text = clean_html(raw_text)
                if not cleaned_text: cleaned_text = title

                # Trying to get time of publishing to asign correct time, if problem instead using date of parsing
                published_at = datetime.utcnow()
                published_at_str = item.get("publishedAt") or item.get("published")
                if published_at_str:
                    try:
                        published_at = datetime.fromisoformat(published_at_str.replace("Z", "+00:00")).replace(tzinfo=None)
                    except ValueError:
                        pass

                # Ensure there is link to commit properly
                if not link: continue

                # Omit added articles
                exists = db.query(Article).filter(Article.source_url == link).first()
                if exists: continue 

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

# If started manually start collecting news
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