
# Ticket 23 — Ingest Status Dashboard (mobile views + minimal server)
**Date:** 2025-08-18  
**Priority:** P2

## TASK
Expose upload/pipeline **status** to creators on mobile: `queued → inspecting → transcoding → publishing → live` with errors and retry guidance.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as authority. 
Focus on **mobile uploads** (iOS & Android). Keep within existing security posture (Cognito), S3 multipart, pipeline publish contract (`media_manifest.json`). 
No TikTok or third‑party scraping. Follow existing telemetry batching and versioned CDN paths.

## SERVER
- **GET** `/v1/upload/status?cursor=...` → paged recent uploads with `{ video_id, filename, created_at, state, progress?, error? }`.
- Optional push: SSE/WebSocket for state changes (later). For now, poll every 10–20 s on this screen.

## CLIENT
- iOS: `/app/ios/Upload/StatusListView.swift` with per‑item progress, error chips, retry action (re‑enqueue from session if needed).
- Android: `/app/android/.../upload/StatusListActivity.kt` with same design.
- Link from profile and from upload queue screen.

## CONSTRAINTS
- States driven by pipeline events (EventBridge/Step Functions) written to a Status table or stream; avoid heavy polling.
- Telemetry: `status_open`, `status_poll(count)`, `status_retry(video_id)`.

## DELIVERABLES
- Server: `/services/upload/status/*` data access and read model (DynamoDB or Redis sorted set).
- Clients: list UI + view model; navigation hooks.
- Tests: unit tests for state serialization; UI smoke tests.

## ACCEPTANCE
- Newly uploaded items appear with `queued` and progress to `live` after publish.
- Failures show actionable error text and the retry button works when appropriate.
