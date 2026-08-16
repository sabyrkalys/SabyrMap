import uuid
from datetime import datetime

from pydantic import BaseModel, model_validator

from app.models.enums import Permission, ShareScope


class ShareCreateRequest(BaseModel):
    scope: ShareScope
    permission: Permission
    shared_with_user_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _validate_target(self) -> "ShareCreateRequest":
        if self.scope == ShareScope.USER and self.shared_with_user_id is None:
            raise ValueError("shared_with_user_id is required when scope is 'user'")
        if self.scope == ShareScope.ORGANIZATION and self.shared_with_user_id is not None:
            raise ValueError("shared_with_user_id must be omitted when scope is 'organization'")
        return self


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
