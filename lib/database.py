from datetime import datetime
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import declarative_base, sessionmaker, relationship

DATABASE_URL = "sqlite:///./styslo.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    subscriptions = relationship("UserCategory", back_populates="user", cascade="all, delete-orphan")
    digests = relationship("Digest", back_populates="user", cascade="all, delete-orphan")

class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False, index=True)

    sources = relationship("Source", back_populates="category", cascade="all, delete-orphan")
    digests = relationship("Digest", back_populates="category", cascade="all, delete-orphan")
    subscriptions = relationship("UserCategory", back_populates="category", cascade="all, delete-orphan")

class UserCategory(Base):
    __tablename__ = "user_categories"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="CASCADE"), primary_key=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="subscriptions")
    category = relationship("Category", back_populates="subscriptions")

class Source(Base):
    __tablename__ = "sources"
    
    id = Column(Integer, primary_key=True, index=True)
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=False)
    name = Column(String, nullable=False)
    source_type = Column(String, nullable=False)
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
    published_at = Column(DateTime, nullable=True, index=True) 
    parsed_at = Column(DateTime, default=datetime.utcnow) 
    

    source = relationship("Source", back_populates="articles")
    digest_links = relationship("DigestArticle", back_populates="article", cascade="all, delete-orphan")


class Digest(Base):
    __tablename__ = "digests"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id =Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    category_id = Column(Integer,ForeignKey("categories.id"),nullable=False,index=True)
    compression_level = Column(String(100), nullable=False)
    summary_text = Column(Text, nullable=False)        
    ai_model = Column(String(100),nullable=True)
    audio_url = Column(String, nullable=True)          
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    
    user = relationship("User", back_populates="digests")
    category = relationship("Category", back_populates="digests")
    article_links = relationship("DigestArticle", back_populates="digest", cascade="all, delete-orphan")
    audio_files = relationship("AudioFile", back_populates="digest", cascade="all, delete-orphan")
    

class DigestArticle(Base):
    __tablename__ = "digest_articles"

    digest_id = Column(Integer, ForeignKey("digests.id", ondelete="CASCADE"), primary_key=True)
    article_id = Column(Integer, ForeignKey("articles.id", ondelete="CASCADE"), primary_key=True)
    position = Column(Integer, nullable=True)

    digest = relationship("Digest", back_populates="article_links")
    article = relationship("Article", back_populates="digest_links")


class AudioFile(Base):
    __tablename__ = "audio_files"

    id = Column(Integer, primary_key=True, index=True)
    digest_id = Column(Integer, ForeignKey("digests.id", ondelete="CASCADE"), nullable=False, index=True)
    file_url = Column(String(1000), nullable=False)
    file_name = Column(String(255), nullable=True)
    mime_type = Column(String(100), default="audio/mpeg")
    language = Column(String(20), default="uk-UA")
    voice_name = Column(String(100), nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    digest = relationship("Digest", back_populates="audio_files")


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