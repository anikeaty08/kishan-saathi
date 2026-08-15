"""Application error contracts and HTTP error mapping."""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import REQUEST_ID_HEADER


class ErrorBody(BaseModel):
    """Stable client-visible error details."""

    code: str
    request_id: str
    details: list[dict[str, Any]] = Field(default_factory=list)


class ErrorResponse(BaseModel):
    """Top-level error envelope shared by every endpoint."""

    error: ErrorBody


class ApplicationError(Exception):
    """Expected application failure safe to expose to API clients."""

    def __init__(
        self,
        *,
        code: str,
        status_code: int,
        details: list[dict[str, Any]] | None = None,
    ) -> None:
        super().__init__(code)
        self.code = code
        self.status_code = status_code
        self.details = details or []


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "unavailable")


def _response(
    request: Request,
    *,
    status_code: int,
    code: str,
    details: list[dict[str, Any]] | None = None,
) -> JSONResponse:
    body = ErrorResponse(
        error=ErrorBody(
            code=code,
            request_id=_request_id(request),
            details=details or [],
        )
    )
    response = JSONResponse(status_code=status_code, content=body.model_dump(mode="json"))
    response.headers[REQUEST_ID_HEADER] = body.error.request_id
    return response


def register_error_handlers(app: FastAPI) -> None:
    """Register predictable mappings from failures to public API errors."""

    @app.exception_handler(ApplicationError)
    async def application_error_handler(
        request: Request,
        exc: ApplicationError,
    ) -> JSONResponse:
        return _response(
            request,
            status_code=exc.status_code,
            code=exc.code,
            details=exc.details,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        return _response(
            request,
            status_code=422,
            code="VALIDATION_ERROR",
            details=[
                {
                    "field": ".".join(str(part) for part in error["loc"]),
                    "code": str(error["type"]).upper(),
                }
                for error in exc.errors()
            ],
        )

    @app.exception_handler(StarletteHTTPException)
    async def http_error_handler(
        request: Request,
        exc: StarletteHTTPException,
    ) -> JSONResponse:
        code_by_status = {
            404: "RESOURCE_NOT_FOUND",
            405: "METHOD_NOT_ALLOWED",
        }
        return _response(
            request,
            status_code=exc.status_code,
            code=code_by_status.get(exc.status_code, "HTTP_ERROR"),
        )

    @app.exception_handler(Exception)
    async def unexpected_error_handler(request: Request, _exc: Exception) -> JSONResponse:
        return _response(
            request,
            status_code=500,
            code="INTERNAL_ERROR",
        )
