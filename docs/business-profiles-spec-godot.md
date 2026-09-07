# JooseBooks — Business Profiles (v1 spec)

> Status: DRAFT — awaiting CEO greenlight
> Principle (CEO's words): "The main app should still focus on people starting out.
> The profile should feel like a bonus feature for when a person is ready."

## The idea
A person might have more than one thing earning money — a day job's freelance work,
an Etsy shop, an LLC for the app business. Today JooseBooks lumps everything into one
pile. Business Profiles let people split their books: **Personal** (the default, always
there) plus any businesses they create, each with a **name + entity type** (LLC,
Sole Proprietor, S-Corp, C-Corp, Partnership, or custom).

The app must be *visually identical* for someone with zero businesses. The feature
announces itself only when you go looking — and then it feels like a treat, not homework.

## Data model (DB.gd)
```sql
CREATE TABLE IF NOT EXISTS profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    entity TEXT DEFAULT '',        -- "LLC", "Sole Prop", custom string
    created_ts INTEGER NOT NULL
);
ALTER TABLE entries ADD COLUMN profile_id INTEGER DEFAULT 0;  -- 0 = Personal
CREATE INDEX IF NOT EXISTS idx_entries_profile ON entries(profile_id, ts);
```
- Migration is guarded: `ALTER TABLE` in a try (existing installs add the column; fresh
  installs get it from CREATE). Existing entries stay Personal — nobody's data moves.
- Every DB read/write function gains an optional `profile_id = 0` param. Default paths
  behave exactly as today.

## UX: the quiet door
- **Header chip** next to the title: `👤 Personal ▾` — small, dim, ignorable.
- Tap it → small popover: your profiles (Personal always on top), and
  `＋ Add a business`.
- **Add a business**: name field + entity chips (Sole Prop / LLC / S-Corp / C-Corp /
  Partnership / Other…) + Save. Two fields, ten seconds.
- With 0 businesses the chip still says `👤 Personal` and the popover shows only
  Personal + the add button — honest, quiet, no nags, no onboarding popup.

## Where profiles show up
1. **AddEntrySheet**: one small chip row (only rendered when ≥1 business exists).
   Default = whatever profile is selected on the dashboard. Starts on Personal.
2. **Dashboard**: summary panel, month strip, entries list, and CSV export all
   respect the selected profile. Switching profiles re-queries — numbers are per-pile.
3. **CSV export**: exports the selected profile; filename gets the business name
   (`joosebooks_2026_my-llc.csv`) so handing "the LLC file" to an accountant is literal.
4. **Entity type display**: profile name renders as `Bong Media LLC` in the chip and
   sheet; the entity is also stored standalone for future tax-rate smarts.

## Explicitly NOT in v1 (YAGNI)
- No combined "all piles" rollup view (v1.1 candidate once someone asks).
- No per-entity tax rates (S-Corp vs Sole Prop have genuinely different set-aside
  math — v2, needs real rates, not vibes).
- No renaming/deleting UI beyond: delete = long-press in popover, **entries fall back
  to Personal** (no data ever deleted).
- No profiles in JooseBooks' Play Store listing copy — the store page sells the one-pile
  simplicity; profiles are an inside treat.

## Tests (autotest.gd additions, headless)
1. Fresh DB → profiles table exists, entries has profile_id column, default 0.
2. Existing pre-migration DB (simulate by creating table without column, then opening)
   → column added, old entries readable and belong to Personal.
3. Create profile "Test LLC" (entity LLC) → add entry $100 in under it →
   Personal summary unchanged; LLC summary shows $100; all-piles still not a thing.
4. CSV for profile → correct rows + filename.
5. Delete profile with entries → entries reassigned to profile_id 0, profile gone.

## Effort
~150 lines across DB.gd (+60), Dashboard.gd (+40), AddEntrySheet.gd (+25),
autotest.gd (+30). One session, zero backend (it's all offline SQLite).