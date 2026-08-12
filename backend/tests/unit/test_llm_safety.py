"""Tests for structurally enforced farmer-facing treatment safety."""

import pytest
from pydantic import ValidationError

from app.integrations.llm.provider import AssistantReply, TreatmentGuidance


def test_structured_treatment_requires_safety_and_local_approval() -> None:
    with pytest.raises(ValidationError, match="TREATMENT_SAFETY_PRECAUTIONS_REQUIRED"):
        TreatmentGuidance(active_ingredient="Example", dosage="2 ml/L")


def test_safe_structured_treatment_is_accepted() -> None:
    reply = AssistantReply(
        short_answer="A treatment may be appropriate after confirming the diagnosis.",
        treatment=TreatmentGuidance(
            active_ingredient="Example active ingredient",
            dosage="Follow the locally approved product label",
            application_method="Target affected foliage only",
            safety_precautions=["Wear label-required protective equipment"],
            consult_local_approved_guidance=True,
        ),
    )

    assert reply.treatment is not None
