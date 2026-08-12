"""Owner-scoped chat persistence."""

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.chats.models import ChatMessage, ChatSession


class ChatRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_chat(self, farmer_id: UUID, chat_id: UUID) -> ChatSession | None:
        result = await self.session.execute(
            select(ChatSession).where(
                ChatSession.id == chat_id, ChatSession.farmer_id == farmer_id
            )
        )
        return result.scalar_one_or_none()

    async def list_chats(
        self, farmer_id: UUID, *, include_archived: bool
    ) -> list[ChatSession]:
        statement = select(ChatSession).where(ChatSession.farmer_id == farmer_id)
        if not include_archived:
            statement = statement.where(ChatSession.archived_at.is_(None))
        result = await self.session.scalars(statement.order_by(ChatSession.updated_at.desc()))
        return list(result)

    async def recent_messages(
        self, farmer_id: UUID, chat_id: UUID, *, limit: int
    ) -> list[ChatMessage]:
        result = await self.session.scalars(
            select(ChatMessage)
            .where(
                ChatMessage.farmer_id == farmer_id,
                ChatMessage.chat_id == chat_id,
            )
            .order_by(ChatMessage.sequence.desc())
            .limit(limit)
        )
        return list(reversed(list(result)))

    async def next_sequence(self, farmer_id: UUID, chat_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.max(ChatMessage.sequence)).where(
                ChatMessage.farmer_id == farmer_id,
                ChatMessage.chat_id == chat_id,
            )
        )
        return int(value or 0) + 1

    def add(self, value: ChatSession | ChatMessage) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()

    async def refresh(self, value: ChatSession | ChatMessage) -> None:
        await self.session.refresh(value)

    async def delete(self, value: ChatSession) -> None:
        await self.session.delete(value)
