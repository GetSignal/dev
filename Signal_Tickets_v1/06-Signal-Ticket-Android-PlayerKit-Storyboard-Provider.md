
# Ticket 6 — Android PlayerKit + storyboard provider (WebVTT sprites) & long-press scrub
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Implement PlayerPool reuse and long-press scrub with WebVTT sprites, caching, and throttling.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Parity with iOS for preview scrubbing and resume behavior.

## CONSTRAINTS
- ExoPlayer; PlayerPool(2–3).
- Parse WebVTT `#xywh`; crop from sprite.
- LRU (~24) + neighbor prefetch; ~8 FPS throttle.
- OkHttp cache ≥ 50 MB; honor Cache-Control.

## DELIVERABLES
- Files: `/app/android/.../player/PlayerPool.kt`, `/app/android/.../player/VttStoryboardProvider.kt`
- Tests: VTT parsing + LRU eviction
- Output: diff-ready code + rationale

## ACCEPTANCE
- Long-press shows thumbnails and seeks on release; resumes only if previously playing.
- Caching + throttle verified.
- Tests pass.
