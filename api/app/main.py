from fastapi import FastAPI

from app.routers.auth import router as auth_router

app = FastAPI(title="AlpineQuest SaaS API")
app.include_router(auth_router)


@app.get("/health")
def health():
    return {"status": "ok"}
