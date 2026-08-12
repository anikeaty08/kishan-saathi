"""Tests for structurally enforced farmer-facing treatment safety."""

import pytest
from pydantic import ValidationError

from app.integrations.llm.provider import AssistantReply, TreatmentGuidance


def test_specific_treatment_is_disabled_without_authoritative_source() -> None:
    with pytest.raises(ValidationError, match="SPECIFIC_TREATMENT_SOURCE_NOT_CONFIGURED"):
        TreatmentGuidance(active_ingredient="Example", dosage="2 ml/L")


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
