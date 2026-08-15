"""Request logs must not contain secret path parameters."""

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from httpx import ASGITransport, AsyncClient
from structlog.testing import capture_logs

from app.core.logging import configure_logging, request_context_middleware


async def test_request_logging_uses_route_template_for_secret_tokens() -> None:
    configure_logging("INFO")
    app = FastAPI()
    app.middleware("http")(request_context_middleware)

    @app.get("/shared/{token}")
    async def shared(token: str) -> PlainTextResponse:
        del token
        return PlainTextResponse("ok")

    with capture_logs() as logs:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/shared/do-not-log-this-secret")

    assert response.status_code == 200
    request_logs = [entry for entry in logs if entry.get("event", "").startswith("request.")]
    assert request_logs
    assert all(entry["path"] == "/shared/{token}" for entry in request_logs)
    assert "do-not-log-this-secret" not in str(request_logs)
