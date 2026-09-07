# JooseBooks

**Bookkeeping for people who hate bookkeeping.**

Money in, money out, profit. One screen, zero jargon, everything offline.

JooseBooks is for freelancers, side-hustlers, and small business owners who
just want to know: *am I making money?* Record income and expenses in
seconds with a big-button keypad, see your year at a glance, and hand your
accountant a clean CSV when tax time comes. No accounts, no cloud, no
subscriptions — your books live on your device and nowhere else.

## Highlights

- **One-screen dashboard** — income, expenses, profit, and tax set-aside for the year, plus a this-month strip
- **10-second entry** — custom keypad built for thumbs; categories are one tap; notes optional
- **Business Profiles** — keep Personal and business money in separate piles (Sole Prop, LLC, S-Corp…) with per-pile summaries and CSV exports. Quiet by design: you'll never see it until you go looking
- **CSV export** — `joosebooks_2026.csv` or `joosebooks_2026_my-llc.csv`, accountant-ready
- **Offline-first** — SQLite on your device. No account, no telemetry, no data collected
- **Dark, calm UI** — gold on charcoal, readable at a glance

## Platforms

| Platform | Status |
|---|---|
| macOS | ✅ v0.1.0 |
| Windows | ✅ v0.1.0 |
| Linux | ✅ v0.1.0 |
| Android | 🚧 coming soon (Play Store) |
| iOS | 🚧 planned |

Downloads are on the [Releases page](https://github.com/Dr-Bongjoose/joosebooks_flutter/releases).

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
flutter test                # runs the unit tests
flutter run -d macos        # or linux, windows
```

Release builds:

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

## Privacy

JooseBooks collects nothing. All data stays in a local SQLite database on
your device. There is no server, no analytics, and no network permission.

## License

[MIT](LICENSE) — © 2026 Joose Labs