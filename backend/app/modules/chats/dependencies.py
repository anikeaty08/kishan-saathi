"""Request-scoped chat dependency assembly."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.dependencies import (
    get_app_settings,
    get_current_weather_provider,
    get_database,
    get_db_session,
    get_forecast_weather_provider,
    get_llm_provider,
    get_memory_provider,
)
from app.database.session import DatabasePort
from app.integrations.llm.provider import LLMProvider
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider
from app.integrations.weather.provider import CurrentWeatherProvider, ForecastWeatherProvider
from app.modules.chats.repository import ChatRepository
from app.modules.chats.service import ChatService
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.memories.repository import MemoryRepository
from app.modules.reminders.repository import ReminderRepository
from app.modules.weather.tool import DatabasePlotForecastTool


def get_chat_service(
    settings: Annotated[Settings, Depends(get_app_settings)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
    database: Annotated[DatabasePort, Depends(get_database)],
    llm_provider: Annotated[LLMProvider, Depends(get_llm_provider)],
    memory_provider: Annotated[MemoryProvider, Depends(get_memory_provider)],
    current_weather_provider: Annotated[
        CurrentWeatherProvider, Depends(get_current_weather_provider)
    ],
    forecast_weather_provider: Annotated[
        ForecastWeatherProvider, Depends(get_forecast_weather_provider)
    ],
) -> ChatService:
    return ChatService(
        repository=ChatRepository(session),
        farms=FarmRepository(session),
        diagnoses=DiagnosisRepository(session),
        memory=memory_provider,
        llm=LLMRouter(llm_provider, settings),
        plot_forecast=DatabasePlotForecastTool(
            settings=settings,
            database=database,
            current_provider=current_weather_provider,
            forecast_provider=forecast_weather_provider,
        ),
        reminders=ReminderRepository(session),
        canonical_memory=MemoryRepository(session),
    )
