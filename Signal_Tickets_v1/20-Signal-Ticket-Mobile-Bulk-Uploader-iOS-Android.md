
# Ticket 20 — Mobile Bulk Uploader (iOS & Android)
**Date:** 2025-08-18  
**Priority:** P1

## TASK
Implement a multi-select, resumable **S3 multipart** uploader on iOS (Swift) and Android (Kotlin) with background transfers, concurrency control, and robust retry.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as authority. 
Focus on **mobile uploads** (iOS & Android). Keep within existing security posture (Cognito), S3 multipart, pipeline publish contract (`media_manifest.json`). 
No TikTok or third‑party scraping. Follow existing telemetry batching and versioned CDN paths.

## BEHAVIOR
- Multi-select assets from camera roll/library; queue items.
- Each item uploads via **multipart** (part size 5–15 MB; 4–8 concurrent parts; exponential backoff).
- Background handling: continue uploads when app is backgrounded (use BGTask/URLSession background on iOS; WorkManager/ForegroundService on Android).
- Compute **SHA‑256** and collect basic probe (duration, resolution, est bitrate) client‑side for **preflight** (see Ticket 22).
- On completion emit an **upload complete** event and call `/v1/upload/sessions/:id/complete`.

## CONSTRAINTS
- Auth: Cognito; obtain **pre-signed URLs** via `/v1/upload/sessions` (Ticket 22).
- Memory safety: stream file parts from disk (no full in‑memory reads).
- Failures: part retries with backoff; resume after app relaunch.
- Telemetry: `upload_start`, `upload_part_retry`, `upload_complete`, `upload_failed` (batched via EventBus).

## DELIVERABLES
- iOS: `/app/ios/Upload/BulkUploader.swift`, `/app/ios/Upload/UploadQueueView.swift` (progress UI), background session plumbing.
- Android: `/app/android/.../upload/BulkUploader.kt`, `/app/android/.../upload/UploadQueueActivity.kt`, WorkManager/Service.
- Tests: unit tests for part sizing and retry logic; UI smoke test for multi-select and progress.
- Output: diff‑ready code + short rationale.

## ACCEPTANCE
- Select 10 videos → all queued; uploads survive background/relauch; parts retry and finish.
- Server receives `complete` and proceeds to pipeline. 
- No OOMs; progress UI responsive.
