"""Farmer-profile SQLAlchemy persistence model."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class FarmerProfile(Base):
    """Local application profile owned by one immutable Cognito subject."""

    __tablename__ = "farmer_profiles"
    __table_args__ = (
        CheckConstraint(
            "preferred_language IS NULL OR length(preferred_language) BETWEEN 2 AND 16",
            name="ck_farmer_profiles_language_length",
        ),
        CheckConstraint(
            "area_unit IN ('acre', 'hectare')",
            name="ck_farmer_profiles_area_unit",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    cognito_sub: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    cognito_username: Mapped[str] = mapped_column(String(128))
    email: Mapped[str] = mapped_column(String(320))
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    preferred_language: Mapped[str | None] = mapped_column(String(16), nullable=True)
    area_unit: Mapped[str] = mapped_column(String(16), default="acre", server_default="acre")
    notifications_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        server_default="false",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
