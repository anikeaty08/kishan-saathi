"""Tests for structurally enforced farmer-facing treatment safety."""

import pytest
from pydantic import ValidationError

from app.integrations.llm.provider import AssistantReply, TreatmentGuidance
from app.integrations.llm.safety import reject_ungrounded_diagnosis


def test_specific_treatment_is_disabled_without_authoritative_source() -> None:
    with pytest.raises(ValidationError, match="Extra inputs are not permitted"):
        TreatmentGuidance.model_validate({"active_ingredient": "Example", "dosage": "2 ml/L"})


def test_general_safety_guidance_is_accepted() -> None:
    reply = AssistantReply(
        short_answer="A treatment may be appropriate after confirming the diagnosis.",
        treatment=TreatmentGuidance(
            safety_precautions=["Wear label-required protective equipment"],
            consult_local_approved_guidance=True,
        ),
    )

    assert reply.treatment is not None


def test_specific_treatment_cannot_hide_in_safety_precautions() -> None:
    with pytest.raises(ValidationError, match="SPECIFIC_TREATMENT_SOURCE_NOT_CONFIGURED"):
        AssistantReply(
            short_answer="Use precautions.",
            treatment=TreatmentGuidance(
                safety_precautions=["Spray ExampleChemical at 2 g/L every 7 days; wear gloves"]
            ),
        )


@pytest.mark.parametrize(
    "text",
    [
        "Spray ExampleChemical at 2 g/L every 7 days.",
        "ExampleChemical ka chhidkav 2 ml per litre dose ke saath karein.",
        "ExampleChemical 2 मिली/लीटर का छिड़काव करें।",
        "ExampleChemical 2 মিলি/লিটার স্প্রে করুন।",
        "ExampleChemical 2 மில்லி/லிட்டர் தெளிக்கவும்.",
        "ExampleChemical 2 మిల్లీ/లీటర్ పిచికారీ చేయండి.",
        "ExampleChemical 2 ملی/لیٹر سپرے کریں۔",
    ],
)
def test_specific_treatment_is_rejected_in_every_visible_language_field(text: str) -> None:
    with pytest.raises(ValidationError, match="SPECIFIC_TREATMENT_SOURCE_NOT_CONFIGURED"):
        AssistantReply(short_answer=text)


def test_general_non_prescriptive_precautions_are_allowed() -> None:
    reply = AssistantReply(
        short_answer="Avoid touching affected leaves with bare hands.",
        general_precautions=["Wash hands after handling the plant."],
        consult_local_expert=True,
    )

    assert reply.consult_local_expert is True


def test_unsupported_disease_label_is_rejected_deterministically() -> None:
    for statement in (
        "Your tomato plant may have early blight.",
        "Your tomato plant has Phytophthora.",
        "The leaf is affected by Alternaria solani.",
    ):
        with pytest.raises(ValueError, match="UNGROUNDED_DIAGNOSIS_LANGUAGE"):
            reject_ungrounded_diagnosis(AssistantReply(short_answer=statement))


def test_only_exact_authorized_classifier_label_is_allowed() -> None:
    reply = AssistantReply(short_answer="The trained scan result is tomato early blight.")

    reject_ungrounded_diagnosis(
        reply,
        authorized_disease_names=("tomato early blight",),
    )

    with pytest.raises(ValueError, match="UNGROUNDED_DIAGNOSIS_LANGUAGE"):
        reject_ungrounded_diagnosis(
            AssistantReply(short_answer="The scan result is early blight."),
            authorized_disease_names=("tomato early blight",),
        )
