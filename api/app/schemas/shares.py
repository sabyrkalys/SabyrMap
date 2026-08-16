import uuid
from datetime import datetime

from pydantic import BaseModel, field_validator

from app.models.enums import Permission, ShareScope


class ShareCreateRequest(BaseModel):
    scope: ShareScope
    permission: Permission
    shared_with_user_id: uuid.UUID | None = None

    @field_validator("shared_with_user_id")
    @classmethod
    def _validate_target(cls, v: uuid.UUID | None, info) -> uuid.UUID | None:
        scope = info.data.get("scope")
        if scope == ShareScope.USER and v is None:
            raise ValueError("shared_with_user_id is required when scope is 'user'")
        if scope == ShareScope.ORGANIZATION and v is not None:
            raise ValueError("shared_with_user_id must be omitted when scope is 'organization'")
        return v


class ShareResponse(BaseModel):
    id: uuid.UUID
    resource_id: uuid.UUID
    scope: ShareScope
    permission: Permission
    shared_with_user_id: uuid.UUID | None
    created_by: uuid.UUID
    created_at: datetime


class ShareListResponse(BaseModel):
    items: list[ShareResponse]
