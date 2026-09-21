import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models.user import User
from app.services.auth import InvalidTokenError, decode_access_token, hash_password
from app.services.organizations import create_personal_organization_and_owner

bearer_scheme = HTTPBearer(auto_error=False)

_CREDENTIALS_ERROR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
)


def _get_or_create_single_user(db: Session) -> User:
    user = (
        db.query(User)
        .filter(User.email == settings.SINGLE_USER_EMAIL, User.deleted_at.is_(None))
        .first()
    )
    if user is None:
        # A well-formed bcrypt hash of a random secret: nobody can log in as
        # this user, and /auth/login stays a clean 401 instead of a crash.
        user = create_personal_organization_and_owner(
            db,
            email=settings.SINGLE_USER_EMAIL,
            password_hash=hash_password(secrets.token_urlsafe(32)),
        )
    return user


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if settings.AUTH_DISABLED:
        return _get_or_create_single_user(db)

    if credentials is None:
        raise _CREDENTIALS_ERROR

    try:
        user_id = decode_access_token(credentials.credentials)
    except InvalidTokenError:
        raise _CREDENTIALS_ERROR

    user = db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
    if user is None:
        raise _CREDENTIALS_ERROR

    return user
