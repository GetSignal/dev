# Signal — Minimal Payload Additions & Baselines (v1)

This note captures the **lowest-cost telemetry that yields high product/ops value**, plus the **OS baselines** and the **tickets to update**. It assumes existing core playback events already in scope (`view_start`, `view_end`, `time_to_first_frame`, `rebuffer`, `playback_error`, `tap_play_pause`, `preview_scrub_*`, `selected_bitrate`).

---

## OS Baselines (Launch)
- **iOS:** 16.0+  
- **Android:** minSdk **26** (Android 8.0), targetSdk **35**

> Rationale: modern media APIs, lifecycle behavior, SwiftUI/ExoPlayer stability, and current store requirements.

---

## Minimal Event Additions (low payload, high value)

All events use the existing batch/debounce envelope (device/session in context). **No PII**; compact props only.

1) **`feed_request`** — fired when fetching a page of feed items  
   - **props:** `cursor?` (string or null)

2) **`feed_response`** — fired on response for the same request  
   - **props:** `cursor?`, `item_count` (int), `latency_ms` (int), `source` (`online|trending|cached`)

3) **`first_paint`** — first frame of the feed UI rendered (separate from player TTFF)  
   - **props:** `ms` (int)

4) **`tap_to_retry`** — user taps error overlay to retry playback/fetch  
   - **props:** none

5) **`share_open`** — share sheet opened  
   - **props:** `target` (`system|copy_link|...`)

6) **`share_complete`** — user completes a share action  
   - **props:** `target` (`system|copy_link|...`)

**Client behavior:** batch with ~200 ms debounce; flush on background/terminate; retry with backoff+jitter.

---

## Tickets that MUST be updated

### A) Add **OS baselines** (iOS 16+; Android minSdk 26 / targetSdk 35)
- **05** — Android Vertical Pager
- **06** — Android PlayerKit & Storyboard Provider
- **11** — Perf & Observability Pass
- **14** — Clients UI: Like/Follow/Flags
- **17** — Bookmarks APIs & Flagged UI (client portions)
- **18** — Share + Deep Links + Telemetry
- **20** — Mobile Bulk Uploader (iOS & Android)
- **21** — Mobile Cloud Drive Pickers (iOS & Android)
- **23** — Ingest Status Dashboard — Mobile Views

> Not required for server‑only tickets: **12, 13, 15, 16, 19, 22**.

### B) Instrument the **new events** (schema + emit points)
- **04** — iOS EventBus (add event names to the envelope + tests)
- **08** — Events API Stub/Ingest (accept new event types & validate props)
- **07** — Clients → Feed API (emit `feed_request`/`feed_response` around network call)
- **11** — Perf & Observability Pass (record `first_paint`, keep TTFF separate)
- **18** — Share + Deep Links + Telemetry (`share_open`/`share_complete`)
- **01** — iOS Vertical Pager (emit `tap_to_retry` on error overlay)
- **05** — Android Vertical Pager (emit `tap_to_retry` on error overlay)

---

## Non‑Goals (for launch)
- **No DRM / signed HLS** at launch (CloudFront+S3 with OAC; versioned immutable assets).
- No comments/messaging; social graph only where already scoped (follow/like).

---

## Validation (success signals)
- **TTFF P75** stable; **feed latency** distributions observable (`feed_*` events).
- **Crash‑free sessions** ≥ store thresholds; **rebuffer rate** unchanged after event adds.
- **Share funnel** observable without feature bloat (open→complete rate).

