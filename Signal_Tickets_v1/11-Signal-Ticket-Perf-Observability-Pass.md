
# Ticket 11 — Performance & observability pass
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Instrument TTFF, rebuffer ratio, selected bitrate, CDN hit ratio; ensure budgets/SLOs are met.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Dashboards and metrics that catch regressions; remediate any budget violations.

## CONSTRAINTS
- TTFF P75 < 1.2s / P95 < 2.0s.
- Rebuffer < 1% of playback time.
- CDN hit ≥ 97%.
- Ranker P99 ≤ 30 ms; fallback to Trending.
- Include device model & app version fields.

## DELIVERABLES
- Files: client metrics hooks, server counters, dashboard configs
- Tests: smoke perf test for TTFF; unit tests for aggregations
- Output: diff-ready code + rationale

## ACCEPTANCE
- Dashboards for TTFF, rebuffer %, selected bitrate, CDN hit ratio, ranker latency.
- Remediation issues or PRs filed for any out-of-budget metrics.
