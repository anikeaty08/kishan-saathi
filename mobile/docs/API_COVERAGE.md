# KrishiSathi Mobile API Coverage

The mobile client points to `API_BASE_URL` and uses Cognito access tokens from
secure platform storage. `KrishiApi` mirrors every operation currently emitted
by the FastAPI OpenAPI document. UI code never performs raw HTTP requests.

| Backend capability | Mobile surfaces | Failure and privacy states |
| --- | --- | --- |
| Health and readiness | Startup/service diagnostics | Offline, timeout, provider unavailable |
| Profile | Onboarding, profile, language, notifications | Missing Cognito, validation details, unauthorized |
| Farms and deletion impact | Farm list, map, farm detail, add/edit/delete review | Empty farm, linked-data blocker, private cleanup |
| Plots, crops and crop cycles | Plot forms/detail, crop stage, plot metrics | At least one crop, stale local preview, deletion blocker |
| Activities and photos | Plot timeline and add-activity flow | Upload failure, private image loading, empty timeline |
| Diagnoses, retakes, images, predictions and feedback | Multi-image scan, processing, result, retake and feedback | Offline queue, 503 model unavailable, low confidence, quality flags |
| Diagnosis reports | Consent sheet, active shares, revoke and expert image access | Token-only public access, expiry, no-cache, sample disabled |
| Chat | Saathi list, scope selection, conversation and archive/delete actions | Idempotency key, archived chat, offline/AI unavailable |
| Memory | Profile memory manager and scoped chat context | Index retry, delete, disconnect blocker |
| Reminder proposals, actions and events | Reminder tabs, suggestion acceptance and completion | Expired proposal, recurring next action, optimistic rollback |
| Weather | Home weather and plot weather | Cached/stale timestamp, provider failure, location denied |
| Location search | Farm/plot location confirmation | Permission denied and manual search fallback |
| Timeline | Plot timeline with categories and paging | Empty and paged loading states |
| Object deletion retry | Privacy screen | Pending/failed cleanup with explicit retry |

## Contract Rules

- Backend errors are parsed from `error.code`, `error.request_id`, and
  `error.details`; UI copy is localized from codes rather than provider text.
- `204 No Content` is handled without JSON casting.
- Chat mutations send `Idempotency-Key`.
- Diagnosis and activity uploads are multipart and use longer timeouts.
- Public diagnosis reports send `X-Report-Token` without a bearer token.
- Access and refresh tokens are never stored in preferences, source, logs, or
  build-time configuration.
- Unsafe mutations are not automatically retried.
- The default emulator URL is `http://10.0.2.2:8000`; production builds should
  provide an HTTPS value with `--dart-define-from-file`.
