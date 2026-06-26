from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import xml.etree.ElementTree as ET
import re
import ollama 

app = FastAPI(title="Styslo Backend API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

RSS_URLS = {
    "general": "https://tsn.ua/rss/full.rss",
    "sport": "https://tsn.ua/rss/sport.rss",
    "technologies": "https://tsn.ua/rss/science.rss",
    "politics": "https://tsn.ua/rss/politics.rss",
}

class NewsRequest(BaseModel):
    channel: str
    compression: str 

def clean_html(raw_html: str) -> str:
    if not raw_html:
        return ""
    # Видаляємо все, що в тегах <>
    clean_text = re.sub(r'<[^>]*>', '', raw_html)
    # Прибираємо HTML сутності на кшталт &nbsp;
    clean_text = re.sub(r'&[^;]+;', '', clean_text)
    return clean_text.strip()


@app.get("/")
def read_root():
    return {"status": "Styslo Backend is running"}

def summarize_news(news_text: str) -> str:
    response = ollama.generate(
        model='llama3',
        prompt=f"Стислий підсумок українською мовою в 2-3 реченнях для радіо-дайджесту: {news_text}"
    )
    return response['response']

@app.post("/api/news")
async def get_news(request: NewsRequest):
    channel_key = request.channel.lower()
    
    url = RSS_URLS.get(channel_key)
    if not url:
        if request.channel.startswith("http"):
            url = request.channel
        else:
            raise HTTPException(status_code=400, detail="Channel not found or invalid URL")

    try:

        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=10.0)
        
        if response.status_code != 200:
            raise HTTPException(status_code=502, detail="Failed to fetch RSS feed from source")

        root = ET.fromstring(response.content)
        items = root.findall(".//item")

        if not items:
            return {"title": "Empty", "content": "Empty"}

        latest_item = items[0]
        title = latest_item.find("title").text if latest_item.find("title") is not None else "Without tite"
        
        description_node = latest_item.find("description")
        raw_description = description_node.text if description_node is not None else ""
        clean_description = clean_html(raw_description)

        if request.compression == "Compressed(only main thought)":
            final_content = title
        else:
            final_content = f"{title}. {clean_description}"

        return {
            "title": title,
            "content": final_content,
            "channel": request.channel
        }

    except ET.ParseError:
        raise HTTPException(status_code=500, detail="Error parsing RSS XML data")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

