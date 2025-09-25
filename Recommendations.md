Recommendations

  1. Re-enable iOS pooling once the cancellation/identity safeguards are in place (e.g., bind token that matches cell.item before attaching) so the implementation matches the spec and Android parity.
  2. Harden the iOS play-on-ready flow: gate autoplay solely on the readyToPlay observer (remove the unconditional player.play() in FeedCell.attach) to guarantee deterministic TTFF.
  3. Introduce bind tokens (or Task ID checks) on both platforms so async manifest/player work never lands on a recycled cell, then add regression tests for rapid scroll churn.
  4. Raise the backend FALLBACK_DAYS default to the 5–7 day window the tiktok-standard.md doc calls for, and add observability around empty responses before pooling is rolled back in.
  5. Capture the validation scenarios from tiktok-standard.md in automated UI/perf runs, so the pool reintroduction can be guarded by measurable TTFF and stall budgets.

