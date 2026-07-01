from datetime import datetime
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import declarative_base, sessionmaker, relationship

DATABASE_URL = "sqlite:///./styslo.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

class Category(Base):
    __tablename__ = "categories"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False, index=True)
    

    sources = relationship("Source", back_populates="category", cascade="all, delete-orphan")


class Source(Base):
    __tablename__ = "sources"
    
    id = Column(Integer, primary_key=True, index=True)
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=False)
    name = Column(String, nullable=False)
    source_type = Column(String, nullable=False)  # "rss", "telegram", "api" in future
    url_or_credentials = Column(String, nullable=False)  
    is_active = Column(Boolean, default=True)
    

    category = relationship("Category", back_populates="sources")
    articles = relationship("Article", back_populates="source", cascade="all, delete-orphan")


class Article(Base):
    __tablename__ = "articles"
    
    id = Column(Integer, primary_key=True, index=True)
    source_id = Column(Integer, ForeignKey("sources.id"), nullable=False)
    title = Column(String, nullable=False)
    source_url = Column(String, nullable=True)  
    raw_text = Column(Text, nullable=False)    
    published_at = Column(DateTime, nullable=True) 
    parsed_at = Column(DateTime, default=datetime.utcnow) 
    

    source = relationship("Source", back_populates="articles")
    digests = relationship("Digest", back_populates="article", cascade="all, delete-orphan")


class Digest(Base):
    __tablename__ = "digests"
    
    id = Column(Integer, primary_key=True, index=True)
    article_id = Column(Integer, ForeignKey("articles.id"), nullable=False)
    compression_level = Column(String, nullable=False) 
    summary_text = Column(Text, nullable=False)        
    audio_url = Column(String, nullable=True)          
    created_at = Column(DateTime, default=datetime.utcnow)
    
    article = relationship("Article", back_populates="digests")




def init_db():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        if db.query(Category).count() == 0:
            print("DB is empty. Populating with test data...")
            
            general = Category(name="General")
            techno = Category(name="Tecnologies 💻")
            politics = Category(name="Politics 🏛️")
            
            db.add_all([general, techno, politics])
            db.commit() 
            
            sources = [
                Source(category_id=general.id, name="BBC News", source_type="rss", url_or_credentials="http://feeds.bbci.co.uk/news/rss.xml"),
                
                Source(category_id=techno.id, name="ТСН Наука", source_type="rss", url_or_credentials="https://tsn.ua/rss/science.rss"),
                Source(category_id=techno.id, name="ITC.ua (Тест)", source_type="rss", url_or_credentials="https://itc.ua/feed/"), 
                
                Source(category_id=politics.id, name="ТСН Політика(Тест)", source_type="rss", url_or_credentials="https://tsn.ua/rss/politics.rss"),
                Source(category_id=politics.id, name="УНІАН Політика (Тест)", source_type="rss", url_or_credentials="https://unian.ua/rss/politics.xml")
            ]
            
            db.add_all(sources)
            db.commit()
            print("Test data added successfully!")
    finally:
        db.close()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

if __name__ == "__main__":
    init_db()