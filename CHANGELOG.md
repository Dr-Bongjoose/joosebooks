# JooseBooks v1.1 — Changelog

## Unreleased (Sep 8 2026) — dates, renames, overview

### Added
- **Transaction date field** — the add-entry sheet now has a date row
  (defaults to today). Tap it to open a calendar picker; the chosen day is
  stored at local noon so month/year bucketing never drifts across midnight
  or DST edges. The dashboard list shows the entry's real date (MMM d).
- **Overview home screen** — the app now opens on a year-at-a-glance view:
  one card per pile (Personal first), each with a 12-month mini bar chart
  (green income up, red expenses down, dim ticks for empty months), in/out
  totals and profit. Year navigation arrows. Tap a card to drill into that
  pile's dashboard; a back button on the dashboard returns to Overview.
- **Profile renaming** — every pile in the pile popover (including the
  default Personal pile) has a pencil button opening a rename dialog,
  prefilled with the current name. Renaming never touches entries.

### Changed
- DB v3: Personal is now a real profile row (id 0) instead of a virtual
  concept. Entry semantics are unchanged (profile_id 0 = Personal); existing
  v1/v2 installs upgrade in place with no data movement.
- Dashboard header shrinks gracefully (Flexible title, compact year nav) so
  the back button fits narrow windows.

### Fixed
- Rename popover showed stale names until reopen (state refresh before
  re-rendering).
- Overview card month labels overflowed on narrow windows (moved to their
  own centered line).

### Notes for testers
- Overview charts read from the same queries the dashboard uses; totals on a
  card always match the pile's dashboard summary.
- CSV export naming is unchanged (`joosebooks_<year>.csv`, slugified for
  business piles).