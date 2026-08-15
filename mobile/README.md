# KrishiSathi Mobile

KrishiSathi is the adaptive Flutter client for the farmer assistant. It keeps
the product focused around four primary destinations: Home, Farm, Scan, and
Saathi. Secondary workflows such as weather, reminders, profile, privacy,
memory, and support remain reachable without crowding the main navigation.

## Product surfaces

- Email/password onboarding through Amazon Cognito, with an explicit preview
  mode when cloud configuration is unavailable.
- Phone-location weather on Home and stored-location current weather plus a
  seven-day forecast for each plot.
- Multi-farm, multi-plot, and multi-crop records with crop cycles, activities,
  photos, map confirmation, filters, and chronological history.
- Camera or gallery leaf checks with one or more photos, optional crop context,
  plot linking, offline queueing, retakes, per-image quality, cautious
  confidence states, feedback, chat continuation, and consented report sharing.
- General, farm, plot, and diagnosis chats with archive, memory connection,
  reminder proposals, offline drafts, and backend idempotency keys.
- Reminder actions, scoped Saathi memory review, privacy cleanup, theme and
  language settings, loading/empty/error/success states, and large-text support.

The app never substitutes an LLM for the trained leaf classifier. The backend
must expose the evaluated classifier through the existing diagnosis contract.
Image progression also remains a separate capability: it must not be inferred
from confidence changes alone.

## Supported devices

- Android API 24 and newer, including compact phones and tablets.
- iPhone and iPad on iOS 15 and newer.
- Layout decisions use available width rather than a phone model. Safe areas,
  keyboard insets, RTL direction, landscape, tablet navigation, and accessible
  text scaling are handled by shared adaptive components.

Android APKs can be built on Windows. A signed iOS archive must be produced on
macOS with Xcode and the project signing team.

## Runtime configuration

Copy `config/dev.example.json` to a git-ignored local file, for example
`config/dev.local.json`:

```json
{
  "API_BASE_URL": "http://10.0.2.2:8000",
  "AWS_REGION": "ap-south-1",
  "COGNITO_USER_POOL_ID": "ap-south-1_example",
  "COGNITO_APP_CLIENT_ID": "public-app-client-id",
  "APP_ENV": "development"
}
```

The Cognito client is public and must not have a client secret. OpenAI, Mem0,
OpenWeather, database, storage, and model-service credentials belong only in
the FastAPI backend; they must never be compiled into the APK.

Start the local backend and run:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/dev.local.json
```

`10.0.2.2` reaches the host from an Android emulator. Use the computer's LAN IP
for a physical device, and use HTTPS outside local development.

## Verification

```powershell
flutter analyze
flutter test
flutter build apk --release --split-per-abi `
  --dart-define-from-file=config/dev.local.json
```

Split APKs keep download size materially below the universal debug build. Never
judge release size from the debug APK, which contains VM and debugging assets.

## Localization policy

The locale selector includes English and all 22 languages in the Eighth
Schedule of the Indian Constitution. UI copy is resolved from bundled catalogs;
there is no Google Translate or other runtime screen translator. English is the
source catalog and missing reviewed entries deliberately fall back to English
instead of displaying invented agricultural wording. Before a public launch,
each catalog and the canonical crop/disease glossary must be reviewed by native
speakers with agricultural expertise.

## Architecture

The code is feature-first. Screens call `AppController`, which coordinates
typed repositories; repositories use the single authenticated `KrishiApi`
boundary. Cognito tokens stay in platform secure storage. UI widgets do not
perform raw HTTP requests and do not parse provider-specific errors.

See [API coverage](docs/API_COVERAGE.md) for the mobile-to-backend contract.
