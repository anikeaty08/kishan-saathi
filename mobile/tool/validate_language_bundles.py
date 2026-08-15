"""Offline validation for KrishiSathi ARB language bundles.

This tool never calls a network service. It validates key coverage,
placeholders, ASCII-only numeric glyphs, and basic script presence.
"""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path


MOBILE_ROOT = Path(__file__).resolve().parents[1]
BUNDLE_DIR = MOBILE_ROOT / "lib" / "l10n"
LANGUAGE_CODES = (
    "en",
    "as",
    "bn",
    "brx",
    "doi",
    "gu",
    "hi",
    "kn",
    "ks",
    "kok",
    "mai",
    "ml",
    "mni",
    "mr",
    "ne",
    "or",
    "pa",
    "sa",
    "sat",
    "sd",
    "ta",
    "te",
    "ur",
)

SCRIPT_RANGES = {
    "as": ("\u0980", "\u09ff"),
    "bn": ("\u0980", "\u09ff"),
    "brx": ("\u0900", "\u097f"),
    "doi": ("\u0900", "\u097f"),
    "gu": ("\u0a80", "\u0aff"),
    "hi": ("\u0900", "\u097f"),
    "kn": ("\u0c80", "\u0cff"),
    "ks": ("\u0600", "\u06ff"),
    "kok": ("\u0900", "\u097f"),
    "mai": ("\u0900", "\u097f"),
    "ml": ("\u0d00", "\u0d7f"),
    "mni": ("\uabc0", "\uabff"),
    "mr": ("\u0900", "\u097f"),
    "ne": ("\u0900", "\u097f"),
    "or": ("\u0b00", "\u0b7f"),
    "pa": ("\u0a00", "\u0a7f"),
    "sa": ("\u0900", "\u097f"),
    "sat": ("\u1c50", "\u1c7f"),
    "sd": ("\u0600", "\u06ff"),
    "ta": ("\u0b80", "\u0bff"),
    "te": ("\u0c00", "\u0c7f"),
    "ur": ("\u0600", "\u06ff"),
}

# Product names intentionally remain unchanged in every language.
ALLOWED_ENGLISH_COPIES = {"appName", "saathi"}


def read_bundle(code: str) -> dict[str, str]:
    payload = json.loads((BUNDLE_DIR / f"app_{code}.arb").read_text(encoding="utf-8"))
    return {
        key: value
        for key, value in payload.items()
        if not key.startswith("@") and isinstance(value, str)
    }


def placeholders(value: str) -> set[str]:
    return set(re.findall(r"\{[A-Za-z][A-Za-z0-9_]*\}", value))


def main() -> None:
    english = read_bundle("en")
    failures: list[str] = []
    for code in LANGUAGE_CODES:
        values = read_bundle(code)
        missing = sorted(set(english) - set(values))
        extra = sorted(set(values) - set(english))
        if missing:
            failures.append(f"{code}: missing {missing}")
        if extra:
            failures.append(f"{code}: unexpected {extra}")
        for key in set(english) & set(values):
            value = values[key]
            if not value.strip():
                failures.append(f"{code}:{key}: empty")
            if placeholders(english[key]) != placeholders(value):
                failures.append(f"{code}:{key}: placeholder mismatch")
            for character in value:
                if character.isdigit() and character not in "0123456789":
                    failures.append(
                        f"{code}:{key}: non-ASCII digit {character!r} "
                        f"({unicodedata.name(character, 'unknown')})"
                    )
            if (
                code != "en"
                and key not in ALLOWED_ENGLISH_COPIES
                and value == english[key]
            ):
                failures.append(f"{code}:{key}: untranslated English copy")
        if code != "en":
            start, end = SCRIPT_RANGES[code]
            localized_lines = sum(
                any(start <= character <= end for character in value)
                for value in values.values()
            )
            if localized_lines < int(len(english) * 0.7):
                failures.append(
                    f"{code}: only {localized_lines}/{len(english)} values use "
                    "the expected native script"
                )
        print(f"{code}: {len(values)} keys")

    if failures:
        raise SystemExit("\n".join(failures))
    print(f"All {len(LANGUAGE_CODES)} bundles are structurally valid.")


if __name__ == "__main__":
    main()
