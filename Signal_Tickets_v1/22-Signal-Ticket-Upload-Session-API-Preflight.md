
# Ticket 22 — Upload Session API & Preflight
**Date:** 2025-08-18  
**Priority:** P1

## TASK
Create `/v1/upload/sessions` for initiating multipart uploads, issuing **pre-signed part URLs**, receiving **preflight** metadata, and finalizing uploads.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as authority. 
Focus on **mobile uploads** (iOS & Android). Keep within existing security posture (Cognito), S3 multipart, pipeline publish contract (`media_manifest.json`). 
No TikTok or third‑party scraping. Follow existing telemetry batching and versioned CDN paths.

## ENDPOINTS
- **POST** `/v1/upload/sessions` → returns `session_id`, `video_id`, `s3_key`, `part_size`, and a short‑lived signer for parts (or batched pre‑signed URLs).
- **PUT** `/v1/upload/sessions/:id/parts` → body: `part_number`, `content_length`, (optional) `sha256`. Returns pre‑signed PUT URL.
- **POST** `/v1/upload/sessions/:id/preflight` → `{ duration_ms, width, height, bitrate_est, sha256 }`.
- **POST** `/v1/upload/sessions/:id/complete` → finalizes multipart; enqueues **inspect/moderate → transcode → publish** job.
- **DELETE** `/v1/upload/sessions/:id` → abort.

## CONSTRAINTS
- Idempotent by `(actor_user_id, sha256)`; return existing `video_id` if duplicate.
- Enforce mime whitelist; size limits; rate limits; server‑side checksum validation optional.
- Security: narrow‑scoped presigns; expiration ≤ 15 min; S3 OAC still enforced for downstream delivery.

## DELIVERABLES
- Server: `/services/upload/api/*`, `/services/upload/signer/*`, queue submitter.
- IaC: permissions for `s3:CreateMultipartUpload`, `UploadPart`, `CompleteMultipartUpload` on ingest bucket path.
- Tests: unit tests for idempotency and signer TTL; integration test plan with sample files.
- Output: diff‑ready code + rationale.

## ACCEPTANCE
- Mobile clients can acquire sessions, upload parts, complete, and trigger the pipeline.
- Duplicate file (same sha256) returns the same `video_id` (no duplicate ingest).
