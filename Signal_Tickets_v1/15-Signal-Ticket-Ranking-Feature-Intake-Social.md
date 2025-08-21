# Ticket 15 — Ranking: Social feature intake (low-weight)
**Date:** 2025-08-16  
**Priority:** P2 (safe wiring)

## TASK
Plumb follow edges and likes into the online ranker **feature vector**, but keep initial weights ~0. Enable gradual ramp via config.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Add *minimal scaffolding only* for Users/Follows/Likes, keeping scope tiny and safe. Respect CDN/TTL rules, manifest usage, and existing telemetry batching. No on-device frame extraction.

## FEATURES
- Per-user: following set, followers count (approx), liked-video ids (recent window), author affinity.
- Per-video: like count (approx), recent like velocity.

## CONSTRAINTS
- No behavior change at first: weights set to ~0 in config; add toggles to ramp safely.
- Redis or feature service fetch must stay within ranker P99 ≤ 30 ms budget; otherwise skip gracefully.
- Backfill jobs can run later; do not block MVP.

## DELIVERABLES
- Code: `/services/ranker/features/social_features.*` + config hooks.
- Tests: unit tests for feature shaping and timeouts.
- Output: diff-ready code + rationale.

## ACCEPTANCE
- Ranker reads social features without breaching latency budget; safe defaults when missing.
- Weights/toggles allow gradual rollout; tests pass.
