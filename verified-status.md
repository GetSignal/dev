Here’s a grounded, repo-verified status read on the three files, tied back to AGENTS.md and what’s in code today.

  Summary

  - Feed and clients: In good shape and aligned with AGENTS.md (vertical pager, PlayerPool, prefetch, empty state, pull-to-
  refresh, startup bitrate cap).
  - Events API: Basic ingestion to Firehose exists; the robust schema/sanitization/rate-limit/testing stack described in
  Phase‑2A docs is not implemented.
  - Pipeline: Templates and Lambda source are present, but MediaConvert + storyboard integration is not wired in IaC.

  1) Phase-2A-Tasks/upcoming-tasks.md

  -
      1. Implement /v1/events (P1): Partially implemented
      - Code: services/api/src/events.ts posts batches to Firehose and returns 200/400. IaC wires POST /v1/events → Lambda
  → Firehose (iac/api/apigw.tf, iac/api/lambdas.tf, iac/events/firehose.tf).
      - Missing vs spec: No envelope/event schema validation; no PII/truncation; no rate limiting; no consistent error
  format; no tests; no monitoring.
      - Status: In progress (minimum viable ingest live); robustness paused.
  -
      2. /v1/feed client integration (P1): Implemented
      - iOS: FeedViewModel hits GET {API_BASE_URL}/v1/feed, loads media_manifest.json, prefetches neighbors; EventBus posts
  to /v1/events.
      - Android: FeedService fetches /v1/feed and per-item manifest; FeedPagerActivity binds and plays.
      - Backend feed: services/api/src/feed.ts implements GSI2 multi-day window + Redis trending backfill, dedupe,
  exploration rate. IaC present.
      - Status: Implemented (cursor currently null; acceptable for MVP).
  -
      3. Android vertical pager (P1): Implemented
      - ViewPager2 vertical snap, visible-only play, pauses others, error overlay with tap-to-retry, accessibility, pull-
  to-refresh (SwipeRefreshLayout) present. Long-press scrub behind feature flag.
      - Status: Implemented, gesture tuning ongoing as per AGENTS.md.
  -
      4. Android PlayerKit & storyboard (P1): Implemented
      - PlayerKit: PlayerKit-Android.kt with ExoPlayer, bitrate cap, TTFF, rebuffer/bitrate telemetry.
      - Storyboards: WebVTT #xywh parsing, LRU≈24, neighbor prefetch, ~8 FPS throttle, OkHttp cache ≥50MB (in app/.../
  FeedPagerActivity.kt).
      - Status: Implemented; storyboard UX gated by asset availability.
  -
      5. Deploy AWS media pipeline: Partially scaffolded
      - Present: storyboard Lambda source (sprite-vtt-generator.js), MediaConvert template, CloudFront cache TF, Firehose,
  API Lambdas, Redis trending writer + VPC endpoints.
      - Missing: MediaConvert job orchestration + Lambda wiring in Terraform, manifest publish step, CloudFront OAC/media
  origins, integration tests.
      - Status: Paused at infra wiring/integration.

  2) Phase-2A-Tasks/events_api_implementation_prompt.md (against code)

  - Phase 1 (schema foundation: envelope, event types, validator): Not implemented
      - No files under /services/api/events/schema/*; the handler accepts/forwards raw JSON.
  - Phase 2 (routes, parser, response): Partially implemented
      - Route is defined in Terraform; handler parses JSON inline; responses are minimal (200/400), not the standardized
  200/202/400 with structured error body.
  - Phase 3 (PII detection, truncation, sanitization middleware): Not implemented
      - No /sanitization/* modules or middleware orchestration.
  - Phase 4 (rate limiting): Not implemented
      - No Redis token bucket; no 429 handling.
  - Phase 5 (queue integration): Partial
      - Uses Firehose (as per AGENTS.md “Kinesis Firehose→S3”), but no retry/backoff or graceful outage handling beyond
  catch → 400.
  - Phase 6 (testing): Not implemented
      - No Jest tests or coverage thresholds.
  - Phase 7 (ops/monitoring): Minimal
      - Console logs only; no health checks/metrics.

  Alignment with AGENTS.md: Acceptable to use Firehose; however, AGENTS.md also expects proper telemetry envelope
  (device_id, session_id, ts) and batch/debounce from clients—iOS and Android satisfy this; server-side validation and
  protection layers are still missing.

  3) Phase-2A-Tasks/events_api_subtasks.md (task-by-task status)

  - 1a–1c (schemas + validator): Not implemented
  - 2a (route): Implemented in Terraform; not as a code “routes.js” with middleware
  - 2b–2c (parser + response): Partially implemented (inline JSON.parse + minimal 200/400)
  - 3a–3c (PII/truncation/middleware): Not implemented
  - 4 (rate limiting): Not implemented
  - 5 (queue adapters/retries): Partial (Firehose only; no retries/order guarantees)
  - 6a–6d (tests): Not implemented
  - 7 (error handling/monitoring): Minimal logs only

  Client + Telemetry compliance (AGENTS.md cross-check)

  - iOS
      - Autoplay, PlayerPool, startup bitrate cap 700 kbps with 3s lift, visible-only play, looping with playback_loop,
  background ≥120s cold-start: Implemented (Core/PlayerKit.swift, FeedViewModel).
      - EventBus batching ~200 ms, envelope with device_id/session_id/ts, events match spec: Implemented (Core/
  EventBus.swift).
      - Long-press scrub: scaffolded and disabled by default: Paused behind flag.
      - Pull-to-refresh + empty state + accessibility: Implemented.
      - Known challenge: paging gesture priority: In progress per AGENTS.md; not yet fixed.
  - Android
      - Vertical pager + visible-only playback + pause others: Implemented.
      - EventBus posts to "$API_BASE/v1/events": Implemented (app FeedPagerActivity).
      - Long-press scrub: Implemented and disabled by default via BuildConfig.ENABLE_LONG_PRESS_SCRUB=false.
      - Pull-to-refresh + empty state with “Pull to refresh or tap Retry”: Implemented.
      - Background ≥120s cold-start behavior: Implemented.

  Next Steps (prioritized, best‑practice)

  - Events API robustness (Phase‑2A P1)
      - Add schema validation: implement /services/api/events/schema/{envelope,eventTypes,validator}.ts using a fast
  validator (e.g., AJV). Enforce batch size, required fields, and per-event props from AGENTS.md.
      - Add sanitization: /sanitization/{piiDetector,fieldTruncator,middleware}.ts for email/phone patterns and field
  length limits; log redactions.
      - Rate limiting: Redis token bucket keyed by device_id with 60s windows; return 429 on exceed; DynamoDB fallback
  path.
      - Reliability: wrap Firehose put with transient retry/backoff; 500 on persistent failure; structured logs +
  on business logic.
  - Pipeline wiring (remain in 2A scope)
      - Terraform resources to invoke MediaConvert, run storyboard Lambda, publish media_manifest.json, and configure
  CloudFront OAC origins for manifests/sprites/HLS; add CI packaging for storyboard Lambda.
      - Add an integration test to validate WebVTT #xywh and sprite delivery through CDN.
  - iOS paging gesture (carryover from Current Challenges)
      - Wire child gesture require‑to‑fail against pageViewController.gestureRecognizers and verify snap + tap coexistence.
  - Observability
      - Dashboards/alarms for /v1/feed fallbacks (fallback_prev_day, fallback_trending) and events ingest error/429 rates.
      - Telemetry queries for playback_loop, dwell per loop, CDN KPIs (as in Next Phase).


## Differences, Relationships or Redundancies ##

> Big Picture

  - upcoming-tasks.md: Roadmap view. Lists Phase 2A core items (events API, feed integration, Android parity, pipeline)
  plus later phases (social, creator tools).
  - events_api_implementation_prompt.md: Implementation brief. Deep spec for the Events API only (objectives, constraints,
  ordering, perf/PII/rate-limits/testing/ops).
  - events_api_subtasks.md: Checklist. Same Events API scope distilled into deliverables, acceptance criteria, and
  estimates with a dependency graph.

  Relationships

  - upcoming-tasks.md → calls out “Implement /v1/events” (P1). The other two files expand that single item.
  - events_api_implementation_prompt.md → references the subtasks doc as the “implementation roadmap.”
  - events_api_subtasks.md → operationalizes the prompt’s narrative into concrete files to create and tests to add.

  Overlap/Redundancies

  - Scope duplication (Events API): The prompt and subtasks both enumerate 1a/1b/1c … 7, with similar deliverables:
      - Schemas: /services/api/events/schema/{envelope,eventTypes,validator}.js
      - Handlers: /services/api/events/handlers/{requestParser,responseFormatter}.js
      - Sanitization: /services/api/events/sanitization/{piiDetector,fieldTruncator,middleware}.js
      - Rate limiting + queue integration + tests + ops
  - Ordering duplication: Both documents include the same dependency order; “Phase” labels are reused in different
  meanings:
      - Roadmap “Phase 2A” (project phase) vs. Prompt “Phase 1–7” (events API internal phases). This naming overlap can
  confuse.
  - Acceptance criteria vs. “Critical Requirements”: Many of the subtasks’ acceptance bullets restate the prompt’s Critical
  Requirements and Error Handling Standards.

  Differences

  - Breadth:
      - upcoming-tasks.md covers multiple tracks (Events API, feed, Android UI/PlayerKit, pipeline, later social/creator
  work).
      - The other two focus exclusively on the Events API.
  - Depth:
      - events_api_implementation_prompt.md adds standards not in subtasks: performance targets (<100ms validation), PII
      - events_api_subtasks.md adds time estimates and per-task acceptance criteria; concise and execution-oriented.
  - Terminology and stack:
      - Prompt lists “Kinesis Streams” as primary telemetry queue; AGENTS.md and the codebase use Firehose→S3 for events.
  Subtasks are agnostic (say “Kinesis/S3/Redis adapters”).

  Notable Inconsistencies with AGENTS.md and Code

  - Telemetry sink:
      - AGENTS.md: “Kinesis Firehose→S3 for events.”
      - Code: services/api/src/events.ts uses Firehose.
      - Prompt: names “Kinesis Streams” as primary; this conflicts with both AGENTS.md and current code.
  src/events.ts Lambda handler. The docs are aligned with each other, but diverge from code structure today.

  ## Suggested Consolidation ##

  - Keep events_api_subtasks.md as the canonical execution checklist (deliverables + acceptance criteria + dependencies).
  - Trim events_api_implementation_prompt.md to contextual requirements not covered by the checklist (PII policy, perf
  goals, error standards, monitoring), and link directly to the checklist for tasks.
  - In the prompt, align the telemetry sink terminology with AGENTS.md/code (“Firehose→S3”) or explicitly support both
  (Streams optional), to avoid conflicting guidance.
  - Disambiguate “Phase” naming by renaming the prompt’s phases to “Stage 1–7” to avoid confusion with roadmap “Phase



  Safe to delete to avoid overlaps/redundancies

  - FeedViewController.swift
  - SwiftUIFeedView.swift
  - PlayerKit-iOS.swift
  - PlayerKit-Android.kt
  - FeedFragment.kt
  - FeedPagerActivity.kt (root-level, not the app module version)
  - xcode.md
  - output.md
  - build-packages-error.md
  - test.json