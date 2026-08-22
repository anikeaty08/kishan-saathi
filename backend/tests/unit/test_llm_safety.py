"""Tests for structurally enforced farmer-facing treatment safety."""

import pytest
from pydantic import ValidationError

from app.integrations.llm.provider import AssistantReply, TreatmentGuidance, TreatmentType
from app.integrations.llm.safety import reject_specific_treatment, reject_ungrounded_diagnosis


def test_chemical_treatment_requires_complete_structured_details() -> None:
    with pytest.raises(ValidationError, match="CHEMICAL_TREATMENT_DETAILS_REQUIRED"):
        TreatmentGuidance(
            treatment_type=TreatmentType.CHEMICAL,
            active_ingredient="Example active ingredient",
            application_method="Apply to affected foliage.",
            safety_precautions=["Wear label-required protective equipment."],
            consult_local_approved_guidance=True,
            weather_considered=True,
        )


def test_complete_typed_chemical_treatment_is_accepted() -> None:
    treatment = TreatmentGuidance(
        treatment_type=TreatmentType.CHEMICAL,
        active_ingredient="Example active ingredient",
        dosage="Use the locally approved label rate.",
        application_method="Apply to affected foliage according to the label.",
        frequency="Repeat only when the approved label permits it.",
        safety_precautions=["Wear label-required protective equipment."],
        consult_local_approved_guidance=True,
        weather_considered=True,
    )
    reply = AssistantReply(
        short_answer="The linked scan and field context support a treatment discussion.",
        treatment=treatment,
    )

    assert reply.treatment == treatment


def test_cultural_treatment_does_not_require_chemical_fields() -> None:
    reply = AssistantReply(
        short_answer="Remove affected plant debris and keep tools clean.",
        treatment=TreatmentGuidance(
            treatment_type=TreatmentType.CULTURAL,
            application_method="Remove affected debris without spreading it through the plot.",
            safety_precautions=["Clean tools after handling affected plants."],
            consult_local_approved_guidance=True,
            weather_considered=True,
        ),
    )

    assert reply.treatment is not None


def test_ordinary_irrigation_interval_is_not_treated_as_chemical_guidance() -> None:
    reject_specific_treatment("Check the soil daily and irrigate every 3 days only if it is dry.")


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
    with pytest.raises(ValueError, match="SPECIFIC_TREATMENT_SOURCE_NOT_CONFIGURED"):
        reject_specific_treatment(AssistantReply(short_answer=text))


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


def test_generic_disease_word_is_not_treated_as_a_diagnosis() -> None:
    reply = AssistantReply(
        short_answer=(
            "I can help you check for signs of disease and reduce fungal or bacterial spread "
            "without naming a condition."
        ),
        follow_up_questions=["Would you like to start a leaf scan for रोग के संकेत?"],
    )

    reject_ungrounded_diagnosis(reply)


def test_authorized_classifier_label_disables_diagnosis_rejection() -> None:
    reply = AssistantReply(
        short_answer="The trained scan result is tomato early blight and it is a disease."
    )

    # An authorized diagnosis permits natural language such as "disease".
    reject_ungrounded_diagnosis(
        reply,
        authorized_disease_names=("tomato early blight",),
    )
