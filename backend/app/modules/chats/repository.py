"""Owner-scoped chat persistence."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, exists, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.modules.chats.models import ChatMessage, ChatSendOperation, ChatSession, ChatTurn
from app.modules.diagnoses.models import DiagnosisCase
from app.modules.farms.models import Plot
from app.modules.memories.models import ChatMemoryConnection


class ChatRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_chat(
        self, farmer_id: UUID, chat_id: UUID, *, for_update: bool = False
    ) -> ChatSession | None:
        statement = select(ChatSession).where(
            ChatSession.id == chat_id, ChatSession.farmer_id == farmer_id
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def list_chats(
        self,
        farmer_id: UUID,
        *,
        include_archived: bool,
        scope_type: str | None = None,
        farm_id: UUID | None = None,
        plot_id: UUID | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[ChatSession]:
        statement = select(ChatSession).where(ChatSession.farmer_id == farmer_id)
        if not include_archived:
            statement = statement.where(ChatSession.archived_at.is_(None))
        if scope_type is not None:
            statement = statement.where(ChatSession.scope_type == scope_type)
        if farm_id is not None:
            statement = statement.where(
                or_(
                    and_(ChatSession.scope_type == "farm", ChatSession.farm_id == farm_id),
                    exists().where(
                        Plot.id == ChatSession.plot_id,
                        Plot.farmer_id == farmer_id,
                        Plot.farm_id == farm_id,
                        ChatSession.scope_type == "plot",
                    ),
                    exists().where(
                        ChatMemoryConnection.chat_id == ChatSession.id,
                        ChatMemoryConnection.farmer_id == farmer_id,
                        ChatMemoryConnection.farm_id == farm_id,
                    ),
                    exists().where(
                        ChatMemoryConnection.chat_id == ChatSession.id,
                        ChatMemoryConnection.farmer_id == farmer_id,
                        ChatMemoryConnection.plot_id == Plot.id,
                        Plot.farmer_id == farmer_id,
                        Plot.farm_id == farm_id,
                    ),
                    exists().where(
                        DiagnosisCase.id == ChatSession.diagnosis_case_id,
                        DiagnosisCase.farmer_id == farmer_id,
                        DiagnosisCase.farm_id == farm_id,
                    ),
                )
            )
        if plot_id is not None:
            statement = statement.where(
                or_(
                    and_(ChatSession.scope_type == "plot", ChatSession.plot_id == plot_id),
                    exists().where(
                        ChatMemoryConnection.chat_id == ChatSession.id,
                        ChatMemoryConnection.farmer_id == farmer_id,
                        ChatMemoryConnection.plot_id == plot_id,
                    ),
                    exists().where(
                        DiagnosisCase.id == ChatSession.diagnosis_case_id,
                        DiagnosisCase.farmer_id == farmer_id,
                        DiagnosisCase.plot_id == plot_id,
                    ),
                )
            )
        result = await self.session.scalars(
            statement.order_by(ChatSession.updated_at.desc()).limit(limit).offset(offset)
        )
        return list(result)

    async def messages_page(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        *,
        limit: int,
        before_sequence: int | None,
    ) -> list[ChatMessage]:
        statement = select(ChatMessage).where(
            ChatMessage.farmer_id == farmer_id,
            ChatMessage.chat_id == chat_id,
        )
        if before_sequence is not None:
            statement = statement.where(ChatMessage.sequence < before_sequence)
        result = await self.session.scalars(
            statement.order_by(ChatMessage.sequence.desc()).limit(limit)
        )
        return list(reversed(list(result)))

    async def message(self, farmer_id: UUID, chat_id: UUID, message_id: UUID) -> ChatMessage | None:
        result = await self.session.execute(
            select(ChatMessage).where(
                ChatMessage.id == message_id,
                ChatMessage.farmer_id == farmer_id,
                ChatMessage.chat_id == chat_id,
            )
        )
        return result.scalar_one_or_none()

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

    async def all_messages(self, farmer_id: UUID, chat_id: UUID) -> list[ChatMessage]:
        result = await self.session.scalars(
            select(ChatMessage)
            .where(
                ChatMessage.farmer_id == farmer_id,
                ChatMessage.chat_id == chat_id,
            )
            .order_by(ChatMessage.sequence)
        )
        return list(result)

    async def next_sequence(self, farmer_id: UUID, chat_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.max(ChatMessage.sequence)).where(
                ChatMessage.farmer_id == farmer_id,
                ChatMessage.chat_id == chat_id,
            )
        )
        return int(value or 0) + 1

    async def get_send_operation(
        self, farmer_id: UUID, chat_id: UUID, idempotency_key: str
    ) -> ChatSendOperation | None:
        result = await self.session.execute(
            select(ChatSendOperation).where(
                ChatSendOperation.farmer_id == farmer_id,
                ChatSendOperation.chat_id == chat_id,
                ChatSendOperation.idempotency_key == idempotency_key,
            )
        )
        return result.scalar_one_or_none()

    async def get_turn(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        turn_id: UUID,
        *,
        for_update: bool = False,
    ) -> ChatTurn | None:
        statement = select(ChatTurn).where(
            ChatTurn.id == turn_id,
            ChatTurn.farmer_id == farmer_id,
            ChatTurn.chat_id == chat_id,
        )
        if for_update:
            statement = statement.with_for_update()
        return (await self.session.execute(statement)).scalar_one_or_none()

    async def get_turn_by_key(
        self, farmer_id: UUID, chat_id: UUID, idempotency_key: str
    ) -> ChatTurn | None:
        return (
            await self.session.execute(
                select(ChatTurn).where(
                    ChatTurn.farmer_id == farmer_id,
                    ChatTurn.chat_id == chat_id,
                    ChatTurn.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one_or_none()

    async def next_turn_sequence(self, farmer_id: UUID, chat_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.max(ChatTurn.sequence)).where(
                ChatTurn.farmer_id == farmer_id,
                ChatTurn.chat_id == chat_id,
            )
        )
        return int(value or 0) + 1

    async def pending_turn_count(self, farmer_id: UUID, chat_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.count(ChatTurn.id)).where(
                ChatTurn.farmer_id == farmer_id,
                ChatTurn.chat_id == chat_id,
                ChatTurn.status.in_(("queued", "processing")),
            )
        )
        return int(value or 0)

    async def get_claimed_turn(
        self, turn_id: UUID, lease_token: UUID, *, for_update: bool = False
    ) -> ChatTurn | None:
        statement = select(ChatTurn).where(
            ChatTurn.id == turn_id,
            ChatTurn.status == "processing",
            ChatTurn.lease_token == lease_token,
        )
        if for_update:
            statement = statement.with_for_update()
        return (await self.session.execute(statement)).scalar_one_or_none()

    async def list_turns(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        *,
        active_only: bool,
        limit: int,
    ) -> list[ChatTurn]:
        statement = select(ChatTurn).where(
            ChatTurn.farmer_id == farmer_id,
            ChatTurn.chat_id == chat_id,
        )
        if active_only:
            statement = statement.where(ChatTurn.status.in_(("queued", "processing")))
        values = await self.session.scalars(statement.order_by(ChatTurn.sequence).limit(limit))
        return list(values)

    async def queue_position(self, turn: ChatTurn) -> int | None:
        if turn.status not in ("queued", "processing"):
            return None
        earlier = await self.session.scalar(
            select(func.count(ChatTurn.id)).where(
                ChatTurn.chat_id == turn.chat_id,
                ChatTurn.farmer_id == turn.farmer_id,
                ChatTurn.status.in_(("queued", "processing")),
                ChatTurn.sequence < turn.sequence,
            )
        )
        return int(earlier or 0) + 1

    async def requeue_expired_turns(self, now: datetime) -> None:
        await self.session.execute(
            update(ChatTurn)
            .where(
                ChatTurn.status == "processing",
                ChatTurn.lease_expires_at.is_not(None),
                ChatTurn.lease_expires_at <= now,
            )
            .values(
                status="queued",
                lease_expires_at=None,
                lease_token=None,
                next_attempt_at=now,
            )
        )

    async def claim_due_turns(self, now: datetime, *, limit: int) -> list[ChatTurn]:
        earlier = aliased(ChatTurn)
        statement = (
            select(ChatTurn)
            .where(
                ChatTurn.status == "queued",
                ChatTurn.next_attempt_at <= now,
                ~exists().where(
                    earlier.chat_id == ChatTurn.chat_id,
                    earlier.farmer_id == ChatTurn.farmer_id,
                    earlier.status.in_(("queued", "processing")),
                    earlier.sequence < ChatTurn.sequence,
                ),
            )
            .order_by(ChatTurn.created_at, ChatTurn.chat_id, ChatTurn.sequence)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        return list(await self.session.scalars(statement))

    def add(self, value: ChatSession | ChatMessage | ChatSendOperation | ChatTurn) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def flush(self) -> None:
        await self.session.flush()

    async def rollback(self) -> None:
        await self.session.rollback()

    async def refresh(
        self, value: ChatSession | ChatMessage | ChatSendOperation | ChatTurn
    ) -> None:
        await self.session.refresh(value)

    async def delete(self, value: ChatSession) -> None:
        await self.session.delete(value)
