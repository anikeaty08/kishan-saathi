"""Structured logging and request-correlation configuration."""

import logging
import sys
from collections.abc import Awaitable, Callable
from uuid import uuid4

import structlog
from fastapi import Request, Response
from starlette.routing import Match

REQUEST_ID_HEADER = "X-Request-ID"
MAX_REQUEST_ID_LENGTH = 128


def configure_logging(log_level: str) -> None:
    """Configure standard-library and structlog output as JSON."""

    level = getattr(logging, log_level.upper(), logging.INFO)
    logging.basicConfig(stream=sys.stdout, level=level, format="%(message)s", force=True)
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )


def _request_id(request: Request) -> str:
    supplied = request.headers.get(REQUEST_ID_HEADER, "").strip()
    if supplied and len(supplied) <= MAX_REQUEST_ID_LENGTH and supplied.isprintable():
        return supplied
    return str(uuid4())


async def request_context_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Bind a request ID, emit lifecycle logs, and return the ID to callers."""

    request_id = _request_id(request)
    request.state.request_id = request_id
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(request_id=request_id)
    logger = structlog.get_logger("http")
    path = _route_template(request)
    logger.info("request.started", method=request.method, path=path)

    try:
        response = await call_next(request)
    except Exception:
        logger.exception("request.failed", method=request.method, path=path)
        raise
    else:
        response.headers[REQUEST_ID_HEADER] = request_id
        logger.info(
            "request.completed",
            method=request.method,
            path=path,
            status_code=response.status_code,
        )
        return response
    finally:
        structlog.contextvars.clear_contextvars()


def _route_template(request: Request) -> str:
    """Log route templates so path secrets such as report tokens never enter logs."""

    for route in request.app.router.routes:
        match, _ = route.matches(request.scope)
        if match is Match.FULL:
            return str(getattr(route, "path", "unmatched"))
    return "unmatched"
