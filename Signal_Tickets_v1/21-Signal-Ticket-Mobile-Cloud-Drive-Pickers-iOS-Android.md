
# Ticket 21 — Mobile Cloud/Drive Pickers (iOS & Android)
**Date:** 2025-08-18  
**Priority:** P2

## TASK
Enable file selection from cloud providers using **native pickers** (no third‑party SDKs). Feed selections into the same Bulk Uploader.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as authority. 
Focus on **mobile uploads** (iOS & Android). Keep within existing security posture (Cognito), S3 multipart, pipeline publish contract (`media_manifest.json`). 
No TikTok or third‑party scraping. Follow existing telemetry batching and versioned CDN paths.

## iOS
- Use **UIDocumentPickerViewController** (mode: `.open`) allowing multiple selection; allow providers (Files/iCloud Drive/Google Drive via Files).
- Securely bookmark file URLs; copy to app sandbox if required; then upload via BulkUploader.

## Android
- Use **Storage Access Framework** (`ACTION_OPEN_DOCUMENT`, `EXTRA_ALLOW_MULTIPLE`) with persisted URI permissions.
- Stream content via `ContentResolver.openInputStream()` into multipart uploader (no full buffering).

## CONSTRAINTS
- Respect file size caps and supported mime types (mp4, mov, hevc, h264).
- Show per‑item failures with retry; maintain queue order.
- Telemetry: `picker_open`, `picker_select(count)`.

## DELIVERABLES
- iOS: `/app/ios/Upload/CloudPicker.swift`, integration into queue.
- Android: `/app/android/.../upload/CloudPicker.kt`, integration into queue.
- Tests: instrumentation tests ensuring URIs resolve and stream properly; unit tests for stream chunking adapters.
- Output: diff‑ready code + rationale.

## ACCEPTANCE
- User can pick from Files/Drive providers; items enter the same queue and upload successfully.
