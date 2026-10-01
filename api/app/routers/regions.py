import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models.region_job import RegionJob
from app.models.user import User
from app.schemas.regions import (
    EstimateRequest,
    EstimateResponse,
    RegionListResponse,
    RegionRequest,
    RegionResponse,
)
from app.services import regions
from app.services.regions import RegionError

router = APIRouter(prefix="/regions", tags=["regions"])


def _http(error: RegionError) -> HTTPException:
    return HTTPException(status_code=error.status_code, detail=error.detail)


def _to_response(job: RegionJob) -> RegionResponse:
    return RegionResponse(
        id=job.id,
        map_id=job.map_id,
        name=job.name,
        bbox=list(regions.job_bbox(job)),
        max_zoom=job.max_zoom,
        version=job.version,
        status=job.status,
        progress=job.progress,
        size_bytes=job.size_bytes,
        files=job.files or [],
        error=job.error,
        created_at=job.created_at,
        ready_at=job.ready_at,
        expires_at=job.expires_at,
    )


@router.post("/estimate", response_model=EstimateResponse)
def estimate_region(
    payload: EstimateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        entry = regions.get_downloadable_map(db, payload.map_id)
        regions.check_max_zoom(payload.max_zoom)
        result = regions.estimate(entry, regions.normalize_bbox(payload.bbox), payload.max_zoom)
    except RegionError as e:
        raise _http(e)
    return EstimateResponse(
        parts=[{"tileset": p.tileset, "tiles": p.tiles, "bytes": p.bytes} for p in result.parts],
        style_bytes=result.style_bytes,
        total_bytes=result.total_bytes,
        max_bytes=settings.REGION_MAX_BYTES,
        allowed=result.allowed,
    )


@router.post("", response_model=RegionResponse)
def create_region(
    payload: RegionRequest,
    response: Response,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        job, created = regions.create_job(
            db,
            user_id=user.id,
            map_id=payload.map_id,
            bbox=payload.bbox,
            max_zoom=payload.max_zoom,
            name=payload.name,
        )
    except RegionError as e:
        raise _http(e)
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return _to_response(job)


@router.get("", response_model=RegionListResponse)
def list_regions(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    jobs = (
        db.query(RegionJob)
        .filter(RegionJob.user_id == user.id)
        .order_by(RegionJob.created_at.desc())
        .all()
    )
    return RegionListResponse(items=[_to_response(j) for j in jobs])


@router.get("/{job_id}", response_model=RegionResponse)
def get_region(job_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        return _to_response(regions.get_own_job(db, user.id, job_id))
    except RegionError as e:
        raise _http(e)


@router.get("/{job_id}/download/{file_name}")
def download_region_file(
    job_id: uuid.UUID,
    file_name: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """nginx serves the file itself (X-Accel-Redirect to its internal
    /regions-files/ location); the API only checks the owner."""
    try:
        job = regions.get_own_job(db, user.id, job_id)
        entry = regions.file_entry(job, file_name)
    except RegionError as e:
        raise _http(e)
    return Response(
        status_code=status.HTTP_200_OK,
        media_type="application/octet-stream",
        headers={
            "X-Accel-Redirect": regions.accel_redirect_path(job, entry["name"]),
            "Content-Disposition": f'attachment; filename="{entry["name"]}"',
        },
    )


@router.delete("/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_region(job_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # The folder is removed by the worker's cleanup once no job points at it.
    try:
        job = regions.get_own_job(db, user.id, job_id)
    except RegionError as e:
        raise _http(e)
    db.delete(job)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
