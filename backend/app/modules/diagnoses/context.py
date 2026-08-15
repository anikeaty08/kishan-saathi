"""Cross-module contract for deleting context derived from a diagnosis chat."""

from typing import Protocol
from uuid import UUID


class DiagnosisContextCleaner(Protocol):
    async def delete_scan_context(self, farmer_id: UUID, case_id: UUID) -> None: ...
