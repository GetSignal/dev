
# Ticket 9 — Pipeline: Storyboard Lambda & MediaConvert template
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Implement Step Functions stage for MediaConvert (CMAF/HLS, 2 s GOP, QVBR) and a Lambda post-step that builds sprite JPGs and WebVTT with `#xywh`. Version outputs under `/{video_id}/vN/...`.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Deterministic, cache-friendly outputs including `media_manifest.json`.

## CONSTRAINTS
- Gate 720p by source quality/engagement.
- Idempotency by video_id on submitter; safe retries.

## DELIVERABLES
- Files: `/services/pipeline/step_functions/*`, `/services/pipeline/mediaconvert/job_template.*`, `/services/pipeline/storyboard_lambda/*`
- Tests: unit test for VTT builder; integration test plan
- Output: diff-ready code + rationale

## ACCEPTANCE
- Produces HLS, poster, sprites, WebVTT, and manifest in versioned paths.
- Idempotent across retries.
