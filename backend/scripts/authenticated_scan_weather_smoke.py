"""Exercise authenticated multi-image diagnosis and cached weather without logging PII."""

import argparse
import asyncio
import json
import os
from contextlib import suppress
from datetime import datetime
from pathlib import Path
from time import perf_counter
from typing import Any
from uuid import uuid4

import httpx


class SmokeFailure(RuntimeError):
    def __init__(self, check: str, detail: str) -> None:
        super().__init__(f"{check}: {detail}")
        self.check = check
        self.detail = detail


def _same_instant(left: object, right: object) -> bool:
    if not isinstance(left, str) or not isinstance(right, str):
        return False
    try:
        return datetime.fromisoformat(left.replace("Z", "+00:00")) == datetime.fromisoformat(
            right.replace("Z", "+00:00")
        )
    except ValueError:
        return False


def _expect(response: httpx.Response, status: int, check: str) -> dict[str, Any]:
    if response.status_code != status:
        try:
            body = response.json()
            error = body.get("error", {}) if isinstance(body, dict) else {}
            code = error.get("code", f"HTTP_{response.status_code}")
        except ValueError:
            code = f"HTTP_{response.status_code}"
        raise SmokeFailure(check, str(code))
    if status == 204:
        return {}
    body = response.json()
    if not isinstance(body, dict):
        raise SmokeFailure(check, "INVALID_JSON_OBJECT")
    return body


async def _run(base_url: str, images: tuple[Path, Path]) -> None:
    email = os.environ.get("SMOKE_EMAIL", "").strip()
    password = os.environ.get("SMOKE_PASSWORD", "")
    if not email or not password:
        raise SmokeFailure("configuration", "SMOKE_EMAIL_AND_PASSWORD_REQUIRED")
    for image in images:
        if not image.is_file():
            raise SmokeFailure("configuration", "SCAN_IMAGE_MISSING")

    token: str | None = None
    case_id: str | None = None
    plot_id: str | None = None
    crop_id: str | None = None
    timeout = httpx.Timeout(120, connect=15)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            signed_in = _expect(
                await client.post(
                    f"{base_url}/api/v1/auth/sign-in",
                    json={"email": email, "password": password},
                ),
                200,
                "authentication",
            )
            token_value = signed_in.get("access_token")
            if not isinstance(token_value, str):
                raise SmokeFailure("authentication", "ACCESS_TOKEN_MISSING")
            token = token_value
            auth = {"Authorization": f"Bearer {token}"}

            phone_started = perf_counter()
            first_phone = _expect(
                await client.post(
                    f"{base_url}/api/v1/weather/current",
                    headers=auth,
                    json={"latitude": 12.9716, "longitude": 77.5946},
                ),
                200,
                "phone_weather_first",
            )
            second_phone = _expect(
                await client.post(
                    f"{base_url}/api/v1/weather/current",
                    headers=auth,
                    json={"latitude": 12.9716, "longitude": 77.5946},
                ),
                200,
                "phone_weather_cached",
            )
            phone_ms = round((perf_counter() - phone_started) * 1000, 1)
            if not _same_instant(
                first_phone.get("fetched_at"), second_phone.get("fetched_at")
            ):
                raise SmokeFailure("phone_weather_cached", "CACHE_TIMESTAMP_CHANGED")
            if first_phone.get("is_stale") is not False:
                raise SmokeFailure("phone_weather_first", "UNEXPECTED_STALE_RESPONSE")

            plot = _expect(
                await client.post(
                    f"{base_url}/api/v1/plots",
                    headers=auth,
                    json={
                        "name": f"Release smoke {uuid4().hex[:8]}",
                        "latitude": 12.9716,
                        "longitude": 77.5946,
                        "location_label": "Release smoke location",
                        "crops": [{"name": "Tomato", "stage": "fruiting"}],
                    },
                ),
                201,
                "plot_create",
            )
            plot_id_value = plot.get("id")
            crops = plot.get("crops")
            if not isinstance(plot_id_value, str) or not isinstance(crops, list) or len(crops) != 1:
                raise SmokeFailure("plot_create", "PLOT_RESPONSE_INVALID")
            plot_id = plot_id_value
            crop_id_value = crops[0].get("id") if isinstance(crops[0], dict) else None
            if not isinstance(crop_id_value, str):
                raise SmokeFailure("plot_create", "CROP_ID_MISSING")
            crop_id = crop_id_value

            plot_weather_started = perf_counter()
            current_first = _expect(
                await client.get(
                    f"{base_url}/api/v1/weather/plots/{plot_id}/current", headers=auth
                ),
                200,
                "plot_current_first",
            )
            current_cached = _expect(
                await client.get(
                    f"{base_url}/api/v1/weather/plots/{plot_id}/current", headers=auth
                ),
                200,
                "plot_current_cached",
            )
            forecast_first = _expect(
                await client.get(
                    f"{base_url}/api/v1/weather/plots/{plot_id}/forecast", headers=auth
                ),
                200,
                "plot_forecast_first",
            )
            forecast_cached = _expect(
                await client.get(
                    f"{base_url}/api/v1/weather/plots/{plot_id}/forecast", headers=auth
                ),
                200,
                "plot_forecast_cached",
            )
            plot_weather_ms = round((perf_counter() - plot_weather_started) * 1000, 1)
            if not _same_instant(
                current_first.get("fetched_at"), current_cached.get("fetched_at")
            ):
                raise SmokeFailure("plot_current_cached", "CACHE_TIMESTAMP_CHANGED")
            if not _same_instant(
                forecast_first.get("fetched_at"), forecast_cached.get("fetched_at")
            ):
                raise SmokeFailure("plot_forecast_cached", "CACHE_TIMESTAMP_CHANGED")

            scan_started = perf_counter()
            files = [("images", (image.name, image.read_bytes(), "image/jpeg")) for image in images]
            diagnosis = _expect(
                await client.post(
                    f"{base_url}/api/v1/diagnoses",
                    headers=auth,
                    files=files,
                ),
                201,
                "diagnosis_create",
            )
            scan_ms = round((perf_counter() - scan_started) * 1000, 1)
            case_id_value = diagnosis.get("id")
            if not isinstance(case_id_value, str):
                raise SmokeFailure("diagnosis_create", "CASE_ID_MISSING")
            case_id = case_id_value
            if diagnosis.get("plant_name") is not None:
                raise SmokeFailure("diagnosis_optional_crop", "PLANT_NAME_NOT_OPTIONAL")
            if diagnosis.get("image_count") != 2:
                raise SmokeFailure("diagnosis_multi_image", "IMAGE_COUNT_MISMATCH")
            image_records = diagnosis.get("images")
            if not isinstance(image_records, list) or len(image_records) != 2:
                raise SmokeFailure("diagnosis_multi_image", "IMAGE_RECORDS_MISSING")
            if any(
                not isinstance(item, dict)
                or not isinstance(item.get("width"), int)
                or not isinstance(item.get("height"), int)
                or item["width"] < 256
                or item["height"] < 256
                for item in image_records
            ):
                raise SmokeFailure("diagnosis_image_quality", "SANITIZED_DIMENSIONS_INVALID")
            assessment = diagnosis.get("active_assessment")
            if not isinstance(assessment, dict):
                raise SmokeFailure("diagnosis_assessment", "ASSESSMENT_MISSING")
            if assessment.get("confidence_label") not in {"low", "medium", "high"}:
                raise SmokeFailure("diagnosis_assessment", "CONFIDENCE_LABEL_INVALID")
            alternatives = assessment.get("alternatives")
            if not isinstance(alternatives, list):
                raise SmokeFailure("diagnosis_assessment", "ALTERNATIVES_MISSING")

            image_id = image_records[0].get("id")
            if not isinstance(image_id, str):
                raise SmokeFailure("diagnosis_image_read", "IMAGE_ID_MISSING")
            stored_image = await client.get(
                f"{base_url}/api/v1/diagnoses/{case_id}/images/{image_id}", headers=auth
            )
            if stored_image.status_code != 200 or not stored_image.content:
                raise SmokeFailure("diagnosis_image_read", f"HTTP_{stored_image.status_code}")
            if stored_image.headers.get("cache-control") != "private, no-store":
                raise SmokeFailure("diagnosis_image_read", "PRIVATE_CACHE_HEADER_MISSING")

            history = await client.get(f"{base_url}/api/v1/diagnoses", headers=auth)
            if history.status_code != 200 or not any(
                isinstance(item, dict) and item.get("id") == case_id for item in history.json()
            ):
                raise SmokeFailure("diagnosis_history", "CASE_NOT_LISTED")
            hidden = await client.get(
                f"{base_url}/api/v1/weather/plots/{uuid4()}/forecast", headers=auth
            )
            if hidden.status_code != 404:
                raise SmokeFailure("ownership_boundary", f"HTTP_{hidden.status_code}")

            print(
                json.dumps(
                    {
                        "phone_weather_ms": phone_ms,
                        "phone_weather_cache_reused": True,
                        "plot_weather_ms": plot_weather_ms,
                        "plot_current_cache_reused": True,
                        "plot_forecast_cache_reused": True,
                        "diagnosis_ms": scan_ms,
                        "diagnosis_images": len(image_records),
                        "diagnosis_confidence_label": assessment.get("confidence_label"),
                        "diagnosis_alternatives": len(alternatives),
                        "stored_image_bytes": len(stored_image.content),
                        "ownership_probe_status": hidden.status_code,
                        "passed": True,
                    }
                )
            )
        finally:
            if token is not None:
                auth = {"Authorization": f"Bearer {token}"}
                if case_id is not None:
                    with suppress(httpx.HTTPError):
                        await client.delete(f"{base_url}/api/v1/diagnoses/{case_id}", headers=auth)
                if crop_id is not None:
                    with suppress(httpx.HTTPError):
                        await client.delete(
                            f"{base_url}/api/v1/crops/{crop_id}",
                            headers=auth,
                            params={"confirm_history_loss": "true"},
                        )
                if plot_id is not None:
                    with suppress(httpx.HTTPError):
                        await client.delete(f"{base_url}/api/v1/plots/{plot_id}", headers=auth)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("image", nargs=2, type=Path)
    args = parser.parse_args()
    try:
        asyncio.run(_run(args.base_url.rstrip("/"), tuple(args.image)))
    except SmokeFailure as exc:
        print(json.dumps({"passed": False, "check": exc.check, "error_code": exc.detail}))
        raise SystemExit(2) from exc


if __name__ == "__main__":
    main()
