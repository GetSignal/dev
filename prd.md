# Signal — Product Requirements Document (PRD)
**Date:** 2025-08-16  
**Owner:** PM/Eng Lead (Signal)  
**Doc status:** v1 (MVP scope)  
**Related docs:** Agent Guide, Agent Prompt, Ticket Pack

---

## 1. Overview
**Signal** is a TikTok-style, short-video app targeting rapid, smooth playback and a “For You” (FYP) experience. MVP launches on **iOS (Swift/SwiftUI)** and **Android (Kotlin)** with a native vertical feed, autoplay (audio on), long-press scrub preview, and a cost-efficient AWS media pipeline.

- **Scale goal (first 6 months):** **1–5M concurrent viewers**.
- **Cost posture:** Optimize costs while preserving great UX (high CDN hit, efficient transcode ladder, caching).  
- **Moderation scope:** **Visual-only** (image/frame checks).  
- **Security:** Light—S3+CloudFront OAC, optional signed cookies for HLS.  
- **Auth:** Amazon **Cognito** (Amplify Auth permitted).

---

## 2. Goals & Non-Goals
### 2.1 Goals (MVP)
- Deliver a vertical, snap-scrolling feed with **video autoplay ON**, **autoplay audio ON** and **tap to play/pause**.
- Provide **long-press scrub** with **WebVTT storyboard + sprites** (no on-device frame extraction).
- Surface a **ranked For You feed** with consistent latency and an exploration mix.
- Robust **upload → inspect → transcode → publish** pipeline; single **`media_manifest.json`** for clients.
- Telemetry for ranking and quality: **batched** events, low chatter, actionable dashboards.

### 2.2 Non-Goals (MVP)
- Captions/CC toggle, comments/live streaming, messaging/DMs, advanced editing, complex security policies, heavy social graphs.  
- Region-specific bandwidth optimization beyond ABR basics (can come later).

---

## 3. Target Users & Personas
- **Creators (Casual/Pro):** Quick post flow, reliable upload, clear moderation outcomes.  
- **Viewers (Mainstream, 16–35):** Seamless FYP feed; minimal stalls; intuitive gestures.  
- **Ops/PM/Data:** Reliable event ingest; simple dashboards (TTFF, rebuffer, CDN hit, ranker latency).

---

## 4. User Stories
- As a viewer, I **open the app** and see a video **playing instantly with sound**.  
- As a viewer, I **swipe** to the next video and it **starts immediately** without jank.  
- As a viewer, I **long-press** to preview any point and **scrub**; on release it **seeks and resumes** if it was playing.  
- As a creator, I **upload** a video; if rejected, I get a **clear reason** (e.g., format, NSFW flag).  
- As PM/ops, I view **dashboards** to confirm experience health (TTFF, rebuffer, hit ratio).

---

## 5. Scope (MVP vs Later)
**MVP**
- iOS/Android native clients; feed, playback, gestures; EventBus telemetry.
- Backend REST: `/v1/feed`, `/v1/events`.
- Pipeline: S3 direct multipart upload → Inspect/Moderate (visual) → MediaConvert (CMAF/HLS, 2s) → **Lambda storyboard post-step** → **`media_manifest.json`**.
- CDN: CloudFront+OAC, **versioned immutable paths**, disciplined TTLs.
- Ranking: online FYP with Trending fallback, client exploration 10–20%/page.

**Later**
- Comments/engagement UI, creator tooling, localization, advanced moderation, server-side personalization features, push notifications, A/B experiments, offline downloads.

---

## 6. Functional Requirements
## 6.0 Delivery & Caching (alignment note)
- **Manifests:** **15–60 s** + `stale-while-revalidate, stale-if-error=60` (explicit).  
  *(Sprites/VTT/posters: 1y immutable; segments: 7–30d immutable; no cookies/headers/query in cache key.)*
  
### 6.1 Feed & Playback
- Vertical **snap** paging; **PlayerPool(2–3)** reused; **prefetch current + ~5–8 s next** (adaptive).
- **Autoplay audio ON**; device volume controls; **tap** to play/pause.
- **Long-press scrub** uses **WebVTT storyboard + sprites**; throttled (~8 FPS), LRU (~24 images), neighbor prefetch.
- **Error UX**: tap-to-retry overlay; no app crash on HLS errors.

### 6.2 Upload & Pipeline
- **Cognito auth** → API returns **presigned multipart** → S3 upload (idempotent by `video_id`).
- **Inspect & moderate**: codec/container/duration probe; **Rekognition** visuals; write `inspection.json`.
- **Transcode**: MediaConvert **CMAF/HLS**, **2s segments**, **aligned GOP**, **per-title QVBR** (default level ~6–7). Ladder: 240p (~300 kbps), 360p (~600), 480p (~1.1 Mbps), 720p (~2–3 Mbps; gated).
- **Storyboard**: Lambda packs sprite JPGs; writes WebVTT cues with `#xywh`.
- **Publish**: one **`media_manifest.json`** with `hls_url`, `poster_url`, `thumbnail_vtt_url`, `duration_ms`, ladder, loudness.

### 6.3 Delivery & Caching
- CloudFront + **OAC** to S3; **Origin Shield** enabled; Brotli/Gzip for `.vtt`.
- **Cache policy**: no cookies/headers/query in cache key.  
- **TTLs**: Sprites/VTT/posters **1y immutable**; segments **7–30d immutable**; manifests **15–60s + stale-while-revalidate (+ stale-if-error=60)**.
- Optional signed cookies/URLs for HLS.

### 6.4 Ranking & Data
- `/v1/feed` returns `media_manifest_url` per item; ranker P99 ≤ **30 ms**, fallback to Trending when exceeded.
- Client exploration rate **10–20%** mixed into pages.
- Telemetry via `/v1/events` (**batched & debounced ~200 ms**): `view_start`, `view_end(dwell_ms, percent_complete)`, `tap_play_pause`, `preview_scrub_start/commit`, `time_to_first_frame`, `rebuffer`, `selected_bitrate`, `playback_error`.

### 6.5 Data Model & Storage
- **DynamoDB (Videos)**: `PK=video_id`; **GSI1** `owner_id/-created_at`; **GSI2** `day_bucket/-engagement_score`.
- **Redis**: hot feed queues; **S3** data lake for analytics.

---

## 7. Non-Functional Requirements (NFRs)
- **Performance**: **TTFF** P75 < **1.2s**, P95 < **2.0s** (Wi-Fi); scroll jank: none; in-memory sprite LRU ≤ 24.
- **Quality**: **Rebuffer ratio** < **1%** of playback time.
- **Availability**: APIs (feed/events) **99.9%** monthly; pipeline durable with retries.
- **Scalability**: 1–5M CCU; maintain **≥97% CDN hit**.
- **Privacy/Security**: no PII in events; minimal auth scope; S3 private via OAC; CORS restricted.
- **Cost**: high cacheability; QVBR, ladder gating; storage tiering; batched telemetry.

---

## 8. KPIs & Success Metrics
- **Experience**: TTFF P95, Rebuffer %, crash-free sessions, median watch time, completion rate.  
- **Cost**: egress per session, transcode minutes per hour uploaded, CDN hit ratio.  
- **Engagement**: sessions/day, avg session length, pct of exploration items watched.  
- **Pipeline**: upload→publish P95, moderation reject rate, MediaConvert queue latency.

---

## 9. Acceptance Criteria (Launch Gate)
- Clients start playback from **`media_manifest.json`** with **audio ON**; long-press scrub works and **resumes only if previously playing**.  
- Measured TTFF within budget on reference sample; **rebuffer < 1%**.  
- CDN headers/paths/TTLs comply; hit ratio **≥97%** in staging canary.  
- `/v1/feed` and `/v1/events` live; telemetry arrives batched; dashboards populated.  
- Pipeline produces HLS, poster, sprites, WebVTT, **`media_manifest.json`** at versioned paths.  
- Ranker meets P99 ≤ 30 ms or consistently falls back to Trending without user impact.  
- Basic accessibility labels present (video surface, scrub overlay).

---

## 10. Rollout Plan
1. **Internal alpha** with synthetic media; measure TTFF/rebuffer; fix hot spots.  
2. **Regional beta** (limited creator cohort); validate pipeline throughput & moderation.  
3. **Scale-up** toggling exploration % and ladder gates; enable Origin Shield if not already.  
4. **General availability** with dashboards and alerts.

---

## 11. Risks & Mitigations
- **CDN miss / cache drift** → Versioned immutable paths; strict cache keys; manifests short TTL + SWR.  
- **Ranker latency spikes** → Hard 30 ms budget + **Trending fallback**; client exploration ensures diversity.  
- **Sprite/VTT mismatch** → Single publish step emits `media_manifest.json`; integration tests for cue ranges.  
- **Mobile thermal/network limits** → Adaptive prefetch; startup bitrate cap; pause background tasks.  
- **Cost overrun** → QVBR defaults; 720p gating; aggressive TTLs; batched telemetry.

---

## 12. Dependencies
- AWS: Cognito, S3, CloudFront, MediaConvert, EventBridge/Step Functions, Rekognition, DynamoDB, (optionally) Kinesis/Redis.  
- Mobile: AVPlayer/ExoPlayer, URLCache/OkHttp.  
- CI/CD: GitHub Actions or equivalent; Makefile.

---

## 13. Out-of-Scope (MVP)
- Comments/live/DMs, monetization, heavy moderation (audio/text), full-blown social graph, creator analytics suite, CC toggle.

---

## 14. Open Questions
- Do we require **signed cookies** for HLS at MVP, or post-GA?  
- What initial **exploration rate** within 10–20% is best for cold start?  
- Is **720p gating** tied to source upload quality only, or also engagement thresholds?

---

## 15. Appendix (References)
- Agent Guide (Production Build Spec) — authoritative engineering constraints  
- Agent Prompt(s) — system wrapper for AI coding assistant  
- Ticket Pack — execution sequence for agents/humans
