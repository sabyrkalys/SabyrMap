from fastapi import FastAPI

from app.routers.auth import router as auth_router
from app.routers.waypoints import router as waypoints_router

app = FastAPI(title="AlpineQuest SaaS API")
app.include_router(auth_router)
app.include_router(waypoints_router)


@app.get("/health")
def health():
    return {"status": "ok"}
