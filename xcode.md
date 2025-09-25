# iOS Build & Validation Notes

## UI Automation Metrics
- Set `AUTOMATION_METRICS=1` (and optionally `AUTOMATION_METRICS_PATH=/tmp/metrics.jsonl`) when launching the app to capture telemetry for automated tests.
- Metrics are recorded as newline-delimited JSON entries (one per `TelemetryEvent`).
- The UI test `FeedPoolingPerfUITests.testRapidScrollMaintainsTTFFBudget` exercises rapid scroll scenarios and asserts that:
  - `time_to_first_frame.ms` values stay ≤ 2000 ms
  - No `playback_error` events fire during the run.

### Running Locally
```
xcodebuild -project iOS/signal.xcodeproj \
           -scheme signalUITests \
           -destination "platform=iOS Simulator,name=iPhone 15" \
           test
```

This command automatically sets the environment variables via the test target and writes metrics to a temp file.

## Manual Spot-Check
- Launch the app with `AUTOMATION_METRICS=1` to capture metrics while performing manual scroll churn.
- Inspect the metrics file to confirm TTFF values and absence of playback errors before enabling pooling changes in production.
