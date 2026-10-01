from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.maps import catalog

router = APIRouter(prefix="/maps", tags=["maps"])


# No login: the catalog only lists what /tiles serves, and /tiles is open to
# the allowed networks anyway (nginx allow-list). The app fetches it before
# the user signs in.
@router.get("")
def list_maps(db: Session = Depends(get_db)) -> dict:
    return catalog(db)
