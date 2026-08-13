"""Narrow shared-memory write boundary used by chat orchestration."""

from typing import Protocol
from uuid import UUID

from app.modules.chats.models import ChatMessage
from app.modules.memories.models import MemoryCaptureJob


class ScopedMemoryWriter(Protocol):
    """Persist filtered farmer evidence for one already-authorized scope."""

    def schedule_scoped_message(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        message: ChatMessage,
        *,
        farm_id: UUID | None,
        plot_id: UUID | None,
    ) -> MemoryCaptureJob: ...
