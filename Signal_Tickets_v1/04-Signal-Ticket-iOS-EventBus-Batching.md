
# Ticket 4 — iOS EventBus (batch + debounce) & required events
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Create an EventBus that batches and debounces telemetry (~200 ms) and posts to `/v1/events`.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Durable, low-chatter telemetry for FYP and performance dashboards.

## CONSTRAINTS
- Envelope: `{device_id, session_id, ts, events:[...]}`
- Events: `view_start`, `view_end(dwell_ms, percent_complete)`, `tap_play_pause`, `preview_scrub_start/commit`, `playback_error`, `time_to_first_frame`, `rebuffer`, `selected_bitrate`
- Retry with backoff

## DELIVERABLES
- Files: `/app/ios/Telemetry/EventBus.swift`, `/app/ios/Telemetry/HttpEventBus.swift`
- Tests: batching/debouncing and retry
- Output: diff-ready code + rationale

## ACCEPTANCE
- Batches post correctly; debouncing merges bursts.
- Retries transient failures.
- Tests pass.
