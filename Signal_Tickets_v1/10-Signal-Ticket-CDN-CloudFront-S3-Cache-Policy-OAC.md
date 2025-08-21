# Ticket 10 — CloudFront/S3 cache policy & OAC (patched)
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Provision CloudFront with OAC to S3, versioned paths, and correct TTLs/cache-key behavior.

## CONTEXT
Use “Signal — Agent Guide (Production Build Spec)” as authority. This ticket **adds** the explicit `stale-if-error=60` directive for manifest responses.

## GOAL
High hit ratio (≥97%) and safe rollouts via immutable versioned assets.

## CONSTRAINTS
- **Do not** forward cookies/headers/query in cache key.
- TTLs:
  - Sprites/VTT/posters: **1y immutable**
  - Segments: **7–30d immutable**
  - **Manifests: 15–60s + `stale-while-revalidate, stale-if-error=60`**
- Enable **Origin Shield** and Brotli/Gzip for text (`.vtt`).
- Optional: signed cookies/URLs for HLS.

## DELIVERABLES
- Files: `/iac/cloudfront_s3/*` (Terraform or CDK)
- Tests: IaC plan output + manual header validation
- Output: diff-ready code + short rationale

## ACCEPTANCE
- Manifest responses show short TTL **with** `stale-while-revalidate` **and** `stale-if-error=60`.
- Long-lived immutable headers for sprites/VTT/posters; segments 7–30d; no cookies/headers/query in cache key.
- Origin Shield enabled.
