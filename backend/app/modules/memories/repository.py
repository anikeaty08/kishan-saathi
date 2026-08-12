"""Owner-scoped canonical memory persistence."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.memories.models import ChatMemoryConnection, ScopedMemoryFact


class MemoryRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_connection(
        self, farmer_id: UUID, chat_id: UUID
    ) -> ChatMemoryConnection | None:
        result = await self.session.execute(
            select(ChatMemoryConnection).where(
                ChatMemoryConnection.farmer_id == farmer_id,
                ChatMemoryConnection.chat_id == chat_id,
            )
        )
        return result.scalar_one_or_none()

    async def list_connection_facts(
        self, farmer_id: UUID, chat_id: UUID
    ) -> list[ScopedMemoryFact]:
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
        self, farmer_id: UUID, farm_id: UUID, *, limit: int = 100
    ) -> list[ScopedMemoryFact]:
        result = await self.session.scalars(
            select(ScopedMemoryFact)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.farm_id == farm_id,
                ScopedMemoryFact.index_status != "deleting",
            )
            .order_by(ScopedMemoryFact.created_at.desc())
            .limit(limit)
        )
        return list(result)

    async def list_plot(
        self, farmer_id: UUID, plot_id: UUID, *, limit: int = 100
    ) -> list[ScopedMemoryFact]:
        result = await self.session.scalars(
            select(ScopedMemoryFact)
            .where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.plot_id == plot_id,
                ScopedMemoryFact.index_status != "deleting",
            )
            .order_by(ScopedMemoryFact.created_at.desc())
            .limit(limit)
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
        result = await self.session.execute(
            statement.execution_options(populate_existing=True)
        )
        return result.scalar_one_or_none()

    async def existing_normalized(
        self, farmer_id: UUID, *, farm_id: UUID | None, plot_id: UUID | None
    ) -> set[str]:
        result = await self.session.scalars(
            select(ScopedMemoryFact.normalized_text).where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.farm_id == farm_id,
                ScopedMemoryFact.plot_id == plot_id,
                ScopedMemoryFact.index_status != "deleting",
            )
        )
        return set(result)

    def add(self, value: ChatMemoryConnection | ScopedMemoryFact) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def refresh(self, value: ChatMemoryConnection | ScopedMemoryFact) -> None:
        await self.session.refresh(value)

    async def delete(self, value: ScopedMemoryFact) -> None:
        await self.session.delete(value)

    async def delete_connection(self, value: ChatMemoryConnection) -> None:
        await self.session.delete(value)

    async def rollback(self) -> None:
        await self.session.rollback()
