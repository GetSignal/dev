# Signal Video Architecture — v2 (Refined) ✅ Corrected & Final
**Date:** 2025-08-16
**Scale target:** 1–5M concurrent viewers (first 6 months)

This is the production-ready 7‑stage lifecycle for Signal, corrected to integrate fully with the native iOS/Android clients and the AWS stack.


## Goals
- <1.2s time‑to‑first‑frame (TTFF) on good networks
- ≥97% CDN hit ratio via immutable, versioned assets
- Cost‑aware client (no on‑device frame extraction; use storyboard sprites)

---
## 1) Capture & Export (Client)
Export a single H.264/AAC file + lightweight Recipe JSON. Emit `upload_intent(...)`. Native stacks only (SwiftUI+UIPageViewController; ViewPager2).

## 2) Direct Upload (Ingest)
Cognito → API returns presigned **multipart** URLs → client uploads to S3 (Transfer Accel optional). Idempotent by `video_id`. Return an **ingest receipt** (video_id, S3 keys, expected states).

## 3) Inspect & Moderate (Visual‑only)
S3 Put → EventBridge → Step Functions.
- Probe (codec/container/duration)
- Rekognition visual checks
- Write `inspection.json`
Reject with codes: `E_CODEC_UNSUPPORTED`, `E_NSFW_FLAGGED`, `E_TOO_LONG`, etc.

## 4) Transcode & Storyboards
Step Functions submits **MediaConvert** (CMAF/HLS, 2s segments, aligned GOP, per‑title QVBR).
- Ladder guidance: 240p~300kbps, 360p~600, 480p~1.1Mbps, 720p~2–3Mbps (gate 720p by quality/engagement)
- **Poster** image for cold start

**Correction:** MediaConvert emits frame captures; a **Lambda post‑step** packs **sprite JPGs** and emits **WebVTT** cues with `sprite.jpg#xywh=x,y,w,h`.

All outputs versioned under `/{{video_id}}/v{{N}}/…`.

## 5) Finalize & Publish
Write **`media_manifest.json`** (single source of truth for clients):
- `hls_url`, `poster_url`, `thumbnail_vtt_url`, `duration_ms`, ladder, loudness
Persist rows:
- DynamoDB (Videos): `PK=video_id`, `SK=video_id`
  - GSI1 (creator timeline): `PK=owner_id`, `SK=-created_at`
  - GSI2 (ops/trending): `PK=day_bucket`, `SK=-engagement_score`
- Redis for hot feed queues; S3/Lake for analytics

## 6) Delivery & Caching (S3 + CloudFront)
- OAC to S3; no cookies/headers/query in cache key
- Brotli/Gzip for VTT; Origin Shield enabled
- TTLs: sprites/VTT/posters = **1y immutable** (versioned); segments = **7–30d** immutable; manifests = **15–60s + stale‑while‑revalidate**
- (Optional) Signed cookies/URLs for HLS to deter hotlinking

## 7) Playback & Telemetry (Clients)
- **PlayerPool(2–3)**; snap paging; **autoplay audio ON**
- **Initial bitrate cap** (~400–700kbps), then full ABR
- **Long‑press scrub** via WebVTT storyboard provider (LRU sprites ~24; neighbor prefetch; ~8fps throttle)
- **Tap to pause/resume**; **Tap‑to‑retry** on error
- **Adaptive prefetch**: current + ~5–8s next (reduce when bandwidth/thermal constrained)

**Telemetry**
Batch & debounce (~200ms) to `/v1/events`:
`view_start`, `view_end(dwell_ms, percent_complete)`, `tap_play_pause`, `preview_scrub_start/commit`, `playback_error`, plus `ttff`, `rebuffer_count/duration`, `selected_bitrate`.
Server: API → Kinesis → S3 (offline) + Redis (online features).

---
## Feed & Ranking
- `/v1/feed` returns items with `media_manifest_url`.
- Online ranker P99 ≤ 30ms; **Trending** fallback if budget exceeded.
- Client exploration rate 10–20% to keep discovery healthy.

---
## Observability & SLOs
- Dashboards: TTFF, startup bitrate, rebuffer %, CDN hit, MediaConvert latency, moderation rates, feed latency
- SLOs: TTFF P75<1.2s/P95<2.0s, CDN≥97%, ranker P99≤30ms

---
## Cost Controls
- Versioned immutable assets, long TTLs
- Short‑lived mezzanines, cold packaged → S3 IA
- QVBR ~6–7 default; gate high rungs by source/engagement
- Client caches sprites/VTT and batches events

---
## API Contracts (excerpt)
**GET** `/v1/feed?cursor=…` → items with `media_manifest_url`  
**POST** `/v1/events` → batch of telemetry

---
## Implementation Notes (Signal Clients)
- Use `media_manifest.json` for one‑shot setup; rely on storyboard provider for scrubbing
- Maintain **resume‑only‑if‑was‑playing** behavior for long‑press
- Preload next & previous when conditions allow
