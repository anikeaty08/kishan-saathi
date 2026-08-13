"""Immutable diagnosis-report snapshots and copied report images."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import JSON, CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class DiagnosisReport(Base):
    __tablename__ = "diagnosis_reports"
    __table_args__ = (
        CheckConstraint("status IN ('active', 'revoked')", name="ck_diagnosis_reports_status"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    diagnosis_case_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(255))
    snapshot: Mapped[dict[str, object]] = mapped_column(JSON)
    approved_fields: Mapped[list[str]] = mapped_column(JSON)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(16), default="active", index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class DiagnosisReportImage(Base):
    __tablename__ = "diagnosis_report_images"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    report_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_reports.id", ondelete="CASCADE"), index=True
    )
    source_image_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_images.id", ondelete="SET NULL"), nullable=True
    )
    object_key: Mapped[str] = mapped_column(String(512), unique=True)
    size_bytes: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
