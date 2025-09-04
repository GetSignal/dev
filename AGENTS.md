# Repository Guidelines

This document is the single source of truth for Signal’s repo structure, client rules, media pipeline, CDN policy, APIs, telemetry, and working conventions.

## Project Structure
- iOS: `signal/signal/` (Swift/SwiftUI), Core in `signal/signal/Core`, Feed in `signal/signal/Feed`, Models/Utils under `signal/signal/Models|Utils`. Tests in `signal/signalTests` and `signal/signalUITests`.
- Android: `signal-android/app/src/main/` (Kotlin). Demo PlayerKit/feed classes exist at repo root; integrate into the app module.
- Pipeline/IaC: `mediaconvert-storyboard-template.json`, `sprite-vtt-generator.js` (Lambda), `terraform-cloudfront-cache.tf`. Product docs at repo root (`prd.md`, `Signal_Agent_Guide.md`).

## Client Rules (must meet)
- Vertical pager with snap feel; `PlayerPool(2–3)` reuses players; autoplay with audio ON; tap to play/pause.
- Long‑press scrub uses WebVTT storyboard sprites: ~8 FPS throttle, LRU ≈24, neighbor prefetch; resume only if it was playing before.
- Startup bitrate cap: 400–700 kbps, lift after ~3s. Prefetch current + ~5–8 s next; consider previous when bandwidth allows.
- Error UX: tap‑to‑retry overlay; accessibility labels for video surface and scrub overlay.

## APIs (contracts)
- GET `/v1/feed?cursor=…` → items with `media_manifest_url` and metadata.
- POST `/v1/events` (batched ~200 ms) with events: `view_start`, `view_end(dwell_ms,percent_complete)`, `tap_play_pause`, `preview_scrub_start/commit`, `time_to_first_frame`, `rebuffer`, `selected_bitrate`, `playback_error`.
- `media_manifest.json`: `video_id`, `duration_ms`, `hls_url`, `poster_url`, `thumbnail_vtt_url`, `ladder[]`, `loudness_lufs`, `created_at` (versioned path `/{video_id}/vN/...`).

## Media Pipeline (7 stages)
Direct S3 multipart upload (Cognito) → Inspect/Moderate → MediaConvert (CMAF/HLS, 2s GOP, QVBR) → Lambda post‑step builds sprite JPGs + WebVTT (#xywh) → Publish `media_manifest.json` → CloudFront (OAC) delivery → Playback + telemetry.

## CDN & Cache Policy
- Versioned immutable paths; no cookies/headers/query in cache key.
- Sprites/VTT/posters: 1y immutable. Segments: 7–30d immutable. Manifests: 15–60s + `stale-while-revalidate, stale-if-error=60`.

## Telemetry
- Single shared EventBus per app; batch/debounce ~200 ms; include `device_id`, `session_id`, `ts`. iOS uses URLCache ≥256 MB; Android OkHttp cache ≥50 MB for storyboard assets.

## Build & Test
- iOS build: `xcodebuild -project signal/signal.xcodeproj -scheme signal -configuration Debug build`
- iOS tests: `xcodebuild -project signal/signal.xcodeproj -scheme signal -destination "platform=iOS Simulator,name=iPhone 15" test`
- Android build: `cd signal-android && ./gradlew assembleDebug`; unit tests: `./gradlew testDebugUnitTest`; instrumented: `./gradlew connectedAndroidTest`.

## Coding & PRs
- Swift/Kotlin: 4‑space indent; types `CamelCase`, members `camelCase`. One top‑level type per file. Use IDE formatters.
- Commits: imperative, scoped first line (e.g., `Feed: fix TTFF regression`). PRs: description + rationale + test notes; link tickets; screenshots for UI.

## Current Decisions
- Backend: Node/TypeScript on Lambda + API Gateway; DynamoDB (Videos), Redis for hot queues, Kinesis Firehose→S3 for events. IaC in Terraform.
- HLS signing: Post‑GA (MVP uses CloudFront+OAC only).
- Exploration mix: 15% default, jitter 10–20%; server‑hinted via `/v1/feed`.
- Android: integrate PlayerKit/feed into `signal-android/app` now; modularize later.
- Samples: host versioned sample and provide `docs/samples/media_manifest.json` for offline runs.

## Env Vars
`API_BASE_URL`, `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `STORYBOARD_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`.
