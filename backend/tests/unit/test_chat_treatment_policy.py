"""Tests for backend-owned treatment authorization boundaries."""

from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest

from app.core.errors import ApplicationError
from app.integrations.llm.provider import (
    AssistantReply,
    ChatRiskReason,
    TreatmentGuidance,
    TreatmentType,
)
from app.integrations.weather.provider import CurrentWeather, ForecastDay, PlotForecast
from app.modules.chats.models import ChatSession
from app.modules.chats.service import ChatService, PromptContext
from app.modules.weather.schemas import CurrentWeatherResponse, PlotForecastResponse

FARMER_ID = UUID("00000000-0000-0000-0000-000000000001")
PLOT_ID = UUID("00000000-0000-0000-0000-000000000002")


class RecordingWeatherTool:
    def __init__(self, *, stale: bool = False) -> None:
        self.stale = stale
        self.current_calls = 0
        self.forecast_calls = 0

    async def current(self, farmer_id: UUID, plot_id: UUID) -> CurrentWeatherResponse:
        assert (farmer_id, plot_id) == (FARMER_ID, PLOT_ID)
        self.current_calls += 1
        return CurrentWeatherResponse(
            weather=CurrentWeather(
                observed_at=datetime.now(tz=UTC),
                condition_code=800,
                condition="clear",
                temperature_c=28,
                feels_like_c=29,
                humidity_percent=60,
                wind_speed_mps=2,
            ),
            provider="openweather",
            fetched_at=datetime.now(tz=UTC),
            is_stale=self.stale,
        )

    async def forecast(self, farmer_id: UUID, plot_id: UUID) -> PlotForecastResponse:
        assert (farmer_id, plot_id) == (FARMER_ID, PLOT_ID)
        self.forecast_calls += 1
        return PlotForecastResponse(
            forecast=PlotForecast(
                timezone="Asia/Kolkata",
                generated_at=datetime.now(tz=UTC),
                days=[
                    ForecastDay(
                        date=date.today(),
                        condition_code=800,
                        temperature_min_c=20,
                        temperature_max_c=30,
                        precipitation_sum_mm=0,
                        precipitation_probability_max_percent=10,
                        wind_speed_max_kmh=12,
                    )
                ],
            ),
            provider="open-meteo",
            fetched_at=datetime.now(tz=UTC),
            is_stale=self.stale,
        )


def _service(weather: RecordingWeatherTool) -> ChatService:
    service = object.__new__(ChatService)
    service._plot_weather = weather
    return service


def _grounded_context() -> PromptContext:
    context = PromptContext()
    context.add_verified(
        "active_classifier_assessment",
        source="trained_leaf_classifier",
        assessment_id=str(uuid4()),
        primary_disease="tomato early blight",
        confidence_label="high",
    )
    context.add_untrusted(
        "diagnosis_linked_crop",
        "farmer_record",
        crop_id=str(uuid4()),
        name="Tomato",
        stage="fruiting",
    )
    return context


@pytest.mark.asyncio
async def test_specific_treatment_requires_scan_context_and_fresh_weather() -> None:
    weather = RecordingWeatherTool()
    service = _service(weather)
    chat = ChatSession(
        farmer_id=FARMER_ID,
        scope_type="diagnosis",
        diagnosis_case_id=uuid4(),
    )
    context = _grounded_context()

    allowed = await service._prepare_treatment_context(
        FARMER_ID,
        chat,
        PLOT_ID,
        context,
        risk_reason=ChatRiskReason.TREATMENT_SAFETY,
    )

    assert allowed is True
    assert weather.current_calls == 1
    assert weather.forecast_calls == 1
    assert {item.kind for item in context.provider_data} == {
        "current_plot_weather",
        "plot_forecast",
    }


@pytest.mark.asyncio
async def test_routine_question_never_fetches_weather_to_unlock_treatment() -> None:
    weather = RecordingWeatherTool()
    service = _service(weather)
    chat = ChatSession(
        farmer_id=FARMER_ID,
        scope_type="diagnosis",
        diagnosis_case_id=uuid4(),
    )

    allowed = await service._prepare_treatment_context(
        FARMER_ID,
        chat,
        PLOT_ID,
        _grounded_context(),
        risk_reason=ChatRiskReason.ROUTINE,
    )

    assert allowed is False
    assert weather.current_calls == 0
    assert weather.forecast_calls == 0


@pytest.mark.asyncio
async def test_stale_weather_does_not_unlock_specific_treatment() -> None:
    service = _service(RecordingWeatherTool(stale=True))
    chat = ChatSession(
        farmer_id=FARMER_ID,
        scope_type="diagnosis",
        diagnosis_case_id=uuid4(),
    )

    allowed = await service._prepare_treatment_context(
        FARMER_ID,
        chat,
        PLOT_ID,
        _grounded_context(),
        risk_reason=ChatRiskReason.TREATMENT_SAFETY,
    )

    assert allowed is False


def test_treatment_policy_blocks_unstructured_and_unauthorized_details() -> None:
    typed = TreatmentGuidance(
        treatment_type=TreatmentType.CHEMICAL,
        active_ingredient="Example active ingredient",
        dosage="2 g/L",
        application_method="Apply according to the approved label.",
        frequency="Repeat after 7 days only if the label permits.",
        safety_precautions=["Wear label-required protective equipment."],
        consult_local_approved_guidance=True,
        weather_considered=True,
    )
    with pytest.raises(ApplicationError, match="LLM_TREATMENT_CONTEXT_REQUIRED"):
        ChatService._validate_treatment_policy(
            AssistantReply(short_answer="Use the linked treatment details.", treatment=typed),
            allow_specific_treatment=False,
        )
    with pytest.raises(ApplicationError, match="LLM_TREATMENT_POLICY_VIOLATION"):
        ChatService._validate_treatment_policy(
            AssistantReply(short_answer="Spray ExampleChemical at 2 g/L."),
            allow_specific_treatment=True,
        )

    ChatService._validate_treatment_policy(
        AssistantReply(short_answer="Check the soil and water every 3 days only if it is dry."),
        allow_specific_treatment=False,
    )
