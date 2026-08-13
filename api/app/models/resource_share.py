import uuid
from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, UniqueConstraint
from sqlalchemy import Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.enums import Permission, ShareScope


class ResourceShare(Base):
    __tablename__ = "resource_shares"
    __table_args__ = (
        Index("ix_resource_shares_resource_id", "resource_id"),
        Index("ix_resource_shares_user_id", "shared_with_user_id"),
        UniqueConstraint("resource_id", "shared_with_user_id", name="uq_resource_shares_resource_user"),
        CheckConstraint(
            "(scope = 'user' AND shared_with_user_id IS NOT NULL) OR "
            "(scope = 'organization' AND shared_with_user_id IS NULL)",
            name="ck_resource_shares_scope_consistency",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    resource_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("resources.id", ondelete="CASCADE"), nullable=False
    )
    shared_with_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=True
    )
    scope: Mapped[ShareScope] = mapped_column(
        SAEnum(ShareScope, name="share_scope", values_callable=lambda x: [e.value for e in x]), nullable=False
    )
    permission: Mapped[Permission] = mapped_column(
        SAEnum(Permission, name="permission", values_callable=lambda x: [e.value for e in x]), nullable=False
    )
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )
