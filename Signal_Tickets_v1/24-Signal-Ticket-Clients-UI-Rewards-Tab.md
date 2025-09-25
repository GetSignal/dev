# Ticket 26 — Clients: UI — Rewards Tab (Main Menu Bar)

**Date:** 2025-09-08  
**Priority:** P3 (UI scaffold)  
**OS Baselines:** iOS **16+**; Android **minSdk 26** / **targetSdk 35**

## PURPOSE
Add a **Rewards** entry to the **Main Menu Bar** (bottom tab). Provide a lightweight screen scaffold so the tab is navigable and testable. Placement within the tab bar is **unspecified** (any position is acceptable for now).

## SCOPE (V1 — UI only)
- **Bottom Tab Item:** label “Rewards” with a generic trophy/award icon (platform default).  
- **Screen Scaffold:** static header “Rewards”. Body shows a neutral placeholder state (e.g., “Rewards coming soon”).  
- **Navigation:** integrate with the app’s bottom-tab navigator. Preserve back-stack behavior and deep link stability.  
- **Theming/Mode:** light/dark support; respects safe areas and dynamic type.  
- **Accessibility:** tab and screen are accessible via VoiceOver/TalkBack with appropriate labels.  
- **Offline:** screen renders without network calls.

## NON-GOALS (deferred)
- Earning rules, balances, redemption flows, catalogs, ledgers, or server endpoints.  
- Notifications, badges, or experiment frameworks.

## ACCEPTANCE CRITERIA
- A “Rewards” tab appears in the Main Menu Bar and navigates to a stable screen scaffold.  
- No interference with feed playback, gestures, or other tabs.  
- UI snapshots pass for light/dark themes and multiple device sizes.  
- Startup/perf unaffected (no additional network requests on tab display).

## IMPLEMENTATION NOTES
- **iOS:** Add a tab item in the root `UITabBarController`/SwiftUI TabView. Create `RewardsView` with static content.  
- **Android:** Add a `BottomNavigation` item and route. Create `RewardsFragment` / Compose `RewardsScreen` with static content.  
- **Feature Flag:** `ff_rewards_tab` (default OFF) to enable staged rollout.

## DEPENDENCIES
- **Main Menu Bar / Bottom Navigation shell** (separate ticket). Rewards tab attaches to this shell when available.

