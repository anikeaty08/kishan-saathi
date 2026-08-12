"""Typed leaf-diagnosis inference provider contract."""

from dataclasses import dataclass
from typing import Protocol

from app.core.errors import ApplicationError


@dataclass(frozen=True, slots=True)
class Prediction:
    """One ranked crop/disease candidate."""

    crop_name: str
    disease_name: str
    confidence: float


@dataclass(frozen=True, slots=True)
class ImageInference:
    """Quality result and ranked predictions for one sanitized image."""

    predictions: tuple[Prediction, ...]
    quality_score: float
    quality_flags: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class CaseInference:
    """Combined case assessment plus preserved per-image evidence."""

    combined_predictions: tuple[Prediction, ...]
    images: tuple[ImageInference, ...]
    model_name: str
    model_version: str


class LeafInferenceProvider(Protocol):
    """Model-serving boundary for one or many leaf images."""

    async def diagnose(
        self,
        *,
        images: tuple[bytes, ...],
        plant_name: str | None,
    ) -> CaseInference: ...

    async def close(self) -> None: ...


class UnavailableLeafInferenceProvider:
    """Fail honestly until an evaluated model checkpoint is configured."""

    async def diagnose(
        self,
        *,
        images: tuple[bytes, ...],
        plant_name: str | None,
    ) -> CaseInference:
        del images, plant_name
        raise ApplicationError(code="LEAF_MODEL_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
