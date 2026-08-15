# KrishiSathi Frontend Completion Audit

Audit date: 13 August 2026

This audit compares the Flutter client, the product requirements in the root
documents, and the alternate `frontened/` folder. Passing analysis or a narrow
widget test is not treated as proof of product completion.

## Design direction

- **Visual thesis:** a calm field journal joined with a precise crop-diagnostic
  instrument—real Indian field photography carries identity while operational
  screens remain quiet and readable.
- **Palette:** forest `#173B2C`, leaf `#2E7D4F`, mineral `#F3F6EF`, soil
  `#5C4938`, harvest amber `#D5A43B`, and weather sky `#397B9D`.
- **Typography:** Material 2021 scale with deliberately compact display sizes
  and Noto system fallbacks for the scheduled Indian scripts.
- **Signature:** crop-aware photographic bands identify farms and plots without
  turning routine data screens into decorative card mosaics.
- **Navigation:** four stable destinations—Home, Farm, Scan, and Saathi. Profile,
  weather, reminders, privacy, memory, and help are secondary routes.

## Alternate frontend and asset audit

The `frontened/` directory is not another application. It contains nine source
images only. All seven photographic assets are present byte-for-byte in
`mobile/assets/images`. Logo concept v2 is present byte-for-byte as
`mobile/assets/branding/app_icon.png`; it was selected because its simpler leaf,
field, and sun geometry survives small launcher sizes better than concept v1.

The app adds four separately generated, continuous crop photographs for rice,
wheat, cotton, and banana. They use the same warm editorial daylight and rural
Indian field language. They are WebP files under 140 KB each; no collage or
cropped multi-panel artwork is used.

| Asset role | Evidence | Result |
| --- | --- | --- |
| App icon and native splash | Android mipmaps, iOS AppIcon, light/dark splash assets | Implemented |
| Onboarding/auth hero | One continuous field photograph, not a four-panel collage | Implemented |
| Farm and plot identity | Crop-aware image selection for tomato, maize, ragi, rice, wheat, cotton, and banana | Implemented |
| Leaf guidance and result imagery | Healthy-leaf and blight imagery | Implemented |
| Farmer identity | Editorial farmer portrait used only in profile/header contexts | Implemented |

## Requirement evidence matrix

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Four primary navigation destinations | `AppShell`, mobile `NavigationBar`, medium/expanded `NavigationRail` | Implemented |
| Android and iOS projects | Android API 24+ and iOS 15+ source, permissions, icons, splash | Implemented; signed iOS archive needs macOS |
| Compact, medium, expanded layouts | Width-based branches at 600/760/840/940 px; tests at 320, 360, 390, 430, and 1024 px | Implemented |
| Safe areas and accessible text | Shared safe-area/content primitives; 200% text-scale regression tests cover the shell and confirmed plot-map form | Implemented |
| Login, signup, confirmation, password reset | Cognito client and complete auth UI | Implemented; live use needs Cognito configuration |
| Onboarding name, language, permissions | Separate resumable screens; farm setup stays optional | Implemented |
| Home greeting, phone weather, tasks, farm entry, recent scans, general chat entry | `HomeScreen` and weather route | Implemented |
| Farm/plot/multi-crop management | CRUD, deletion-impact review, map confirmation, crop lifecycle and area-unit preference | Implemented |
| Location search and confirmed pointer | Backend-mediated Open-Meteo geocoding, device location, tappable `flutter_map` pointer, visible OSM attribution, and configurable tile endpoint | Implemented; public OSM tiles are hackathon/development only |
| Activities and optional photos | Create/read/edit/delete, crop/time association, partial-upload handling | Implemented |
| Combined plot timeline | Crop/category/date filters and pagination | Implemented |
| One or more leaf images and optional crop name | Camera/gallery selection, removal before submit, plot optionality | Implemented |
| Offline leaf scan | Durable local photo queue and automatic resubmission | Implemented |
| Diagnosis result, alternatives, quality/confidence, retake, feedback, reports, linked chat | Scan and result flows | Implemented at UI/contract level; real inference needs the trained artifact |
| Separate repeated-scan progression | Product decision is on hold; confidence changes are never misrepresented as progression | Intentionally deferred |
| General/farm/plot/scan chats | Scoped creation, filtering, archive/rename/delete, drafts, connection to memory | Implemented |
| Reminder proposal consent and task actions | Accept/decline plus done/skip/reschedule/cancel; manual recurring reminders | Implemented |
| Plot memory review and deletion | Farm/plot views, pagination, retry/delete and chat connect/disconnect | Implemented |
| Weather current/forecast and stale state | Phone current weather; plot current plus seven-day forecast; one-hour cache metadata | Implemented |
| Loading, empty, error, success, offline, low-confidence states | Shared state components and feature-specific recovery actions | Implemented |
| Selected area measurement | Persistent acres/hectares choice and display conversion | Implemented |
| English plus all 22 scheduled-language selectors and RTL | Bundled locale registry, native names, system-font fallbacks, Urdu/Kashmiri/Sindhi RTL | Infrastructure implemented |
| Every screen fully translated | English source copy is still partly embedded in feature widgets and non-English catalogs are incomplete | **Incomplete—must not be claimed complete** |
| Reviewed crop/disease glossary | Final 89-class manifest and native agronomy review are not available | **External content blocker** |
| Offline reading of private farm/chat history | Durable scans and drafts exist; an approved encrypted structured cache has not been selected | **Incomplete architecture decision** |
| Push notifications and multilingual voice | Explicitly deferred from the hackathon scope | Deferred |

## Current verification

- `flutter analyze --no-pub`: clean on the final mobile worktree.
- `flutter test --no-pub`: 27 tests passed. Coverage includes 320–1024 px
  widths, medium/expanded navigation rails, landscape, RTL, dark mode system-bar
  contrast, 200% text scaling, plot pointer confirmation, error localization,
  area conversion, history filtering, weather states, and the four primary
  destinations.
- Release split APKs built successfully: 40.9 MB armeabi-v7a, 43.1 MB arm64-v8a,
  and 44.5 MB x86_64.
- The x86_64 release APK installed and launched on the project Pixel 6 emulator
  at 1080×2400; Android reported KrishiSathi as the resumed activity with no
  Flutter fatal exception or app ANR, and the Home screen was visually reviewed.
- A credential-pattern audit found none of the provider keys pasted in chat in
  `mobile/` source or assets.
- Visual inspection covered the alternate logo concepts, authentication hero,
  crop imagery, and rendered Home/Farm/Scan/Saathi compact layouts.

## Required completion work

1. Move every farmer-visible English literal into the source language catalog.
2. Complete all 22 language packs and review every pack with native speakers;
   review the agriculture glossary separately with domain experts.
3. Select and implement encrypted offline caching for private farm, diagnosis,
   timeline, and chat summaries before claiming full offline-first behavior.
4. Connect the user's trained classifier with its class manifest and exact
   preprocessing contract, then run end-to-end scan tests.
5. Produce and test a signed iOS archive on macOS.

Until these items are evidenced, the Flutter implementation is a strong,
testable frontend foundation—not a fully production-complete multilingual app.
