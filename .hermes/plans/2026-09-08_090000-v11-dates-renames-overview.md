# JooseBooks v1.1 — Dates, Renames, Overview Implementation Plan

> **For Hermes:** Implement task-by-task with TDD. Visual verification (screenshots) is MANDATORY for every UI change — headless tests are necessary but not sufficient (CEO rule).

**Goal:** Add (1) an editable date on new transactions, (2) renameable profiles including the default Personal pile, (3) a visual Overview home screen with per-profile graphs.

**Architecture:** New `lib/db.dart` owns the schema (DB v3) + aggregation queries; new `lib/overview.dart` + `lib/charts.dart` add the Overview home with hand-painted mini bar charts (CustomPainter, zero new dependencies); `lib/main.dart` keeps the dashboard, add-sheet, and popovers and imports the shared db layer.

**Tech Stack:** Flutter 3.47, sqflite_common_ffi, existing P0 design tokens (#0D0D10 / #D4A843 / gold-green-red), no new pub deps.

**Overview design decision (CEO delegated):** per-profile cards on the home screen, each with a 12-month mini bar chart (green income bars up, red expense bars down, dim baseline for empty months), year totals on the card, tap → the existing dashboard for that pile. Rejected: fl_chart line graphs (new dep, harder to read at card size, hides per-pile shape); single combined chart (hides the per-profile picture the CEO asked for).

---

## Task 1: Extract db layer + DB v3 (Personal becomes a real row)

**Objective:** Centralize schema so tests stop duplicating it, and make Personal renameable by giving it a real row (id=0) — semantics of `profile_id = 0` stay identical.

**Files:**
- Create: `lib/db.dart`
- Modify: `lib/main.dart` (remove inline schema, import db.dart)
- Test: `test/profiles_test.dart` (import shared factory)

**Design:**
- `openAppDatabase(path)` → version 3. onCreate: existing v2 tables + `INSERT OR IGNORE INTO profiles (id, name, entity, created_ts) VALUES (0, 'Personal', '', 0)`. onUpgrade: keep `oldV < 2` block, add `oldV < 3` → same INSERT OR IGNORE (id=0 can't collide — v2 autoincrement started at 1).
- Personal row means popover/chips/cards iterate `profiles` directly (no more hardcoded virtual row); CSV keeps `joosebooks_<year>.csv` for a Personal pile still named "Personal", slug otherwise.

**Steps (TDD):**
1. RED: tests — fresh v3 DB has profiles row id=0 name='Personal'; v2 DB with a business upgrades → Personal row added, business untouched; v1→v3 chain upgrades both.
2. Run: `flutter test` — expect failures.
3. GREEN: write `lib/db.dart`, switch main.dart to it.
4. `flutter analyze` clean + `flutter test` green.
5. Commit: `feat(db): v3 schema, Personal as real profile row, shared db layer`

## Task 2: Rename profiles (incl. Personal)

**Objective:** Pencil icon per row in the pile popover → rename dialog (prefilled) → UPDATE.

**Files:**
- Modify: `lib/main.dart` (popover rows, `_openRenameProfile`)
- Test: `test/db_test.dart` — rename via UPDATE keeps entries pointing at same id.

**Steps (TDD):**
1. RED: db test — update name on profile 0, queries by profile_id unaffected.
2. GREEN: rename method + UI (pencil IconButton; Personal gets pencil only, businesses keep long-press delete).
3. `flutter analyze` + tests; visual check: open popover, screenshot dialog prefilled; rename via sqlite3 UPDATE + screenshot showing new name everywhere (synthetic keyboard never lands in Flutter — proven wedge).

## Task 3: Date field on transactions

**Objective:** Add-entry sheet gets a date row (defaults to today); tapping opens `showDatePicker`; entry stores chosen date at local noon.

**Files:**
- Modify: `lib/main.dart` (AddEntrySheet date row, `_save` ts, entry list shows `MMM d`)
- Test: db-level — inserting with explicit ts preserves the chosen date (noon rule, month bucket correctness).

**Steps (TDD):**
1. RED: test — entry saved with ts at noon of chosen day lands in the right month bucket and year query.
2. GREEN: date row UI + state + save logic.
3. Visual verify by clicks only (picker cells are clickable): open sheet → date row → pick different day → row shows it → Save → list shows 09/01-style date.

## Task 4: Overview home screen

**Objective:** Overview becomes home: profile cards (Personal first, then businesses), each with mini 12-month bar chart + income/expenses/profit for the year; tap → dashboard for that pile.

**Files:**
- Create: `lib/db.dart` addition — `monthlyByProfile(db, year)` (bucket in Dart from one year query)
- Create: `lib/charts.dart` — `MiniBarChart` CustomPainter (P0 colors, 12 slots, up/down bars)
- Create: `lib/overview.dart` — OverviewPage + ProfileCard
- Modify: `lib/main.dart` — home = OverviewPage; DashboardPage gets back arrow when pushed
- Test: `test/db_test.dart` — bucket math (income/out per month, per profile); widget smoke test for OverviewPage rendering card names from seeded db.

**Steps (TDD):**
1. RED: bucket tests + widget test.
2. GREEN: implement query, painter, page, navigation.
3. `flutter analyze` + tests; visual verify with sqlite3-seeded data across months/piles: overview screenshot, drill-in screenshot, resize check (Flutter reflow criterion).

## Task 5: Final gates + docs

- `flutter analyze` clean; `flutter test` green.
- Visual scorecard screenshots: overview, dashboard, add-sheet date, rename popover.
- CHANGELOG.md entry; commit per task; report per-feature scorecard with proof column (CEO format).

**Risks / notes:**
- Existing v2 installs get the Personal row via guarded INSERT OR IGNORE — no data moved, upgrade-preserves-data test proves it.
- Synthetic input limits: keyboard never lands in Flutter fields; date picker + chips are click-only (verified); rename text verified via sqlite3 seed.
- CSV filename for default-named Personal stays `joosebooks_<year>.csv` (accountant convention preserved).
- Release (AAB +N, Play upload) is a separate CEO-gated step — NOT in this plan.