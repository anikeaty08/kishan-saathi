"""Open-Meteo geocoding adapter contract."""

import logging

import httpx
import pytest

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.core.logging import configure_logging
from app.integrations.geocoding.open_meteo import OpenMeteoGeocodingProvider


@pytest.mark.asyncio
async def test_open_meteo_geocoding_maps_location_results() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["name"] == "Pune"
        assert request.url.params["language"] == "mr"
        return httpx.Response(
            200,
            json={
                "results": [
                    {
                        "name": "Pune",
                        "latitude": 18.52,
                        "longitude": 73.85,
                        "country": "India",
                        "admin1": "Maharashtra",
                        "timezone": "Asia/Kolkata",
                    }
                ]
            },
        )

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://geocoding.test"
    )
    provider = OpenMeteoGeocodingProvider(Settings(_env_file=None), client=client)
    try:
        results = await provider.search(query="Pune", language="mr", limit=5)
    finally:
        await client.aclose()

    assert results[0].name == "Pune"
    assert results[0].admin1 == "Maharashtra"
    assert results[0].latitude == 18.52


def test_http_client_info_urls_are_suppressed() -> None:
    configure_logging("INFO")

    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING


@pytest.mark.asyncio
@pytest.mark.parametrize("payload", [None, [], {"results": [{"name": "broken"}]}])
async def test_open_meteo_rejects_invalid_response_shapes(payload: object) -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=payload)

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://geocoding.test"
    )
    provider = OpenMeteoGeocodingProvider(Settings(_env_file=None), client=client)
    try:
        with pytest.raises(ApplicationError) as raised:
            await provider.search(query="Pune", language="en", limit=5)
    finally:
        await client.aclose()

    assert raised.value.code == "GEOCODING_INVALID_RESPONSE"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    [httpx.ReadTimeout("timeout"), httpx.RemoteProtocolError("bad protocol")],
)
async def test_open_meteo_normalizes_transport_failures(failure: Exception) -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        raise failure

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://geocoding.test"
    )
    provider = OpenMeteoGeocodingProvider(Settings(_env_file=None), client=client)
    try:
        with pytest.raises(ApplicationError) as raised:
            await provider.search(query="Pune", language="en", limit=5)
    finally:
        await client.aclose()

    assert raised.value.code == "GEOCODING_UNAVAILABLE"


@pytest.mark.asyncio
async def test_open_meteo_normalizes_non_success_status() -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"reason": "rate limited"})

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://geocoding.test"
    )
    provider = OpenMeteoGeocodingProvider(Settings(_env_file=None), client=client)
    try:
        with pytest.raises(ApplicationError) as raised:
            await provider.search(query="Pune", language="en", limit=5)
    finally:
        await client.aclose()

    assert raised.value.code == "GEOCODING_PROVIDER_ERROR"
