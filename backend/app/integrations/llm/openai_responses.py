"""OpenAI Responses API structured-output adapter."""

import hashlib

import openai
from openai import AsyncOpenAI

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.llm.provider import AssistantReply, LLMProvider, LLMRequest, LLMResult


class OpenAIResponsesProvider(LLMProvider):
    """Use Responses API Structured Outputs with no provider-side conversation state."""

    def __init__(
        self,
        settings: Settings,
        *,
        client: AsyncOpenAI | None = None,
    ) -> None:
        self._client = client or AsyncOpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.external_request_timeout_seconds,
            max_retries=2,
        )
        self._owns_client = client is None

    async def respond(self, request: LLMRequest, *, model: str) -> LLMResult:
        safety_identifier = hashlib.sha256(str(request.farmer_id).encode()).hexdigest()
        try:
            response = await self._client.responses.parse(
                model=model,
                instructions=request.instructions,
                input=request.input_text,
                text_format=AssistantReply,
                store=False,
                safety_identifier=safety_identifier,
                max_output_tokens=1200,
                reasoning={"effort": "low"},
            )
        except openai.AuthenticationError as exc:
            raise ApplicationError(code="LLM_AUTHENTICATION_FAILED", status_code=503) from exc
        except (openai.APITimeoutError, openai.APIConnectionError, openai.RateLimitError) as exc:
            raise ApplicationError(code="LLM_TEMPORARILY_UNAVAILABLE", status_code=503) from exc
        except openai.APIError as exc:
            raise ApplicationError(code="LLM_PROVIDER_ERROR", status_code=502) from exc

        reply = response.output_parsed
        if reply is None:
            raise ApplicationError(code="LLM_INVALID_RESPONSE", status_code=502)
        return LLMResult(
            reply=reply,
            provider_response_id=response.id,
            model=model,
        )

    async def close(self) -> None:
        if self._owns_client:
            await self._client.close()
