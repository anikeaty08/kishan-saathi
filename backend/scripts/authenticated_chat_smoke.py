"""Measure the authenticated direct-chat and owned-speech path without logging PII."""

import argparse
import asyncio
import json
import os
from contextlib import suppress
from dataclasses import asdict, dataclass
from time import perf_counter
from typing import Any
from uuid import uuid4

import httpx

MAX_FIRST_EVENT_MS = 2_000
MAX_FIRST_TOKEN_MS = 15_000
MAX_STREAM_COMPLETION_MS = 45_000
MAX_FIRST_AUDIO_MS = 15_000
MAX_TRANSCRIPTION_MS = 30_000


class SmokeFailure(RuntimeError):
    def __init__(self, check: str, detail: str) -> None:
        super().__init__(f"{check}: {detail}")
        self.check = check
        self.detail = detail


@dataclass(frozen=True, slots=True)
class StreamMetrics:
    case: str
    status: int
    headers_ms: float
    first_event_ms: float | None
    first_token_ms: float | None
    completed_ms: float | None
    token_events: int
    characters: int


def _elapsed_ms(started: float, observed: float | None) -> float | None:
    return round((observed - started) * 1000, 1) if observed is not None else None


def _error_code(response: httpx.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return "NON_JSON_ERROR"
    if not isinstance(body, dict):
        return "INVALID_ERROR_BODY"
    error = body.get("error")
    if not isinstance(error, dict):
        return "INVALID_ERROR_BODY"
    code = error.get("code")
    return code if isinstance(code, str) else "INVALID_ERROR_BODY"


def _require_latency(check: str, value: float | None, maximum_ms: int) -> None:
    if value is None:
        raise SmokeFailure(check, "TIMING_MISSING")
    if value > maximum_ms:
        raise SmokeFailure(check, f"LATENCY_{round(value)}MS_EXCEEDS_{maximum_ms}MS")


async def _stream_turn(
    client: httpx.AsyncClient,
    *,
    base_url: str,
    token: str,
    chat_id: str,
    case: str,
    content: str,
) -> tuple[StreamMetrics, dict[str, Any]]:
    started = perf_counter()
    first_event: float | None = None
    first_token: float | None = None
    completed: float | None = None
    token_events = 0
    characters = 0
    result: dict[str, Any] | None = None
    provider_error: str | None = None

    async with client.stream(
        "POST",
        f"{base_url}/api/v1/chats/{chat_id}/messages/stream",
        headers={
            "Authorization": f"Bearer {token}",
            "Idempotency-Key": f"smoke-{uuid4().hex}",
        },
        json={"content": content},
    ) as response:
        headers_at = perf_counter()
        if response.status_code != 200:
            body = await response.aread()
            failure_response = httpx.Response(
                response.status_code,
                content=body,
                headers=response.headers,
            )
            raise SmokeFailure("stream_status", _error_code(failure_response))

        async for line in response.aiter_lines():
            if not line:
                continue
            observed = perf_counter()
            first_event = first_event or observed
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SmokeFailure("stream_protocol", "INVALID_NDJSON") from exc
            if not isinstance(event, dict):
                raise SmokeFailure("stream_protocol", "INVALID_EVENT")
            event_name = event.get("event")
            if event_name == "token":
                delta = event.get("data")
                if not isinstance(delta, str):
                    raise SmokeFailure("stream_protocol", "INVALID_TOKEN")
                first_token = first_token or observed
                token_events += 1
                characters += len(delta)
            elif event_name == "done":
                candidate = event.get("result")
                if not isinstance(candidate, dict):
                    raise SmokeFailure("stream_protocol", "INVALID_RESULT")
                result = candidate
                completed = observed
            elif event_name == "error":
                code = event.get("error_code")
                provider_error = code if isinstance(code, str) else "UNKNOWN_STREAM_ERROR"

    metrics = StreamMetrics(
        case=case,
        status=response.status_code,
        headers_ms=_elapsed_ms(started, headers_at) or 0,
        first_event_ms=_elapsed_ms(started, first_event),
        first_token_ms=_elapsed_ms(started, first_token),
        completed_ms=_elapsed_ms(started, completed),
        token_events=token_events,
        characters=characters,
    )
    if provider_error is not None:
        raise SmokeFailure(f"{case}_stream_provider", provider_error)
    if result is None or completed is None:
        raise SmokeFailure("stream_protocol", "DONE_EVENT_MISSING")
    if first_token is None or token_events == 0:
        raise SmokeFailure("direct_rendering", "TOKEN_EVENT_MISSING")
    _require_latency("first_event", metrics.first_event_ms, MAX_FIRST_EVENT_MS)
    _require_latency("first_token", metrics.first_token_ms, MAX_FIRST_TOKEN_MS)
    _require_latency("stream_completion", metrics.completed_ms, MAX_STREAM_COMPLETION_MS)
    assistant = result.get("assistant_message")
    structured = assistant.get("structured_content") if isinstance(assistant, dict) else None
    if not isinstance(structured, dict) or not structured.get("short_answer"):
        raise SmokeFailure("structured_stream", "ASSISTANT_RESULT_MISSING")
    return metrics, result


async def _run(base_url: str) -> None:
    email = os.environ.get("SMOKE_EMAIL", "").strip()
    password = os.environ.get("SMOKE_PASSWORD", "")
    if not email or not password:
        raise SmokeFailure("configuration", "SMOKE_EMAIL_AND_PASSWORD_REQUIRED")

    timeout = httpx.Timeout(120, connect=10)
    chat_id: str | None = None
    token: str | None = None
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            started = perf_counter()
            login = await client.post(
                f"{base_url}/api/v1/auth/sign-in",
                json={"email": email, "password": password},
            )
            login_ms = round((perf_counter() - started) * 1000, 1)
            if login.status_code != 200:
                raise SmokeFailure("authentication", _error_code(login))
            login_body = login.json()
            token_value = login_body.get("access_token") if isinstance(login_body, dict) else None
            if not isinstance(token_value, str) or not token_value:
                raise SmokeFailure("authentication", "ACCESS_TOKEN_MISSING")
            token = token_value
            auth = {"Authorization": f"Bearer {token}"}

            started = perf_counter()
            created = await client.post(f"{base_url}/api/v1/chats", headers=auth, json={})
            create_ms = round((perf_counter() - started) * 1000, 1)
            if created.status_code != 201:
                raise SmokeFailure("create_chat", _error_code(created))
            created_body = created.json()
            chat_value = created_body.get("id") if isinstance(created_body, dict) else None
            if not isinstance(chat_value, str):
                raise SmokeFailure("create_chat", "CHAT_ID_MISSING")
            chat_id = chat_value

            measurements: list[StreamMetrics] = []
            last_result: dict[str, Any] | None = None
            for case, content in (
                ("greeting", "Hey sup"),
                ("crop_guidance", "How can I check whether my tomato soil needs water today?"),
            ):
                metrics, last_result = await _stream_turn(
                    client,
                    base_url=base_url,
                    token=token,
                    chat_id=chat_id,
                    case=case,
                    content=content,
                )
                measurements.append(metrics)

            messages = await client.get(
                f"{base_url}/api/v1/chats/{chat_id}/messages",
                headers=auth,
            )
            if messages.status_code != 200:
                raise SmokeFailure("message_persistence", _error_code(messages))
            message_body = messages.json()
            items = message_body.get("items") if isinstance(message_body, dict) else None
            if not isinstance(items, list):
                raise SmokeFailure("message_persistence", "ITEMS_MISSING")
            roles = [item.get("role") for item in items if isinstance(item, dict)]
            sequences = [item.get("sequence") for item in items if isinstance(item, dict)]
            if roles != ["user", "assistant", "user", "assistant"]:
                raise SmokeFailure("message_persistence", "ROLE_ORDER_INVALID")
            if sequences != [1, 2, 3, 4]:
                raise SmokeFailure("message_persistence", "SEQUENCE_ORDER_INVALID")

            old_route = await client.get(
                f"{base_url}/api/v1/chats/{chat_id}/turns/{uuid4()}",
                headers=auth,
            )
            if old_route.status_code != 404:
                raise SmokeFailure("queue_removal", f"OLD_ROUTE_STATUS_{old_route.status_code}")

            if last_result is None:
                raise SmokeFailure("speech", "ASSISTANT_RESULT_MISSING")
            assistant = last_result.get("assistant_message")
            assistant_id = assistant.get("id") if isinstance(assistant, dict) else None
            if not isinstance(assistant_id, str):
                raise SmokeFailure("speech", "ASSISTANT_MESSAGE_ID_MISSING")

            speech_started = perf_counter()
            first_audio: float | None = None
            audio_parts: list[bytes] = []
            async with client.stream(
                "GET",
                f"{base_url}/api/v1/voice/chats/{chat_id}/messages/{assistant_id}/speech",
                headers=auth,
            ) as speech:
                speech_headers = perf_counter()
                if speech.status_code != 200:
                    body = await speech.aread()
                    failure_response = httpx.Response(speech.status_code, content=body)
                    raise SmokeFailure("speech", _error_code(failure_response))
                if not speech.headers.get("content-type", "").startswith("audio/"):
                    raise SmokeFailure("speech", "AUDIO_CONTENT_TYPE_MISSING")
                async for chunk in speech.aiter_bytes():
                    if chunk and first_audio is None:
                        first_audio = perf_counter()
                    if chunk:
                        audio_parts.append(chunk)
            audio_content = b"".join(audio_parts)
            if first_audio is None or not audio_content:
                raise SmokeFailure("speech", "AUDIO_BODY_EMPTY")
            speech_first_audio_ms = _elapsed_ms(speech_started, first_audio)
            speech_total_ms = round((perf_counter() - speech_started) * 1000, 1)
            _require_latency("speech_first_audio", speech_first_audio_ms, MAX_FIRST_AUDIO_MS)

            transcription_started = perf_counter()
            transcription = await client.post(
                f"{base_url}/api/v1/voice/chats/{chat_id}/transcriptions",
                headers=auth,
                files={"audio": ("assistant.mp3", audio_content, "audio/mpeg")},
            )
            transcription_ms = round((perf_counter() - transcription_started) * 1000, 1)
            if transcription.status_code != 200:
                raise SmokeFailure("transcription", _error_code(transcription))
            transcription_body = transcription.json()
            transcript = (
                transcription_body.get("transcript")
                if isinstance(transcription_body, dict)
                else None
            )
            if not isinstance(transcript, str) or not transcript.strip():
                raise SmokeFailure("transcription", "TRANSCRIPT_MISSING")
            _require_latency("transcription", transcription_ms, MAX_TRANSCRIPTION_MS)

            print(
                json.dumps(
                    {
                        "authentication_ms": login_ms,
                        "create_chat_ms": create_ms,
                        "streams": [asdict(item) for item in measurements],
                        "persisted_messages": len(items),
                        "old_queue_route_status": old_route.status_code,
                        "speech_headers_ms": _elapsed_ms(speech_started, speech_headers),
                        "speech_first_audio_ms": speech_first_audio_ms,
                        "speech_total_ms": speech_total_ms,
                        "speech_bytes": len(audio_content),
                        "transcription_ms": transcription_ms,
                        "transcript_characters": len(transcript),
                        "passed": True,
                    }
                )
            )
        finally:
            if token is not None and chat_id is not None:
                with suppress(httpx.HTTPError):
                    await client.delete(
                        f"{base_url}/api/v1/chats/{chat_id}",
                        headers={"Authorization": f"Bearer {token}"},
                    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    try:
        asyncio.run(_run(args.base_url.rstrip("/")))
    except SmokeFailure as exc:
        print(json.dumps({"passed": False, "check": exc.check, "error_code": exc.detail}))
        raise SystemExit(2) from exc


if __name__ == "__main__":
    main()
