# Signal — Agent Guide (Production Build Spec)
**Date:** 2025-08-16 • **Audience:** AI coding assistant • **Goal:** Build/extend the *Signal* TikTok-like app and media pipeline to production readiness with minimum ambiguity.

---


## 0) Scope & Objectives
- Deliver a **vertical short-video experience** on iOS (Swift/SwiftUI) and Android (Kotlin) with autoplay, snap scrolling, long-press scrub preview, and cost-efficient delivery.
- Integrate with an AWS-based media pipeline and expose a `/v1/feed` and `/v1/events` API.
- Meet the non-functional targets below; do **not** change guardrails without explicit instruction.

### Non-functional budgets (must meet)
- **TTFF (time to first frame):** P75 < **1.2 s**, P95 < **2.0 s** (Wi-Fi).
- **CDN hit ratio:** ≥ **97%** for media & storyboard assets.
- **Rebuffer ratio:** < **1%** of playback time.
- **Ranker latency:** online ranker **P99 ≤ 30 ms** or fall back to Trending.

---

## 1) Architecture Snapshot (7 stages)
1) **Capture & Export (client):** Export a single H.264/AAC file + light Recipe JSON. No server-side creative edits.
2) **Direct Upload:** Cognito-auth → API issues **presigned multipart** → client uploads to S3 (idempotent by `video_id`, supports resume).
3) **Inspect & Moderate:** S3 Put → EventBridge → Step Functions → Probe (codec/duration) + Rekognition (visual). Write `inspection.json`.
4) **Transcode & Storyboards:** Step Functions submits **MediaConvert** (CMAF/HLS, 2s GOP, per-title QVBR). **Post-step Lambda** stitches **sprite JPGs** and writes **WebVTT (#xywh)**.
5) **Finalize & Publish:** Write **`media_manifest.json`** (single source of truth). Persist metadata in DynamoDB; warm Redis.
6) **Delivery & Caching:** S3 behind **CloudFront (OAC)**. Versioned paths. Immutable TTLs for sprites/VTT; short-TTL+SWR for manifests.
7) **Playback & Telemetry:** Native players with **PlayerPool(2–3)**; long-press scrub via storyboard provider; batch/debounce telemetry to `/v1/events`.

---

## 2) Hard Guardrails (do not change unless told)
- **CDN & cache keys:** Use **versioned, immutable** paths `/{video_id}/vN/…`. No cookies/headers/query in cache key.
- **Storyboards:** MediaConvert **does not output sprites**. Always run the **Lambda post-step** to produce sprites + WebVTT.
- **Client scrubbing:** Use **WebVTT storyboard**. No on-device frame extraction.
- **Security:** S3 with **Origin Access Control**; optional **signed cookies/URLs** for HLS. Minimal WAF on `/feed` and `/events`.
- **Auth:** **Cognito**. For speed, you may use **Amplify Auth**; otherwise AWS SDK with Keychain/SecureStorage. Keep tokens in secure storage.
- **Tech exclusions:** No React-Native; no heavy cross-fade between items; CC toggle is **out of scope** for now.

---

## 3) Contracts (authoritative)
### 3.1 `media_manifest.json` (client reads exactly one object)
```json
{
  "video_id": "a1",
  "duration_ms": 183000,
  "hls_url": "https://cdn.example.com/vod/a1/v7/hls/master.m3u8",
  "poster_url": "https://cdn.example.com/vod/a1/v7/poster.jpg",
  "thumbnail_vtt_url": "https://cdn.example.com/vod/a1/v7/storyboard/storyboard.vtt",
  "ladder": [
    {"height":240,"bitrate":300000},
    {"height":360,"bitrate":600000},
    {"height":480,"bitrate":1100000},
    {"height":720,"bitrate":2500000}
  ],
  "loudness_lufs": -16.0,
  "created_at": "2025-08-16T12:00:00Z"
}
```
**Rules:** Path is versioned; clients **must honor CDN Cache-Control** and avoid query params.

### 3.2 Feed
**GET** `/v1/feed?cursor=…`
```json
{
  "cursor":"opaque",
  "items":[
    {
      "video_id":"a1",
      "media_manifest_url":"https://cdn.example.com/vod/a1/v7/media_manifest.json",
      "author":{"id":"u123","handle":"@alex"},
      "stats":{"likes":1200,"comments":80,"shares":10}
    }
  ]
}
```

### 3.3 Events (batched & debounced ~200 ms)
**POST** `/v1/events`
```json
{
  "device_id":"ios-abc",
  "session_id":"s-123",
  "ts": 1700000000,
  "events":[
    {"name":"view_start","props":{"video_id":"a1"}},
    {"name":"view_end","props":{"video_id":"a1","dwell_ms":1543,"percent_complete":76}},
    {"name":"tap_play_pause","props":{"playing":true}},
    {"name":"preview_scrub_start"},
    {"name":"preview_scrub_commit","props":{"seconds":42}},
    {"name":"playback_error","props":{"video_id":"a1","code":"E_HLS_PLAY"}},
    {"name":"time_to_first_frame","props":{"ms":740}},
    {"name":"rebuffer","props":{"count":1,"total_ms":340}},
    {"name":"selected_bitrate","props":{"kbps":1200}}
  ]
}
```

### 3.4 Rejection codes (ingest/moderation)
`E_CODEC_UNSUPPORTED`, `E_TOO_LONG`, `E_TOO_LARGE`, `E_NSFW_FLAGGED`, `E_TRANSCODE_FAILED`

---

## 4) Client Implementation Rules
- **Paging:** Vertical pager (iOS: `UIPageViewController` in SwiftUI; Android: ViewPager2). **Snap** feel (no bounce; fast decel).
- **Autoplay:** Start with **audio ON**. Hardware buttons control volume.
- **Tap to Play/Pause** on surface.
- **Long-press to scrub preview:** Pause on press; show overlay frame from **WebVTT sprite**; throttle requests (~8 FPS); on release **seek** and **resume only if it was playing before**.
- **PlayerPool:** Size **2–3**; pre-warm **current + ~5–8 s next**. Also consider previous item when bandwidth allows.
- **Initial bitrate cap:** 400–700 kbps during startup; release after playback stabilizes.
- **Caching:** iOS `URLCache` ≥ **256 MB** disk; Android OkHttp cache ≥ **50 MB**. In-memory **LRU** sprite cache ~**24 images** with **neighbor prefetch**.
- **Lifecycle & errors:** Pause on background/interruption; show **Tap-to-retry** overlay on errors; report `playback_error`.
- **Accessibility:** Provide labels for video surface and scrub overlay.

---

## 5) Media Pipeline Rules
- **Multipart S3 upload** with **Transfer Acceleration** optional; retries are **idempotent** by `video_id`.
- **Step Functions** orchestrates: Inspect → Moderate → Transcode → **Storyboard Lambda** → Publish.
- **MediaConvert:** CMAF HLS, **2 s** segments, aligned GOP, per-title **QVBR ~6–7** by default; gate **720p** by source quality/engagement; write **poster**.
- **Storyboard Lambda:** Packs frames → **sprite JPGs**, writes **WebVTT** with `#xywh`. Outputs go under `/{video_id}/vN/storyboard/`.
- **Publish:** Write `media_manifest.json` and persist to DynamoDB (Videos table).

**DynamoDB keys**
- Primary: `PK=video_id`, `SK=video_id`
- GSI1 (creator timeline): `PK=owner_id`, `SK=-created_at`
- GSI2 (ops/trending): `PK=day_bucket`, `SK=-engagement_score`
- Use **TTL** for ephemeral rows.

---

## 6) CDN & Cache Policy
- **CloudFront + OAC** to S3; **Origin Shield** on; **Brotli/Gzip** for `.vtt`.
- **TTLs:**
  - Sprites/VTT/posters: `Cache-Control: public, max-age=31536000, immutable`
  - Segments: long TTL **7–30 d**, versioned/immutable
  - **Manifests:** **15–60 s** + `stale-while-revalidate, stale-if-error=60`
- **Cache key:** do **not** forward cookies/headers/query. Use versioned paths.

---

## 7) Ranking & Feed
- Online ranker must reply within **30 ms P99**; otherwise **fallback to Trending** for that page.
- Client mixes **10–20% exploration** items per page to keep discovery healthy.

---

## 8) Deliverables & Repo Structure
```
/app/ios/...           # Swift/SwiftUI app + PlayerKit
/app/android/...       # Kotlin app + PlayerKit
/services/api/...      # /v1/feed, /v1/events (REST)
/services/pipeline/... # Step Functions, MediaConvert job, Storyboard Lambda
/iac/...               # CloudFront/S3, DynamoDB, IAM (Terraform or CDK)
/docs/architecture/... # Corrected doc + this Agent Guide
/tests/...             # Unit + UI + integration tests
```

**Environment variables (examples)**
- `API_BASE_URL`, `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `COGNITO_HOSTED_UI_DOMAIN`
- `STORYBOARD_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`

---

## 9) Definition of Done (the checklist the agent must satisfy)
- [ ] `/v1/feed` returns items with **`media_manifest_url`**; clients fetch the manifest and start playback.
- [ ] Clients implement **autoplay w/ audio on**, **tap-to-pause**, **long-press scrub** (resume only-if-was-playing).
- [ ] **PlayerPool(2–3)** with pre-warm current + 5–8 s next; initial bitrate cap 400–700 kbps.
- [ ] **Storyboard provider** parses WebVTT, crops from sprites, LRU cache, neighbor prefetch, ~8 FPS throttle.
- [ ] **Telemetry** batched/debounced to `/v1/events` with events listed above.
- [ ] Media pipeline outputs `/{video_id}/vN/...` including HLS, poster, sprites, WebVTT, and **`media_manifest.json`**.
- [ ] CloudFront cache policy and TTLs configured; CDN hit ratio dashboards exist.
- [ ] DynamoDB tables & GSIs created; idempotency on transcode submitter.
- [ ] Unit tests (VTT parsing, EventBus batching), UI tests (paging, gestures), basic perf test (TTFF).

---

## 10) Tasks for the Assistant (prioritized)
1. **iOS/Android clients:** implement PlayerPool, pager, gestures, storyboard provider, telemetry, lifecycle handling.
2. **API service:** implement `/v1/feed` (serves `media_manifest_url`) and `/v1/events` (batched ingest).
3. **Pipeline IaC:** Step Functions, MediaConvert template, **Storyboard Lambda**, and S3/CloudFront policies.
4. **DynamoDB & Redis:** create tables/GSIs; implement feed queue warmup.
5. **Dashboards:** TTFF, rebuffer, CDN hit ratio, ranker latency.

---

## 11) Out of Scope (do not implement)
- RN/FlashList/Redux, caption toggle, advanced video editing, comments/live streams, complex auth UX beyond Cognito basics.

> Use this guide as the system prompt/context for coding. Prefer concise, strongly typed code; add tests where indicated; adhere to budgets and guardrails above.
