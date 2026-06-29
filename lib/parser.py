import feedparser
from datetime import datetime
import time
import re
from database import SessionLocal, Source, Article

def clean_html(raw_html):

    if not raw_html:
        return ""

    clean_re = re.compile('<.*?>')
    text = re.sub(clean_re, '', raw_html)
    text = " ".join(text.split())
    return text

def parse_rss_sources():
    db = SessionLocal()
    try:
        rss_sources = db.query(Source).filter(Source.source_type == "rss", Source.is_active == True).all()
        print(_dt_log(), f"Знайдено {len(rss_sources)} активних RSS-джерел для опитування.")

        for source in rss_sources:
            print(_dt_log(), f"Парсимо джерело: {source.name} ({source.url_or_credentials})")
            

            feed = feedparser.parse(source.url_or_credentials)
            
            new_articles_count = 0
            
            for entry in feed.entries:
                title = entry.get("title", "Без назви")
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
            print(_dt_log(), f"Успішно додано {new_articles_count} нових статей з джерела {source.name}.")
            
    except Exception as e:
        print(_dt_log(), f"Помилка під час парсингу: {e}")
        db.rollback()
    finally:
        db.close()

def _dt_log():
    return f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"

if __name__ == "__main__":
    print("Запуск збору новин...")
    parse_rss_sources()
    print("Збір завершено.")