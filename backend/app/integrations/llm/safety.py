"""Deterministic farmer-visible safety policy for language-model output."""

import re
import unicodedata
from collections.abc import Iterable

from pydantic import BaseModel

from app.integrations.inference.plantwild_manifest import (
    PLANT_PATHOLOGY_ALIASES,
    PLANTWILD_DISEASE_LABELS,
)

_PRESCRIPTIVE_PATTERNS = (
    # Concentrations, area rates, and other dosage-like quantities in Latin text.
    re.compile(
        r"\b\d+(?:[.,]\d+)?\s*(?:mg|g|kg|ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)"
        r"\s*(?:/|per)\s*(?:l|lit(?:er|re)s?|kg|acre|hectare|ha)\b",
        re.IGNORECASE,
    ),
    # Common Roman-script treatment commands, including Romanized Indian-language prompts.
    re.compile(
        r"\b(?:spray|apply|mix|drench|inject|chhidkav|chhidkaav|phavarni|pichkari)\b"
        r".{0,100}\b(?:at|using|with|dose|dosage|ml|mg|gram|g/l|per\s+lit(?:er|re))\b",
        re.IGNORECASE,
    ),
    # Prescriptive treatment phrases in the most common requested native scripts.
    re.compile(
        r"(?=.{0,120}(?:\d|मिली|ملی|মিলি|மில்லி|మిల్లీ))"
        r"(?=.{0,120}(?:छिड़काव\s*करें|फवारणी\s*करा|স্প্রে\s*করুন|"
        r"தெளிக்கவும்|పిచికారీ\s*చేయండి|سپرے\s*کریں))",
        re.IGNORECASE,
    ),
)

# Disease-family words are intentionally policy data, not farmer-facing copy. The
# final class manifest will extend this vocabulary when the trained model is
# integrated. These families cover the current PlantWild labels and common ways
# a model could smuggle an unsupported diagnosis into an otherwise free-text
# response. The multilingual reviewer remains a second, broader semantic gate.
_DIAGNOSIS_PATTERNS = (
    re.compile(
        r"\b(?:"
        + "|".join(
            re.escape(item)
            for item in sorted(
                (*PLANTWILD_DISEASE_LABELS, *PLANT_PATHOLOGY_ALIASES),
                key=len,
                reverse=True,
            )
        )
        + r")\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:anthracnose|blight|mildew|rust|mosaic|virus|canker|rot|scab|"
        r"mould|mold|wilt|blast|scorch|leaf\s+spot|curl\s+virus|greening\s+disease|"
        r"cercospora|septoria)\b",
        re.IGNORECASE,
    ),
)


def _strings(value: object) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, BaseModel):
        yield from _strings(value.model_dump(mode="python"))
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, (list, tuple, set)):
        for item in value:
            yield from _strings(item)


def reject_specific_treatment(value: object) -> None:
    """Reject chemical dosage or mixing directions in unstructured visible fields.

    This deterministic check is intentionally paired with the multilingual LLM
    reviewer. Treatment frequency alone is deliberately allowed because ordinary
    irrigation, inspection, and cultural advice can also contain intervals. The
    typed treatment object carries any authorized chemical detail.
    """

    for raw_text in _strings(value):
        text = unicodedata.normalize("NFKC", raw_text)
        if any(pattern.search(text) for pattern in _PRESCRIPTIVE_PATTERNS):
            raise ValueError("SPECIFIC_TREATMENT_SOURCE_NOT_CONFIGURED")


def reject_ungrounded_diagnosis(
    value: object,
    *,
    authorized_disease_names: Iterable[str] = (),
) -> None:
    """Reject disease language that is not copied from classifier evidence.

    The language model may explain observations and uncertainty, but it is not a
    diagnosis authority. A specific disease label can appear in farmer-visible
    prose only when the backend supplied it from an authorized assessment.
    Generic words such as "disease", "fungal", and "bacterial" are not diagnoses
    by themselves and remain available for neutral prevention and follow-up
    guidance.
    This deterministic boundary complements, rather than replaces, the semantic
    multilingual safety reviewer.
    """

    authorized = tuple(
        unicodedata.normalize("NFKC", item).strip()
        for item in authorized_disease_names
        if item.strip()
    )

    # If a diagnosis is explicitly authorized for this turn, we trust the prompt
    # and the LLM reviewer to keep the discussion constrained to that diagnosis.
    # Banning generic words like "disease" or "रोग" prevents natural explanation.
    if authorized:
        return

    for raw_text in _strings(value):
        text = unicodedata.normalize("NFKC", raw_text)
        if any(pattern.search(text) for pattern in _DIAGNOSIS_PATTERNS):
            raise ValueError("UNGROUNDED_DIAGNOSIS_LANGUAGE")
