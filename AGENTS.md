# Repository Guidelines

This document is the single source of truth for Signal’s repo structure, client rules, media pipeline, CDN policy, APIs, telemetry, and working conventions.

## Project Structure
- iOS: `signal/signal/` (Swift/SwiftUI), Core in `signal/signal/Core`, Feed in `signal/signal/Feed`, Models/Utils under `signal/signal/Models|Utils`. Tests in `signal/signalTests` and `signal/signalUITests`.
- Android: `signal-android/app/src/main/` (Kotlin). Demo PlayerKit/feed classes exist at repo root; integrate into the app module.
- Pipeline/IaC: `mediaconvert-storyboard-template.json`, `sprite-vtt-generator.js` (Lambda), `terraform-cloudfront-cache.tf`. Product docs at repo root (`prd.md`, `Signal_Agent_Guide.md`).

## Client Rules (must meet)
- Vertical pager with snap feel; `PlayerPool(2–3)` reuses players; autoplay with audio ON; tap to play/pause.
- Long‑press scrub uses WebVTT storyboard sprites: ~8 FPS throttle, LRU ≈24, neighbor prefetch; resume only if it was playing before. Currently feature‑flagged OFF by default during stabilization.
- Startup bitrate cap: 400–700 kbps, lift after ~3s. Prefetch current + ~5–8 s next; consider previous when bandwidth allows.
- Error/empty UX: tap‑to‑retry overlay; accessibility labels for video surface and scrub overlay; show a friendly empty‑state when `items.isEmpty` (not loading) with "Pull to refresh or tap Retry" message and a Retry action.
- Pull‑to‑refresh: supported on both iOS and Android to reload the feed on demand.

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

Implemented event names include: `view_start`, `view_end`, `tap_play_pause`, `preview_scrub_start/commit` (flagged), `time_to_first_frame`, `rebuffer`, `selected_bitrate`, `playback_error`, and `playback_loop {video_id, loop_count}`.

## Build & Test
- iOS build: `xcodebuild -project signal/signal.xcodeproj -scheme signal -configuration Debug build`
- iOS tests: `xcodebuild -project signal/signal.xcodeproj -scheme signal -destination "platform=iOS Simulator,name=iPhone 15" test`
- Android build: `cd signal-android && ./gradlew assembleDebug`; unit tests: `./gradlew testDebugUnitTest`; instrumented: `./gradlew connectedAndroidTest`.

## Coding & PRs
- Swift/Kotlin: 4‑space indent; types `CamelCase`, members `camelCase`. One top‑level type per file. Use IDE formatters.
- Commits: imperative, scoped first line (e.g., `Feed: fix TTFF regression`). PRs: description + rationale + test notes; link tickets; screenshots for UI.

## Current Decisions
- Backend: Node/TypeScript on Lambda + API Gateway; DynamoDB (Videos), Redis (ElastiCache) for trending backfill, Kinesis Firehose→S3 for events. IaC in Terraform.
- HLS signing: Post‑GA (MVP uses CloudFront+OAC only).
- Exploration mix: 15% default, jitter 10–20%; server‑hinted via `/v1/feed`.
- Android: integrate PlayerKit/feed into `signal-android/app` now; modularize later.
- Samples: host versioned sample and provide `docs/samples/media_manifest.json` for offline runs.

## Env Vars
`API_BASE_URL`, `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `STORYBOARD_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`.

Backend (Lambda) additional:
- `FEED_LIMIT` (default 20)
- `FALLBACK_DAYS` (default 3; today + previous N−1)
- `TRENDING_REDIS_URL` (e.g., `rediss://<endpoint>:6379`)
- `TRENDING_REDIS_AUTH_SECRET_ARN` (Secrets Manager ARN holding Redis auth token)
- (Optional) `TRENDING_REDIS_AUTH_TOKEN` for dev/local when no secret is used

## Implemented (iOS)
- Autoplay: visible player only; prefetch players prepared with `autoPlay=false`.
- Single play trigger: starts when item is ready and attached; no duplicate play paths.
- Looping: seamless in‑view loop; emits `playback_loop` on each wrap; `view_end` only on exit.
- Pause guarantees: user pause disables auto‑resume for that item; pauses any non‑visible players.
- Background policy: if backgrounded ≥120s, cold‑start feed and release players on foreground.
- Long‑press scrub: disabled by default via `ENABLE_LONG_PRESS_SCRUB`; scaffolded state machine for safe resume‑only‑if‑was‑playing.
- Gesture tuning: tap attached to video surface; non‑cancelling; paging enabled (in progress: see challenges).
- Empty state: `EmptyFeedView` with "Pull to refresh or tap Retry" and accessibility labels; Retry calls `FeedViewModel.loadInitialFeed()`.
- Pull‑to‑refresh: `FeedView` uses `.refreshable { await loadInitialFeed() }`.

## Implemented (Android)
- Visible‑only playback enforcement on user action; pauses other bound items when one starts.
- Long‑press scrub disabled by default via `BuildConfig.ENABLE_LONG_PRESS_SCRUB`.
- Feed networking wired; PlayerKit integrated.
- Empty state: friendly message with "Pull to refresh or tap Retry" and a Retry button that re‑fetches the feed.
- Pull‑to‑refresh: `SwipeRefreshLayout` wraps `ViewPager2`; refresh triggers feed reload.
- Background policy: mirrors iOS 120s cold‑start behavior (release players and refetch on resume after ≥120s).

## Data & Backend
- `/v1/feed`, `/v1/events` (Firehose→S3), `/v1/manifest` with `hls_url` override for testing.
- Seeding: `scripts/seed_videos.mjs` supports `HLS_MAP` and `HLS_LIST` for one‑shot multi‑video insert.

Feed service resiliency (TikTok‑style best practice):
- Multi‑day window over GSI2 (`day_bucket/-engagement_score`): query today then previous `FALLBACK_DAYS−1` days until `FEED_LIMIT` items or exhaustion. De‑dupe by `video_id`. No table scans in production.
- Trending backfill via Redis (ElastiCache) ZSET `trending:v1`: if the window yields < `FEED_LIMIT`, fill remaining from the ZSET (highest rank first), then `BatchGetItem` missing attributes from DynamoDB. Reason codes logged (`fallback_prev_day`, `fallback_trending`).
- Trending writer Lambda: scheduled (EventBridge, ~5 min) to rebuild `trending:v1` from recent GSI2 results; size ~500–1000.
- Observability: log fallback paths; alert if empty responses > threshold.

## Current Challenges
- iOS vertical paging intermittently blocked by gesture priority: child gestures can preempt `UIPageViewController` pan. Pending fix: require child tap/long‑press to fail against `pageViewController.gestureRecognizers` (pan) rather than the internal scroll view recognizer.
- Storyboard previews blank on demo streams without `#xywh` VTT; expected until pipeline assets are available.
- Backend infra: when Lambdas are VPC‑attached, ensure Interface VPC Endpoints exist for Secrets Manager, KMS, and Logs (plus Gateway endpoint for DynamoDB). Without them, calls can time out and cause 500s.

## Next Phase
- iOS: finalize paging fix (wire require‑to‑fail to `pageViewController.gestureRecognizers`), verify snap + tap coexist.
- Android: confirm loop parity and gesture tuning; validate empty‑state + pull‑to‑refresh on slow networks.
- Backend: keep Redis trending backfill on; maintain `FALLBACK_DAYS`/`FEED_LIMIT` via env vars; trending writer health checks.
- Infra: keep Lambdas VPC‑attached with Interface Endpoints (Secrets, KMS, Logs) and DynamoDB gateway endpoint; Lambda timeout 10s.
- Pipeline: storyboard Lambda integration test; add real VTT+sprites to enable scrub thumbnails.
- Telemetry: add dashboard queries for `playback_loop`, dwell per loop, and CDN KPIs.
