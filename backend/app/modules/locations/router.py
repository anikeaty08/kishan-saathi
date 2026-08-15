"""Authenticated Open-Meteo location-name search."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from app.core.dependencies import get_geocoding_provider
from app.core.errors import ApplicationError
from app.integrations.geocoding.provider import GeocodingProvider, GeocodingResult
from app.modules.users.dependencies import get_current_farmer_id
from app.modules.users.schemas import SupportedLanguage

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/search", response_model=list[GeocodingResult])
async def search_locations(
    query: Annotated[str, Query(min_length=2, max_length=100)],
    provider: Annotated[GeocodingProvider, Depends(get_geocoding_provider)],
    _farmer_id: Annotated[UUID, Depends(get_current_farmer_id)],
    language: Annotated[SupportedLanguage, Query()] = SupportedLanguage.ENGLISH,
    limit: Annotated[int, Query(ge=1, le=10)] = 5,
) -> list[GeocodingResult]:
    normalized_query = query.strip()
    if len(normalized_query) < 2:
        raise ApplicationError(code="GEOCODING_QUERY_INVALID", status_code=422)
    return list(await provider.search(query=normalized_query, language=language.value, limit=limit))
