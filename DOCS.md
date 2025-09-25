# Doc Index

Concise links to the source of truth for product, architecture, guardrails, and the canonical Events API checklist.

- Product Requirements (PRD)
  - `prd.md`
- Architecture (Refined, Corrected)
  - `Signal_Video_Architecture_v2_Refined_CORRECTED.md`
- Agent Guide (System Guardrails for Clients/Backend/IaC)
  - `Signal_Agent_Guide.md`
  - `AGENTS.md` (repo‑wide rules and working conventions)
- Events API — Canonical Implementation Checklist
  - `Phase-2A-Tasks/events_api_subtasks.md`
- Supporting Context
  - `Phase-2A-Tasks/events_api_implementation_prompt.md` (context/standards; implement from the checklist above)

Related (CDN & Pipeline references)
- CloudFront cache policy and behaviors: `terraform-cloudfront-cache.tf`
- MediaConvert template: `mediaconvert-storyboard-template.json`
- Storyboard post-step Lambda (sprites + WebVTT): `sprite-vtt-generator.js`

## Automation Suites

- iOS pooled-feed perf regression:
  ```
  xcodebuild -project iOS/signal.xcodeproj \
             -scheme signalUITests \
             -destination "platform=iOS Simulator,name=iPhone 15" \
             test
  ```
- Android pooled-feed perf regression (build with `AUTOMATION_METRICS=true` so telemetry is emitted):
  ```
  AUTOMATION_METRICS=true ./gradlew :app:connectedDebugAndroidTest
  ```
