
# Ticket 2 — iOS PlayerPool + autoplay & gestures
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Implement reusable PlayerPool and gestures: autoplay audio ON, tap-to-pause/resume. Ensure lifecycle safety.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Smooth attach/detach across recycled pages with zero-cost switching and correct lifecycle behavior.

## CONSTRAINTS
- **PlayerPool(2–3)**; prewarm current + ~5–8 s next.
- Autoplay audio ON; device buttons control volume.
- Pause on background/interruption; resume only if appropriate.
- No audio crossfades.

## DELIVERABLES
- Files: `/app/ios/Player/PlayerPool.swift`, `/app/ios/Player/VideoContentViewController.swift`
- Tests: unit tests for pool acquire/release and lifecycle
- Output: diff-ready code + rationale

## ACCEPTANCE
- Current page autoplays with audio ON.
- Pool reuses players; no leaks.
- Background pause / foreground resume works.
- Unit tests pass.
