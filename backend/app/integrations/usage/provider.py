"""Provider-neutral AI usage observations with no prompt or response content."""

from dataclasses import dataclass
from typing import Protocol
from uuid import UUID


@dataclass(frozen=True, slots=True)
class AIUsageObservation:
    farmer_id: UUID
    operation: str
    model: str
    provider_response_id: str | None
    request_count: int
    input_tokens: int
    cached_input_tokens: int
    cache_write_tokens: int
    output_tokens: int
    reasoning_tokens: int
    total_tokens: int
    latency_ms: int


class AIUsageSink(Protocol):
    async def record(self, observation: AIUsageObservation) -> None: ...


class NullAIUsageSink:
    async def record(self, observation: AIUsageObservation) -> None:
        del observation
