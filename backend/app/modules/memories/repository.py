"""Owner-scoped canonical memory persistence."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.chats.models import ChatSession
from app.modules.memories.models import ChatMemoryConnection, MemoryCaptureJob, ScopedMemoryFact


class MemoryRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_connection(self, farmer_id: UUID, chat_id: UUID) -> ChatMemoryConnection | None:
        result = await self.session.execute(
            select(ChatMemoryConnection).where(
                ChatMemoryConnection.farmer_id == farmer_id,
                ChatMemoryConnection.chat_id == chat_id,
            )
        )
        return result.scalar_one_or_none()

    async def list_connection_facts(self, farmer_id: UUID, chat_id: UUID) -> list[ScopedMemoryFact]:
        result = await self.session.scalars(
            select(ScopedMemoryFact)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.source_chat_id == chat_id,
                ScopedMemoryFact.index_status != "deleting",
            )
            .order_by(ScopedMemoryFact.created_at)
        )
        return list(result)

    async def list_farm(
        self,
        farmer_id: UUID,
        farm_id: UUID,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[ScopedMemoryFact]:
        result = await self.session.scalars(
            select(ScopedMemoryFact)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.farm_id == farm_id,
                ScopedMemoryFact.index_status != "deleting",
            )
            .order_by(ScopedMemoryFact.created_at.desc(), ScopedMemoryFact.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def list_plot(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[ScopedMemoryFact]:
        result = await self.session.scalars(
            select(ScopedMemoryFact)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.plot_id == plot_id,
                ScopedMemoryFact.index_status != "deleting",
            )
            .order_by(ScopedMemoryFact.created_at.desc(), ScopedMemoryFact.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def get_fact(
        self, farmer_id: UUID, fact_id: UUID, *, for_update: bool = False
    ) -> ScopedMemoryFact | None:
        statement = select(ScopedMemoryFact).where(
            ScopedMemoryFact.id == fact_id,
            ScopedMemoryFact.farmer_id == farmer_id,
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement.execution_options(populate_existing=True))
        return result.scalar_one_or_none()

    async def facts_by_normalized(
        self,
        farmer_id: UUID,
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
        normalized: set[str],
    ) -> dict[str, ScopedMemoryFact]:
        if not normalized:
            return {}
        result = await self.session.scalars(
            select(ScopedMemoryFact).where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.farm_id == farm_id,
                ScopedMemoryFact.plot_id == plot_id,
                ScopedMemoryFact.normalized_text.in_(normalized),
                ScopedMemoryFact.index_status != "deleting",
            )
        )
        return {fact.normalized_text: fact for fact in result}

    async def list_diagnosis_facts(
        self,
        farmer_id: UUID,
        case_id: UUID,
        *,
        for_update: bool = False,
    ) -> list[ScopedMemoryFact]:
        statement = (
            select(ScopedMemoryFact)
            .join(ChatSession, ChatSession.id == ScopedMemoryFact.source_chat_id)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ChatSession.farmer_id == farmer_id,
                ChatSession.diagnosis_case_id == case_id,
            )
        )
        if for_update:
            statement = statement.with_for_update(of=ScopedMemoryFact)
        result = await self.session.scalars(statement)
        return list(result)

    async def get_capture_job(
        self,
        job_id: UUID,
        *,
        lease_token: UUID | None = None,
        for_update: bool = False,
    ) -> MemoryCaptureJob | None:
        statement = select(MemoryCaptureJob).where(MemoryCaptureJob.id == job_id)
        if lease_token is not None:
            statement = statement.where(
                MemoryCaptureJob.lease_token == lease_token,
                MemoryCaptureJob.status == "processing",
            )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def delete_capture_job(self, value: MemoryCaptureJob) -> None:
        await self.session.delete(value)

    async def due_capture_jobs(self, *, now: datetime, limit: int) -> list[MemoryCaptureJob]:
        result = await self.session.scalars(
            select(MemoryCaptureJob)
            .where(
                MemoryCaptureJob.next_attempt_at <= now,
                or_(
                    MemoryCaptureJob.status == "pending",
                    and_(
                        MemoryCaptureJob.status == "processing",
                        MemoryCaptureJob.lease_expires_at <= now,
                    ),
                ),
            )
            .order_by(MemoryCaptureJob.next_attempt_at, MemoryCaptureJob.created_at)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        return list(result)

    def add(self, value: ChatMemoryConnection | ScopedMemoryFact | MemoryCaptureJob) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def refresh(
        self, value: ChatMemoryConnection | ScopedMemoryFact | MemoryCaptureJob
    ) -> None:
        await self.session.refresh(value)

    async def delete(self, value: ScopedMemoryFact) -> None:
        await self.session.delete(value)

    async def delete_connection(self, value: ChatMemoryConnection) -> None:
        await self.session.delete(value)

    async def rollback(self) -> None:
        await self.session.rollback()
