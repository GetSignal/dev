
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
