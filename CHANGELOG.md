# Changelog

All notable changes to JooseBooks are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-09-07

First public alpha. Desktop release (macOS, Windows, Linux).

### Added
- One-screen dashboard: year income / expenses / profit / tax set-aside (~28%),
  plus a this-month strip
- Add-entry sheet: money IN/OUT toggle, custom keypad, category chips,
  optional note
- Business Profiles: separate money piles (Personal default + any businesses
  with an entity type — Sole Prop, LLC, S-Corp, C-Corp, Partnership, Other);
  per-pile summaries, entries, and CSV exports; deleting a business moves its
  entries back to Personal (data is never deleted)
- CSV export with accountant-friendly filenames
  (`joosebooks_2026_my-llc.csv`)
- Year navigation (previous / next year)
- Offline-first local SQLite storage; no accounts, no network

[0.1.0]: https://github.com/Dr-Bongjoose/joosebooks_flutter/releases/tag/v0.1.0