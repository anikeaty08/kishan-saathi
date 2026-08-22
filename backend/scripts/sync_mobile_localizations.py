"""Validate or build missing offline Flutter language-pack entries."""

import argparse
import asyncio
import json
import re
from pathlib import Path
from typing import Any

from openai import AsyncOpenAI, OpenAIError
from pydantic import BaseModel, ConfigDict

LANGUAGES = {
    "as": ("Assamese", "Bengali-Assamese script"),
    "bn": ("Bengali", "Bengali script"),
    "brx": ("Bodo", "Devanagari script"),
    "doi": ("Dogri", "Devanagari script"),
    "gu": ("Gujarati", "Gujarati script"),
    "hi": ("Hindi", "Devanagari script"),
    "kn": ("Kannada", "Kannada script"),
    "kok": ("Konkani", "Devanagari script"),
    "ks": ("Kashmiri", "Perso-Arabic script"),
    "mai": ("Maithili", "Devanagari script"),
    "ml": ("Malayalam", "Malayalam script"),
    "mni": ("Manipuri", "Meitei Mayek script"),
    "mr": ("Marathi", "Devanagari script"),
    "ne": ("Nepali", "Devanagari script"),
    "or": ("Odia", "Odia script"),
    "pa": ("Punjabi", "Gurmukhi script"),
    "sa": ("Sanskrit", "Devanagari script"),
    "sat": ("Santali", "Ol Chiki script"),
    "sd": ("Sindhi", "Perso-Arabic script"),
    "ta": ("Tamil", "Tamil script"),
    "te": ("Telugu", "Telugu script"),
    "ur": ("Urdu", "Perso-Arabic script"),
}
PLACEHOLDER = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)\}")
SCRIPT_RANGES = {
    "as": ((0x0980, 0x09FF),),
    "bn": ((0x0980, 0x09FF),),
    "brx": ((0x0900, 0x097F),),
    "doi": ((0x0900, 0x097F),),
    "gu": ((0x0A80, 0x0AFF),),
    "hi": ((0x0900, 0x097F),),
    "kn": ((0x0C80, 0x0CFF),),
    "kok": ((0x0900, 0x097F),),
    "ks": ((0x0600, 0x06FF),),
    "mai": ((0x0900, 0x097F),),
    "ml": ((0x0D00, 0x0D7F),),
    "mni": ((0xABC0, 0xABFF),),
    "mr": ((0x0900, 0x097F),),
    "ne": ((0x0900, 0x097F),),
    "or": ((0x0B00, 0x0B7F),),
    "pa": ((0x0A00, 0x0A7F),),
    "sa": ((0x0900, 0x097F),),
    "sat": ((0x1C50, 0x1C7F),),
    "sd": ((0x0600, 0x06FF),),
    "ta": ((0x0B80, 0x0BFF),),
    "te": ((0x0C00, 0x0C7F),),
    "ur": ((0x0600, 0x06FF),),
}
SCRIPT_EXEMPT_KEYS = {
    "appName",
    "saathi",
    "supportContact",
    "versionValue",
    "applicationId",
}
PRIMARY_TRANSLATION_LOCALES = {"doi", "kok", "ks", "mni", "sat"}


class TranslationItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str
    value: str


class TranslationBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    translations: list[TranslationItem]


def _catalog(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name}: catalog must be a JSON object")
    return value


def _write_catalog(path: Path, catalog: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _visible_keys(catalog: dict[str, Any]) -> list[str]:
    return [
        key for key, value in catalog.items() if not key.startswith("@") and isinstance(value, str)
    ]


def _uses_expected_script(value: str, *, key: str, locale: str) -> bool:
    if key in SCRIPT_EXEMPT_KEYS or not any(character.isalpha() for character in value):
        return True
    return any(
        start <= ord(character) <= end
        for character in value
        for start, end in SCRIPT_RANGES[locale]
    )


def _validate_translation(source: str, translated: str, *, key: str, locale: str) -> None:
    if not translated.strip():
        raise ValueError(f"{locale}:{key}: empty translation")
    if PLACEHOLDER.findall(source) != PLACEHOLDER.findall(translated):
        raise ValueError(f"{locale}:{key}: placeholders changed")
    source_digits = [
        character for character in source if character.isascii() and character.isdigit()
    ]
    translated_digits = [
        character for character in translated if character.isascii() and character.isdigit()
    ]
    if source_digits != translated_digits:
        raise ValueError(f"{locale}:{key}: 0-9 digits changed")
    if not _uses_expected_script(translated, key=key, locale=locale):
        raise ValueError(f"{locale}:{key}: expected native script is missing")


async def _translate_locale(
    client: AsyncOpenAI,
    *,
    model: str,
    locale: str,
    language: str,
    script: str,
    source: dict[str, str],
) -> dict[str, str]:
    response = await client.responses.parse(
        model=model,
        store=False,
        max_output_tokens=20_000,
        reasoning={"effort": "low"},
        text_format=TranslationBatch,
        instructions=(
            f"Translate an offline agricultural mobile-app UI catalog into {language} using "
            f"natural, concise {script}. Return every supplied key exactly once. Preserve "
            "KrishiSathi and Saathi as brand names, all {placeholder} tokens exactly, technical "
            "IDs, email, OpenWeather, Open-Meteo, OpenStreetMap, Mem0, and the digits 0-9. "
            f"Except for those preserved technical values, every translated value must contain "
            f"native {script} characters; never use Latin transliteration or another language's "
            "script. "
            "Translate error messages into calm farmer-friendly language. Do not add explanations."
        ),
        input=json.dumps(source, ensure_ascii=False),
    )
    parsed = response.output_parsed
    if parsed is None:
        raise ValueError(f"{locale}: model returned no parsed translation")
    translations = {item.key: item.value for item in parsed.translations}
    if len(translations) != len(parsed.translations):
        raise ValueError(f"{locale}: duplicate keys returned")
    if set(translations) != set(source):
        missing = sorted(set(source) - set(translations))
        extra = sorted(set(translations) - set(source))
        raise ValueError(f"{locale}: key mismatch missing={missing} extra={extra}")
    for key, translated in translations.items():
        _validate_translation(source[key], translated, key=key, locale=locale)
    return translations


async def _run(
    *,
    l10n_dir: Path,
    translate: bool,
    concurrency: int,
    locales: set[str] | None,
    repair_identical: bool,
) -> None:
    english_path = l10n_dir / "app_en.arb"
    english = _catalog(english_path)
    english_keys = _visible_keys(english)
    targets: list[tuple[str, Path, dict[str, Any], list[str]]] = []
    for locale in LANGUAGES:
        if locales is not None and locale not in locales:
            continue
        path = l10n_dir / f"app_{locale}.arb"
        catalog = _catalog(path)
        missing = [
            key
            for key in english_keys
            if key not in catalog
            or (
                repair_identical
                and key not in {"appName", "saathi"}
                and catalog.get(key) == english[key]
            )
            or not _uses_expected_script(str(catalog.get(key, "")), key=key, locale=locale)
        ]
        extra = [key for key in _visible_keys(catalog) if key not in english]
        if extra:
            raise ValueError(f"{locale}: unknown keys {extra}")
        targets.append((locale, path, catalog, missing))

    if not translate:
        incomplete = {locale: len(missing) for locale, _, _, missing in targets if missing}
        if incomplete:
            raise ValueError(f"incomplete catalogs: {incomplete}")
        print(json.dumps({"locales": len(targets) + 1, "keys": len(english_keys), "passed": True}))
        return

    from app.core.config import Settings

    settings = Settings()
    if not settings.openai_api_key.strip():
        raise ValueError("OPENAI_API_KEY is required to build missing translations")
    client = AsyncOpenAI(api_key=settings.openai_api_key)
    semaphore = asyncio.Semaphore(concurrency)

    async def update(target: tuple[str, Path, dict[str, Any], list[str]]) -> None:
        locale, path, catalog, missing = target
        if not missing:
            return
        language, script = LANGUAGES[locale]
        translated: dict[str, str] = {}
        model = (
            settings.openai_primary_model
            if locale in PRIMARY_TRANSLATION_LOCALES
            else settings.openai_light_model
        )
        for offset in range(0, len(missing), 40):
            batch_keys = missing[offset : offset + 40]
            source = {key: str(english[key]) for key in batch_keys}
            for attempt in range(1, 4):
                try:
                    async with semaphore:
                        batch = await _translate_locale(
                            client,
                            model=model,
                            locale=locale,
                            language=language,
                            script=script,
                            source=source,
                        )
                    translated.update(batch)
                    break
                except (OpenAIError, ValueError):
                    if attempt == 3:
                        raise
                    print(
                        json.dumps(
                            {"locale": locale, "offset": offset, "retry": attempt}
                        )
                    )
            for key in batch_keys:
                catalog[key] = translated[key]
                metadata_key = f"@{key}"
                if metadata_key in english:
                    catalog[metadata_key] = english[metadata_key]
            _write_catalog(path, catalog)
        for key in missing:
            catalog[key] = translated[key]
            metadata_key = f"@{key}"
            if metadata_key in english:
                catalog[metadata_key] = english[metadata_key]
        _write_catalog(path, catalog)
        print(json.dumps({"locale": locale, "added": len(missing)}))

    try:
        await asyncio.gather(*(update(target) for target in targets))
    finally:
        await client.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--l10n-dir",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "mobile" / "lib" / "l10n",
    )
    parser.add_argument("--translate", action="store_true")
    parser.add_argument(
        "--locale",
        action="append",
        choices=sorted(LANGUAGES),
        help="Limit translation to one locale; repeat for more than one.",
    )
    parser.add_argument(
        "--repair-identical",
        action="store_true",
        help="Retranslate non-brand entries that are still identical to English.",
    )
    parser.add_argument("--concurrency", type=int, default=2, choices=range(1, 5))
    args = parser.parse_args()
    asyncio.run(
        _run(
            l10n_dir=args.l10n_dir.resolve(),
            translate=args.translate,
            concurrency=args.concurrency,
            locales=set(args.locale) if args.locale else None,
            repair_identical=args.repair_identical,
        )
    )


if __name__ == "__main__":
    main()
