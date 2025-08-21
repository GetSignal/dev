
# Ticket 8 — `/v1/events` service stub + validations
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Create REST endpoint that accepts batched telemetry and validates schema.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Accept, validate, queue events for downstream (Kinesis/S3/Redis).

## CONSTRAINTS
- Envelope + event names as specified.
- 400 on invalid payloads; basic rate limiting.
- No PII; redact oversize fields.

## DELIVERABLES
- Files: `/services/api/events/handlers.*`, `/services/api/events/schema.*`
- Tests: schema validation + rate limiting
- Output: diff-ready code + rationale

## ACCEPTANCE
- Accepts valid batches; rejects invalid clearly.
- Tests pass.
