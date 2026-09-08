# Play Console Session State — JooseBooks (v3)

**Date:** 2026-09-08 (evening)
**Status:** 🚀 **ALL 13 CHANGES SUBMITTED FOR REVIEW** — "Changes in review" on Publishing overview

## What happened this session (v3)
1. AAB v1.0.0+1 uploaded by user (manual drag-drop), processed OK (App bundle 1, 8.81MB / 5s delivery).
2. Fixed release notes language tag error: notes must be wrapped in `<en-US>` tags.
3. Cleared 3 release errors: financial-features checkbox, Health apps declaration, Dashboard setup items.
4. Dashboard completed: Data safety ("no data collection"), Target audience (18+), Government apps (No), Financial features (No), Health (No), **App category = Productivity** (modal Save kept failing via AXPress; type-ahead in the open dropdown + Save worked), Contact details (jooselabs@protonmail.com + jooselabs.com).
5. **Last blocker: Advertising ID declaration** (App content → Advertising ID) = "No", saved.
6. Clicked "Submit 13 changes for review" → confirmed → **"Changes in review"** ✅

## Current state
- Publishing overview: all changes **in review**. Google review typically ≤7 days.
- Closed testing - Alpha: countries 176/176 ✅, testers EMPTY (deliberately deferred), release draft saved + submitted.
- Store listing: "Ready to send for review" (rolled into the same submission).
- App content: every form green.

## After approval
- Release goes live on Closed testing - Alpha track.
- **Testers still needed:** ~12 email addresses must be added to the track for the 14-day clock. Console may show "Changes in review" until approval; testers can be added anytime.
- 14-day closed-test clock starts only when ≥12 opted-in testers have the build.
- Then Production unlocks.

## Gotchas learned (v3)
- Release notes REQUIRE `<en-US>` wrapping or "Next" blocks with orange validation.
- Play Console modals: AXPress on Save sometimes returns -25202 (button not actually pressable via AX) — retry after re-capture; for virtualized dropdowns use type-ahead (type the option text) then Save.
- Dashboard "10 of 11" can lag a beat after saving; reload if stuck.
- The advertising-ID declaration lives in App content, surfaced via Publishing overview "View 1 issue".