# JooseBooks v1.1 — Changelog

## Unreleased (Sep 9–10 2026) — edit entries, swipe-to-delete with undo

### Added
- **Edit existing entries** — tap any row on the dashboard to open the
  same add-entry sheet in edit mode: every field prefilled (date, in/out,
  amount, category, pile, note), gold "Edit entry" title, "Save changes"
  button. Saving updates the row in place (same id, date/pile preserved
  unless changed); cancel discards everything.
- **Swipe-to-delete with undo** — swipe a dashboard row left to delete it.
  The row leaves the list immediately and a snackbar offers UNDO (gold).
  Undo restores the identical row — same id and all fields — so edits
  chained after a restore are never lost. Multiple rapid deletes queue
  their snackbars (FIFO), so every delete stays undoable.
- Demo/screenshot modes for QA: `JOOSBOOKS_DEMO=1` (throwaway demo DB +
  auto-opens edit sheet), `=2` (demo DB, plain list), `=3` (demo DB +
  auto-runs one delete to show the undo snackbar). Real books untouched.

### Fixed
- Swipe-to-delete on device threw "Unsupported operation: read-only" —
  the dismissed row was mutated out of the unmodifiable list returned by
  `db.query` inside `setState`. Rows now leave via list rebind before the
  snackbar shows, per Dismissible's contract (item gone from the tree in
  the same frame).
- Rapid double-delete's second snackbar replaced the first, permanently
  orphaning the first row's undo. Snackbars now queue natively.

### QA (test/entry_lifecycle_qa_test.dart — 8 adversarial cases)
- Cancel-edit persists nothing; keypad caps at 9 digits / 2 decimals
  (`1.234` → `1.23` = 123 cents saved); UNDO restores every field + id;
  double-swipe deletes both rows with queued undos; late UNDO still
  restores; a restored row re-edits with correct prefill; double-tap
  Save saves exactly once; amount-only edit preserves date/category/
  note/pile.

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
- **Removed the duplicate "Quick add" button** at the bottom of the Overview
  card list — it opened the exact same add-entry sheet as the gold + FAB.
  The FAB is now the single add affordance.
- Month initials (J F M A M J J A S O N D) are rendered by the chart widget
  itself, one cell per month slot, so every letter is centered under its own
  bar column at any card width (previously a single letter-spaced text line
  whose spacing didn't track the chart geometry).

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