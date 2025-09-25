# Ticket 7 — Feed API client & manifest consumption (iOS + Android)
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Implement `/v1/feed` client, fetch `media_manifest_url`, and configure playback from `media_manifest.json`.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Start playback within TTFF budget using initial bitrate cap and prefetch of next item.

## CONSTRAINTS
- Use manifest fields (`hls_url`, `poster_url`, `thumbnail_vtt_url`, `duration_ms`, ladder, loudness).
- Initial bitrate cap 400–700 kbps; prefetch current + ~5–8 s next.
- Safe retries/backoff for GETs.

## DELIVERABLES
- Files: `/app/*/Networking/APIClient.*`, `/app/*/Feed/FeedViewModel.*`
- Tests: manifest parsing + prefetch behavior
- Output: diff-ready code + rationale

## ACCEPTANCE
- `/v1/feed` → `media_manifest_url` → playback starts (audio ON).
- Meets TTFF budget on sample media.
- Tests pass.

---
**Update 2025-09-08: Extend Feed item schema (client consumption; manifest unchanged)**

### `/v1/feed` Response — Item Additions
Each item MAY include the following **optional** fields:
- `caption : string` — human-readable caption text.
- `audio : object` — audio label metadata:
  - `title : string?`
  - `artist : string?`
  - `is_original : boolean?`

> `media_manifest.json` stays focused on playback (HLS URL, sprites, VTT, duration, ladder, loudness). No changes here.

### Client Handling
- If `caption` missing/empty → hide caption overlay.
- If `audio` missing:
  - If `author.handle` present → render fallback “original sound — @author”.
  - Else → hide audio label overlay.
- No extra network calls; parse within existing feed pipeline.

### OS Baselines (for client work in this ticket)
- iOS **16+**; Android **minSdk 26** / **targetSdk 35**.
---

---
**Finalized 2025-09-08: Client Contract Affirmation**
- `/v1/feed.items[].caption` ≤ **2,200 chars** (UTF-8). Render with two-line truncation.
- `/v1/feed.items[].audio` keys: **title?**, **artist?**, **is_original?**; fallback rule “original sound — @author” when needed.
- Acceptance: contract tests ensure optionality and fallback behavior.
---
