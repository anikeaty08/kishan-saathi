"""Bounded owner-scoped queries for the combined chronological timeline."""

from collections.abc import Collection
from datetime import datetime
from typing import TypeVar
from uuid import UUID

from sqlalchemy import Select, and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import InstrumentedAttribute
from sqlalchemy.sql.elements import ColumnElement

from app.modules.chats.models import ChatSession
from app.modules.diagnoses.models import DiagnosisAssessment, DiagnosisCase
from app.modules.farms.models import (
    Activity,
    ActivityPhoto,
    Crop,
    CropCycleEvent,
    CropStageEvent,
)
from app.modules.history.schemas import TimelineCategory, TimelineItem
from app.modules.memories.models import ChatMemoryConnection
from app.modules.reminders.models import ReminderEvent

T = TypeVar("T")


class HistoryRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def timeline(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        *,
        crop_id: UUID | None,
        categories: Collection[TimelineCategory],
        date_from: datetime | None,
        date_to: datetime | None,
        per_category_limit: int,
    ) -> list[TimelineItem]:
        items: list[TimelineItem] = []
        if TimelineCategory.DIAGNOSIS in categories:
            items.extend(
                await self._diagnoses(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
            items.extend(
                await self._assessments(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        if TimelineCategory.CHAT in categories:
            items.extend(
                await self._chats(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        if TimelineCategory.REMINDER in categories:
            items.extend(
                await self._reminders(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        if TimelineCategory.ACTIVITY in categories:
            items.extend(
                await self._activities(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        if TimelineCategory.CROP_STAGE in categories:
            items.extend(
                await self._crop_events(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        if TimelineCategory.CROP_CYCLE in categories:
            items.extend(
                await self._crop_cycle_events(
                    farmer_id, plot_id, crop_id, date_from, date_to, per_category_limit
                )
            )
        return items

    async def _diagnoses(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = select(DiagnosisCase).where(
            DiagnosisCase.farmer_id == farmer_id, DiagnosisCase.plot_id == plot_id
        )
        if crop_id is not None:
            statement = statement.where(DiagnosisCase.crop_id == crop_id)
        statement = self._dates(statement, DiagnosisCase.created_at, date_from, date_to)
        values = await self._session.scalars(
            statement.order_by(DiagnosisCase.created_at.desc()).limit(limit)
        )
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.DIAGNOSIS,
                event_code="diagnosis.case_created",
                occurred_at=value.created_at,
                plot_id=plot_id,
                crop_id=value.crop_id,
                reference_id=value.id,
                data={
                    "status": value.status,
                    "plant_name": value.plant_name,
                    "title": value.title,
                },
            )
            for value in values
        ]

    async def _chats(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        scan_scope: ColumnElement[bool] = and_(
            ChatSession.scope_type == "scan",
            DiagnosisCase.farmer_id == farmer_id,
            DiagnosisCase.plot_id == plot_id,
        )
        if crop_id is not None:
            scan_scope = and_(scan_scope, DiagnosisCase.crop_id == crop_id)
            scope: ColumnElement[bool] = scan_scope
        else:
            connected = select(ChatMemoryConnection.chat_id).where(
                ChatMemoryConnection.farmer_id == farmer_id,
                ChatMemoryConnection.plot_id == plot_id,
            )
            scope = or_(
                and_(
                    ChatSession.scope_type == "plot",
                    ChatSession.plot_id == plot_id,
                ),
                scan_scope,
                ChatSession.id.in_(connected),
            )
        statement = (
            select(ChatSession, DiagnosisCase.crop_id)
            .outerjoin(
                DiagnosisCase,
                and_(
                    DiagnosisCase.id == ChatSession.diagnosis_case_id,
                    DiagnosisCase.farmer_id == farmer_id,
                ),
            )
            .where(ChatSession.farmer_id == farmer_id, scope)
        )
        if date_from is not None:
            statement = statement.where(ChatSession.created_at >= date_from)
        if date_to is not None:
            statement = statement.where(ChatSession.created_at <= date_to)
        rows = await self._session.execute(
            statement.order_by(ChatSession.created_at.desc()).limit(limit)
        )
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.CHAT,
                event_code="chat.session_created",
                occurred_at=value.created_at,
                plot_id=plot_id,
                crop_id=case_crop_id,
                reference_id=value.id,
                data={"scope_type": value.scope_type, "title": value.title},
            )
            for value, case_crop_id in rows
        ]

    async def _assessments(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = (
            select(DiagnosisAssessment)
            .join(DiagnosisCase, DiagnosisCase.id == DiagnosisAssessment.case_id)
            .where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisCase.plot_id == plot_id,
            )
        )
        if crop_id is not None:
            statement = statement.where(DiagnosisCase.crop_id == crop_id)
        statement = self._dates(statement, DiagnosisAssessment.created_at, date_from, date_to)
        rows = await self._session.execute(
            statement.add_columns(DiagnosisCase.crop_id)
            .order_by(DiagnosisAssessment.created_at.desc())
            .limit(limit)
        )
        return [
            TimelineItem(
                id=assessment.id,
                category=TimelineCategory.DIAGNOSIS,
                event_code="diagnosis.assessment_created",
                occurred_at=assessment.created_at,
                plot_id=plot_id,
                crop_id=case_crop_id,
                reference_id=assessment.case_id,
                data={
                    "predicted_crop": assessment.predicted_crop,
                    "primary_disease": assessment.primary_disease,
                    "confidence": assessment.confidence,
                    "confidence_label": assessment.confidence_label,
                    "is_active": assessment.is_active,
                    "model_name": assessment.model_name,
                    "model_version": assessment.model_version,
                },
            )
            for assessment, case_crop_id in rows
        ]

    async def _reminders(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = select(ReminderEvent).where(
            ReminderEvent.farmer_id == farmer_id, ReminderEvent.plot_id == plot_id
        )
        if crop_id is not None:
            statement = statement.where(ReminderEvent.crop_id == crop_id)
        statement = self._dates(statement, ReminderEvent.occurred_at, date_from, date_to)
        values = await self._session.scalars(
            statement.order_by(ReminderEvent.occurred_at.desc()).limit(limit)
        )
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.REMINDER,
                event_code=f"reminder.{value.event_type}",
                occurred_at=value.occurred_at,
                plot_id=plot_id,
                crop_id=value.crop_id,
                reference_id=value.reminder_id,
                data={
                    "series_id": str(value.series_id),
                    "previous_due_at": (
                        value.previous_due_at.isoformat()
                        if value.previous_due_at is not None
                        else None
                    ),
                    "due_at": value.due_at.isoformat(),
                },
            )
            for value in values
        ]

    async def _activities(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = select(Activity).where(
            Activity.farmer_id == farmer_id, Activity.plot_id == plot_id
        )
        if crop_id is not None:
            statement = statement.where(Activity.crop_id == crop_id)
        statement = self._dates(statement, Activity.occurred_at, date_from, date_to)
        values = await self._session.scalars(
            statement.order_by(Activity.occurred_at.desc()).limit(limit)
        )
        activities = list(values)
        photo_counts: dict[UUID, int] = {}
        if activities:
            counts = await self._session.execute(
                select(ActivityPhoto.activity_id, func.count())
                .where(
                    ActivityPhoto.farmer_id == farmer_id,
                    ActivityPhoto.activity_id.in_([value.id for value in activities]),
                )
                .group_by(ActivityPhoto.activity_id)
            )
            photo_counts = {activity_id: int(count) for activity_id, count in counts}
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.ACTIVITY,
                event_code="activity.recorded",
                occurred_at=value.occurred_at,
                plot_id=plot_id,
                crop_id=value.crop_id,
                reference_id=value.id,
                data={
                    "title": value.title,
                    "notes": value.notes,
                    "photo_count": photo_counts.get(value.id, 0),
                },
            )
            for value in activities
        ]

    async def _crop_events(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = (
            select(CropStageEvent)
            .join(Crop, Crop.id == CropStageEvent.crop_id)
            .where(
                CropStageEvent.farmer_id == farmer_id,
                Crop.plot_id == plot_id,
            )
        )
        if crop_id is not None:
            statement = statement.where(CropStageEvent.crop_id == crop_id)
        statement = self._dates(statement, CropStageEvent.observed_at, date_from, date_to)
        values = await self._session.scalars(
            statement.order_by(CropStageEvent.observed_at.desc()).limit(limit)
        )
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.CROP_STAGE,
                event_code="crop.stage_updated",
                occurred_at=value.observed_at,
                plot_id=plot_id,
                crop_id=value.crop_id,
                reference_id=value.crop_id,
                data={"stage": value.stage},
            )
            for value in values
        ]

    async def _crop_cycle_events(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        crop_id: UUID | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[TimelineItem]:
        statement = (
            select(CropCycleEvent)
            .join(Crop, Crop.id == CropCycleEvent.crop_id)
            .where(
                CropCycleEvent.farmer_id == farmer_id,
                Crop.plot_id == plot_id,
            )
        )
        if crop_id is not None:
            statement = statement.where(CropCycleEvent.crop_id == crop_id)
        statement = self._dates(statement, CropCycleEvent.occurred_at, date_from, date_to)
        values = await self._session.scalars(
            statement.order_by(CropCycleEvent.occurred_at.desc()).limit(limit)
        )
        return [
            TimelineItem(
                id=value.id,
                category=TimelineCategory.CROP_CYCLE,
                event_code=f"crop.cycle_{value.event_type}",
                occurred_at=value.occurred_at,
                plot_id=plot_id,
                crop_id=value.crop_id,
                reference_id=value.crop_id,
                data={"event_date": value.event_date.isoformat()},
            )
            for value in values
        ]

    @staticmethod
    def _dates(
        statement: Select[tuple[T]],
        column: InstrumentedAttribute[datetime],
        date_from: datetime | None,
        date_to: datetime | None,
    ) -> Select[tuple[T]]:
        if date_from is not None:
            statement = statement.where(column >= date_from)
        if date_to is not None:
            statement = statement.where(column <= date_to)
        return statement
