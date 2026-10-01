from fastapi import FastAPI

from app.routers.auth import router as auth_router
from app.routers.maps import router as maps_router
from app.routers.regions import router as regions_router
from app.routers.shares import router as shares_router
from app.routers.tracks import router as tracks_router
from app.routers.waypoints import router as waypoints_router

app = FastAPI(title="SabyrMap SaaS API")
app.include_router(auth_router)
app.include_router(waypoints_router)
app.include_router(tracks_router)
app.include_router(shares_router)
app.include_router(maps_router)
app.include_router(regions_router)


@app.get("/health")
def health():
    return {"status": "ok"}
