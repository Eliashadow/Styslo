import feedparser
from datetime import datetime
import time
import re
from sqlalchemy.orm import Session
from database import SessionLocal, Source, Article  

def clean_html(raw_html):
    if not raw_html:
        return ""
    clean_re = re.compile('<.*?>')
    text = re.sub(clean_re, '', raw_html)
    text = " ".join(text.split())
    return text


def parse_rss_sources(db: Session):
    try:

        rss_sources = db.query(Source).filter(Source.source_type == "rss", Source.is_active == True).all()
        print(_dt_log(), f"Found {len(rss_sources)} active RSS sources for polling.")

        for source in rss_sources:

            url = getattr(source, "url_or_credentials", getattr(source, "url", ""))
            print(_dt_log(), f"Parsing source: {source.name} ({url})")
            
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
            print(_dt_log(), f"Successfully added {new_articles_count} new articles from source {source.name}.")
            
    except Exception as e:
        print(_dt_log(), f"Error occurred while parsing: {e}")
        db.rollback()

def _dt_log():
    return f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"

if __name__ == "__main__":
    print("Starting news collection manually...")
    standalone_db = SessionLocal()
    try:
        parse_rss_sources(standalone_db)
    finally:
        standalone_db.close()
    print("News collection completed.")