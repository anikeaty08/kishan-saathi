"""Persistence models for linked multi-image diagnosis cases."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class DiagnosisCase(Base):
    """Farmer-owned case that groups initial images and later retakes."""

    __tablename__ = "diagnosis_cases"
    __table_args__ = (
        CheckConstraint(
            "status IN ('processing', 'completed', 'failed')",
            name="ck_diagnosis_cases_status",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    farm_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("farms.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    plot_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("plots.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    crop_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("crops.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    plant_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    title: Mapped[str] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(20), default="processing")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DiagnosisImage(Base):
    """One sanitized private leaf image belonging to exactly one case."""

    __tablename__ = "diagnosis_images"
    __table_args__ = (
        UniqueConstraint("object_key", name="uq_diagnosis_images_object_key"),
        CheckConstraint("width >= 32 AND height >= 32", name="ck_diagnosis_images_dimensions"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    case_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), index=True
    )
    object_key: Mapped[str] = mapped_column(String(512))
    size_bytes: Mapped[int] = mapped_column(Integer)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    captured_or_uploaded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    quality_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    quality_flags: Mapped[list[str]] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DiagnosisAssessment(Base):
    """One combined model assessment; only one is active per case."""

    __tablename__ = "diagnosis_assessments"
    __table_args__ = (
        CheckConstraint("confidence BETWEEN 0 AND 1", name="ck_assessments_confidence"),
        CheckConstraint(
            "confidence_label IN ('low', 'medium', 'high')",
            name="ck_assessments_confidence_label",
        ),
        Index(
            "uq_diagnosis_assessments_active_case",
            "case_id",
            unique=True,
            postgresql_where=text("is_active"),
            sqlite_where=text("is_active = 1"),
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    case_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), index=True
    )
    predicted_crop: Mapped[str] = mapped_column(String(100))
    primary_disease: Mapped[str] = mapped_column(String(200))
    confidence: Mapped[float] = mapped_column(Float)
    confidence_label: Mapped[str] = mapped_column(String(10))
    model_name: Mapped[str] = mapped_column(String(100))
    model_version: Mapped[str] = mapped_column(String(100))
    is_active: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DiagnosisPrediction(Base):
    """Ranked combined or per-image evidence retained for error analysis."""

    __tablename__ = "diagnosis_predictions"
    __table_args__ = (
        CheckConstraint("confidence BETWEEN 0 AND 1", name="ck_predictions_confidence"),
        CheckConstraint("rank >= 1", name="ck_predictions_rank"),
        CheckConstraint("scope IN ('combined', 'image')", name="ck_predictions_scope"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    assessment_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_assessments.id", ondelete="CASCADE"), index=True
    )
    image_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("diagnosis_images.id", ondelete="CASCADE"), nullable=True, index=True
    )
    scope: Mapped[str] = mapped_column(String(10))
    rank: Mapped[int] = mapped_column(Integer)
    crop_name: Mapped[str] = mapped_column(String(100))
    disease_name: Mapped[str] = mapped_column(String(200))
    confidence: Mapped[float] = mapped_column(Float)


class DiagnosisFeedback(Base):
    """Farmer correction retained separately from immutable model output."""

    __tablename__ = "diagnosis_feedback"
    __table_args__ = (UniqueConstraint("case_id", name="uq_diagnosis_feedback_case"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    farmer_id: Mapped[UUID] = mapped_column(
        ForeignKey("farmer_profiles.id", ondelete="RESTRICT"), index=True
    )
    case_id: Mapped[UUID] = mapped_column(
        ForeignKey("diagnosis_cases.id", ondelete="CASCADE"), index=True
    )
    is_incorrect: Mapped[bool] = mapped_column(Boolean)
    corrected_crop: Mapped[str | None] = mapped_column(String(100), nullable=True)
    corrected_disease: Mapped[str | None] = mapped_column(String(200), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
