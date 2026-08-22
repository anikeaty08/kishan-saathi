"""Owner-scoped chat persistence."""

from uuid import UUID

from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.chats.models import ChatMessage, ChatSendOperation, ChatSession
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

    async def effective_scope_ids(
        self,
        farmer_id: UUID,
        chats: list[ChatSession],
    ) -> dict[UUID, tuple[UUID | None, UUID | None]]:
        """Resolve the current farm/plot context for chat transport responses."""

        if not chats:
            return {}
        chat_ids = [chat.id for chat in chats]
        connections = list(
            await self.session.scalars(
                select(ChatMemoryConnection).where(
                    ChatMemoryConnection.farmer_id == farmer_id,
                    ChatMemoryConnection.chat_id.in_(chat_ids),
                )
            )
        )
        connection_by_chat = {connection.chat_id: connection for connection in connections}
        case_ids = [chat.diagnosis_case_id for chat in chats if chat.diagnosis_case_id is not None]
        cases = (
            list(
                await self.session.scalars(
                    select(DiagnosisCase).where(
                        DiagnosisCase.farmer_id == farmer_id,
                        DiagnosisCase.id.in_(case_ids),
                    )
                )
            )
            if case_ids
            else []
        )
        case_by_id = {case.id: case for case in cases}

        resolved: dict[UUID, tuple[UUID | None, UUID | None]] = {}
        for chat in chats:
            case = (
                case_by_id.get(chat.diagnosis_case_id)
                if chat.diagnosis_case_id is not None
                else None
            )
            connection = connection_by_chat.get(chat.id)
            if case is not None:
                resolved[chat.id] = (case.farm_id, case.plot_id)
            elif connection is not None:
                resolved[chat.id] = (connection.farm_id, connection.plot_id)
            else:
                resolved[chat.id] = (chat.farm_id, chat.plot_id)
        return resolved

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

    def add(self, value: ChatSession | ChatMessage | ChatSendOperation) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def flush(self) -> None:
        await self.session.flush()

    async def rollback(self) -> None:
        await self.session.rollback()

    async def refresh(self, value: ChatSession | ChatMessage | ChatSendOperation) -> None:
        await self.session.refresh(value)

    async def delete(self, value: ChatSession) -> None:
        await self.session.delete(value)
