# Agent Memory — durable facts (spilled from Hermes persistent memory, 2026-09-07)

Hermes' memory store was at capacity; these facts live here so nothing is lost.
The agent re-reads this file at the start of JooseBooks sessions.

## Repo layout (post-reorg 2026-09-07)
- `~/joose-labs/joosebooks` — Flutter edition, THE keeper (local folder renamed from joosebooks_flutter)
- GitHub remote is still named `joosebooks_flutter` (rename pending, pairs with going public; old URLs redirect after rename)
- `~/joose-labs/joosebooks-godot-archived` — Godot edition, ARCHIVED on GitHub (read-only). Historical reference only.
- `docs/business-profiles-spec-godot.md` — original spec from the Godot edition, preserved
- v0.1.0-alpha released: 3 desktop CI builds (macos/windows/linux zips verified); release workflow triggers on `v*` tags

## JooseBooks gotchas
- DEBUG builds run with App Sandbox OFF (machine-wide secinitd XPC wedge on this Mac; Release keeps sandbox for Play Store)
- Active user DB: `~/Library/Application Support/com.jooselabs.joosebooksFlutter/joosebooks.db`
  (old sandboxed container-path DB was migrated in; container DB also upgraded to v2 as fallback)
- 405pt phone-shaped window header: use natural-width chip (NOT Flexible+Spacer — Spacer steals flex share), compact chevron IconButtons (28w)
- Synthetic keyboard events never land in Flutter windows (clicks + AXPress do) — drive text via on-screen numpad or sqlite seeding
- Profile chip is GOLD only when ≥1 business exists (spec: quiet door)

## Backlog
- Flip GitHub repo public (CEO decision), optionally rename remote to `joosebooks`
- Code-signing (Apple ~$99/yr, Windows EV ~$200-400/yr) — current builds unsigned (right-click → Open)
- Edit-entries feature, mobile share-sheet CSV, app icon polish, Play Store publish (docs/PLAY_STORE_RUNBOOK.md)
