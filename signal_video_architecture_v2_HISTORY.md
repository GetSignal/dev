
# Signal Video Architecture — v2 (Refined)

**Updated for**: 1–5M concurrent viewers, mobile-only (iOS/Android), visuals-only moderation, “For You” ranking must-have, cost-first while preserving great UX.

---

## 1) Goals & Assumptions
- **Throughput**: Design for 5M CCU with ≥97–98% CDN hit ratio to protect origin.
- **Simplicity**: Minimal glue code; heavily managed services.
- **Cost-first**: H.264-only at launch, per-title QVBR, 4-rung ladder, pre-transcode moderation, aggressive CDN caching, Redis feed warming.
- **Moderation**: Visuals only, pre-transcode; escalate when uncertain.
- **Feed**: Two-stage ranking (cheap candidate gen + tiny online ranker) with per-user warm queues.

---

## 2) High-Level Architecture (ASCII)

```
 Mobile Apps (iOS/Android)
  ├─ Auth: Cognito
  ├─ Upload Manager ──(Presigned Multipart)──► S3: raw/
  │                           ▲
  │                    API GW + Lambda: Presign
  │
  ├─ Feed Client ──► API GW + Lambda: Feed Service ──► Redis (ElastiCache): per-user queues
  │                                               └──► DynamoDB: Videos/UserLibrary/FeedCache/EngagementAgg
  │
  ├─ Player (Exo/AVPlayer pool, ABR preload) ◄── CloudFront ◄── S3: vod/packaged/ (HLS/CMAF)
  │
  └─ Event Ingest (impressions, dwell, likes) ──► API GW (HTTP) ─► Kinesis Streams ─►
                                                 ├─ Lambda: Online Aggs ─► Redis Trending
                                                 ├─ Firehose ─► S3 Data Lake (Parquet)
                                                 └─ Lambda: Update EngagementAgg (DynamoDB)

S3: raw/  ──(EventBridge)──► Lambda: Transcode Submitter (idempotent) ─► MediaConvert (H.264 QVBR, 4-rungs)
    │                                                         │
    └─► Lambda: Moderation Orchestrator (Tier A frames → Tier B video) ─► Rekognition
                                                              │
                                                              └─ Verdict → DynamoDB(Videos) & route:
                                                                 - approve: proceed to transcode
                                                                 - reject: mark & stop

MediaConvert ─► S3: vod/packaged/ + thumbnails/ + sprites/ ─► SNS/EventBridge ─► Lambda: Status Updater (Videos) ─► WebSocket push

Batch Recs: Glue/Spark (15–30 min) on S3 lake ─► write candidates to DynamoDB/S3
Online Ranker: SageMaker Serverless **or** Lambda-hosted model (LR/XGBoost)
Feed Service: pull from Redis queue → top-up via ranker → fallback to trending
```
---

## Player choice & PlayerKit wrapper (Callout)

**Decision:** Use **native players** — **ExoPlayer** (Android) and **AVPlayer** (iOS).

**Why:** Best-in-class HLS ABR, hardware decode, broad device coverage, and lower battery/CPU than custom decoders.

**PlayerKit (thin wrapper)**
Unify behavior across platforms and keep feed code player-agnostic.
```ts
interface PlayerKit {
  prepare(hlsUrl: string, opts?: { initialBitrateCapKbps?: number })
  play(); pause(); seek(ms: number)
  on(event: 'firstFrame'|'rebufferStart'|'rebufferEnd'|'bitrateChange'|'ended'|'error', cb: (...args)=>void)
  dispose()
}
```

**Operational policy**
- **Pool:** 2–3 player instances; reuse aggressively.
- **Preload:** fully buffer current clip + **5–8 s** of next clip only.
- **Startup cap:** begin around **400–700 kbps** (360p) then clear cap to allow upswitch.
- **ABR-friendly:** 2 s segments; aligned GOP; loudness-normalized audio.
- **Fallbacks:** if TTFB/TFF > 1.5 s, downshift one rung; if 2 re-buffers in first 5 s, lock ≤540p for session.
- **Telemetry → event ingest:** time_to_first_frame, rebuffer_count/duration, selected_bitrate, watch_time_ms, percent_complete, skips, volume_state, errors.
- **UX:** instant poster; **sprite** previews on scrub; respect silent mode; captions toggle if available.

**Note:** Revisit a custom pipeline only for exotic needs (multi-angle sync, unusual DRM requirements, or transport beyond HLS). Natives + wrapper are sufficient for 1–5M CCU.

---

## 3) Core Data Flows

### A. Upload → Moderation → Transcode → Publish
1. **Client** requests presigned multipart creds (API GW+Lambda). Parts 5–15MB, pause/resume, backoff.
2. S3 `raw/` object create → **EventBridge** fanout:
   - **Moderation Orchestrator (Lambda)**:
     - **Tier A**: sample 1 fps up to 60 frames; Rekognition Image.
     - If near-threshold: **Tier B**: Rekognition Video async; SNS callback.
     - Write `moderation_verdict` to `Videos` (DynamoDB). Approve → emit event.
   - **Transcode Submitter (Lambda)** listens for “approved” → `CreateJob` to **MediaConvert** (idempotent, DLQ).
3. MediaConvert outputs:
   - **HLS/CMAF** with 2s segments; posters; **storyboard sprites**; loudness-normalized AAC.
   - Write to `vod/packaged/` + `thumbnails/`, `sprites/`.
4. **Status Updater (Lambda)** processes job events → set `status=published` in `Videos` and notify clients (WebSocket).

### B. Playback
- Mobile player preloads **current full** + **next 5–8s**; player pool size 2–3.
- CloudFront with long TTL on segments (immutable), short TTL on manifests; Origin Shield on; stale-while-revalidate.

### C. Events → “For You”
- Client sends impressions, dwell, likes, etc. → **Kinesis**.
- Consumers:
  - **Online aggs** to **Redis Trending** (5–60 min windows).
  - **EngagementAgg** DynamoDB for basic counters.
  - **Firehose** → S3 Data Lake (Parquet) for batch features.
- **Candidate Gen (Glue/Spark, 15–30 min):**
  - Co-visitation; creator recency; trending with decay.
  - Write top 1–2k candidates/user to S3 or DynamoDB.
- **Online Ranker (SageMaker Serverless or Lambda w/ XGBoost):**
  - Re-rank candidates using features (recency, dwell priors, fatigue, time-of-day, device, etc.).
- **Feed Service** fills Redis per-user queues with ranked IDs; API returns 10–20 at a time; fallback to trending if low.

---

## 4) Media & Encoding (cost-first, quality preserved)
- **Codec:** H.264 only (launch). AV1/HEVC canaries later for high-traffic devices/videos.
- **Packaging:** HLS/CMAF; segment duration **2s**; keyframe-aligned GOP=2s.
- **Rate control:** **QVBR** level 6–7; per-title analysis.
- **Initial ladder (enable 720p conditionally):**
  - 426×240 @ 250–400 kbps
  - 640×360 @ 400–700 kbps
  - 960×540 @ 800–1100 kbps
  - 1280×720 @ 1400–2000 kbps (gate on source quality & engagement)
- **Audio:** AAC LC 64–96 kbps; **EBU R128** loudness normalization.
- **Artifacts:** poster JPG/PNG; **sprite sheet** (e.g., 10×10 tiles, 1s or 2s cadence).

---

## 5) Caching & CDN
- **CloudFront behaviors:**
  - Segments: immutable names, **TTL 7–30d**, no per-user tokens, vary only on path.
  - Manifests: **TTL 15–60s**; gzip/brotli enabled.
  - **Origin Shield + Regional Edge Cache** ON; **SWR** for manifests.
- **WAF throttles** for basic scraper mitigation.
- **Outcome:** ≥97–98% hit ratio; origin kept <50–75k rps at 5M CCU.

---

## 6) Data Model (DynamoDB)
- **Videos**: `PK=video_id`, `SK=const`, attrs: owner_id, status, moderation_verdict, duration, ladder_profile, poster_path, sprite_path, created_at.
- **UserLibrary**: `PK=user_id`, `SK=created_at#video_id` (optionally bucket SK by day).
- **EngagementAgg**: `PK=video_id`, `SK=window#yyyy-mm-ddThh`, attrs: views, avg_dwell, likes, shares.
- **FeedCache (optional)**: `PK=user_id`, `SK=ts#uuid`, attrs: list<video_id> for warm queues.
- **GSIs** as needed: VideosByUser (`GSI1PK=owner_id`, `GSI1SK=created_at`).

---

## 7) Services & Lambdas (minimal glue)
- **Upload Presigner** (API GW + Lambda): returns multipart creds; validates transform params.
- **Moderation Orchestrator**: frame sampling, Rekognition calls, verdict writeback.
- **Transcode Submitter**: `CreateJob` to MediaConvert; idempotent (by `video_id`), DLQ, metrics.
- **Status Updater**: MediaConvert events → Videos.status; push WebSocket.
- **Event Ingest**: API GW HTTP → Kinesis.
- **Online Aggregator**: Kinesis → Redis Trending + Dynamo EngagementAgg.
- **Candidate Gen**: Glue/Spark job 15–30 min.
- **Online Ranker**: SageMaker Serverless or Lambda (model artifact in S3); P99 < 30 ms goal.
- **Feed Service**: top-up Redis queues, serve pages, fallback to trending.

_All async edges wired with retries, idempotency keys, and DLQs; CloudWatch alarms everywhere._

---

## 8) Mobile App Policies
- **Initial bitrate**: 360p unless strong Wi‑Fi signal and >8 Mbps probe.
- **Preload**: full current + 5–8s next; posters immediately; sprites on scrub.
- **Player pool**: 2–3 instances; aggressive reuse.
- **View definition**: dwell ≥2s **or** ≥50% completion for “view” events.

---

## 9) Observability & SLOs
- **SLIs**: time-to-first-frame, rebuffer ratio, average bitrate, CDN hit ratio, Feed API P99, ranker P99.
- **Targets**: TFF < 800 ms on Wi‑Fi; rebuffer < 2%; CDN hit ≥ 97%; Feed API P99 < 120 ms; ranker P99 < 30 ms.
- **Dashboards**: CloudWatch + embedded RUM in app. Alarm on deltas (e.g., hit ratio drop >1% in 5 min).

---

## 10) Cost Controls
- Single codec (H.264) and **per-title QVBR**.
- **4-rung ladder**, enable 720p selectively.
- **Pre-transcode moderation** to avoid wasted jobs.
- Expire **mezzanines** early; move cold packaged to IA.
- **Redis queues** to avoid live heavy-ranking.
- **High CDN hit** via immutable segments, long TTLs, Origin Shield.

---

## 11) API Endpoints (illustrative)
- `POST /upload/presign` → { uploadId, parts[] }
- `GET /feed` → { items: [video_id…], nextCursor }
- `POST /event` → body: { type, video_id, dwell_ms, ... }
- WebSocket channel for `video_status` updates.

---

## 12) Phase‑2 Toggles (when ready)
- AV1 for Android-heavy cohorts on high-traffic videos.
- LL‑HLS if near-live is needed.
- Human-in-the-loop moderation for gray cases.
- Feature store (Dynamo/Redis) for richer ranker features.
- Geo-aware ladders and device-aware codec policies.

---

## 13) Pseudocode Snippets

**Transcode Submitter (idempotent):**
```python
def handler(event):
    vid = event["video_id"]
    if videos_table.get(vid).get("transcode_job_id"): return "exists"
    job = mediaconvert.create_job(settings_for(vid))
    videos_table.update(vid, {"transcode_job_id": job.id, "status": "processing"})
```

**Moderation Orchestrator (Tier A/B):**
```python
frames = sample_frames(s3_uri, fps=1, max_frames=60)
labels = [rekog.detect(img) for img in frames]
if near_threshold(labels): start_rekognition_video(s3_uri)  # async
else: approve_or_reject(labels)
```

**Feed Top‑Up:**
```python
ids = redis.lrange(f"user:{uid}:queue", 0, 49)
if len(ids) < 20:
    candidates = candidates_store.get(uid) or trending.now(1000)
    scored = ranker.score(uid, candidates)  # fast model
    redis.rpush(f"user:{uid}:queue", *take(scored, 200))
return take(ids, 20)
```

---

### That’s it
This v2 folds in the minimal glue services, pre-transcode moderation, cost‑optimized encoding, and a practical “For You” that scales to 1–5M CCU without blowing up origin or the bill.
