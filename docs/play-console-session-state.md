# JooseBooks — Session Handoff (v5)
**Date:** 2026-09-08 (late evening) · **Next session:** new UX features for the app

## ✅ MILESTONE: JOOSEBOOKS IS LIVE AND WORKING ON THE USER'S PHONE
- v1.0.0 (versionCode **3**) published on **Closed testing - Alpha**, 177 countries.
- Publishing overview CLEAN — review of +3 cleared and shipped same evening.
- User's Pixel: installs, opens, and **works** (user confirmed by using it; icon + name correct).
- Store listing: `play.google.com/store/apps/details?id=com.jooselabs.joosebooks`
- Opt-in link: `play.google.com/apps/testing/com.jooselabs.joosebooks`

## What it took to get here (the crash saga — don't repeat)
1. **v1**: sqflite_common_ffi without `sqlite3_flutter_libs` → no bundled SQLite on Android.
2. **v2**: fixed SQLite (kept), fixed label ("joosebooks_flutter"→"JooseBooks" in AndroidManifest) + JB launcher icon (flutter_launcher_icons) — but STILL crashed.
3. **v3 REAL root cause** (found via emulator logcat): `ClassNotFoundException` — manifest
   `.MainActivity` resolves against Gradle **namespace** (`...joosebooks_flutter`), but
   MainActivity.kt sat in `kotlin/com/jooselabs/joosebooks/`. Fixed by moving MainActivity.kt
   into the namespace package. **Emulator-verified: 0 crashes, UI runs.** Review cleared.
- Lesson: a desktop-first Flutter app must be launch-tested on Android before store upload.
  Emulator reproduce → logcat crash buffer → fix → verify was a ~15-min loop.

## Current app architecture (single file, on purpose)
- `lib/main.dart` — ALL app code: one-screen dashboard (money in/out, profit),
  SQLite entries+profiles tables (schema v2), CSV export, profiles concept exists in DB
  (profile_id column, profiles table) but **UI shows no profile switching yet** — good hook
  for new features.
- Design: #0D0D10 bg, #17171D/#212129 surfaces, #D4A843 gold, kGreen/kRed for +/-,
  categories: Server costs / Equipment / Software+tools / Revenue / Other.
- DB at `getApplicationSupportDirectory()/joosebooks.db`, version 2 (onUpgrade guarded ALTER).

## Release process (works, repeat for every new build)
1. Bump `pubspec.yaml` version `+N` (currently **1.0.0+3**).
2. `flutter build appbundle --release` → AAB at `build/app/outputs/bundle/release/`.
3. Verify with bundletool: `java -jar /tmp/bundletool.jar dump manifest --bundle=<aab>`
   (download bundletool from GitHub releases; aapt2 can't read .aab).
4. Console: Closed testing → Alpha → Create new release → **user uploads AAB manually**
   (native file picker can't be driven) → release name + `<en-US>` tagged notes → Next →
   Save → Publishing overview → Submit → wait quick checks (~5-10 min) → Send for review.
5. Update reviews are fast (same day). New releases deactivate the old one until cleared.

## Environment gotchas (learned this session, verified)
- Emulator Pixel_3a_API_33: needs `-wipe-data -partition-size 4096` for a 56MB AAB; default
  partition fills up → `INSTALL_FAILED_INSUFFICIENT_STORAGE`. Kill with `pkill qemu-system-aarch64`.
- adb at `~/Library/Android/sdk/platform-tools/adb`; `adb` alone not on PATH.
- AX `set_value` sets web form fields reliably; CGEvent clicks reach pages; native file
  pickers DON'T respond to synthetic input → user does uploads.
- Publishing overview "Restart review" button appears when a review is already in progress.
- Release notes REQUIRE `<en-US>` tags or validation error "text outside language tags".
- macOS disk was ~5GB free; /tmp cleanups of aab-extract dirs help.
- Emulator was left RUNNING at session end? No — killed (pkill qemu-system-aarch64).

## NEXT SESSION BRIEF
User used the app on their phone and has **new feature ideas** (not yet specified — ask first).
Candidates seen in DB/code (user may or may not want these):
- Profile switching UI (DB already supports it)
- CSV export polish, monthly summaries
Whatever they are: bump versionCode, verify on emulator FIRST (launch + feature),
then AAB → console flow above.

## Key files
- Handoff (this doc): `~/joose-labs/joosebooks/docs/play-console-session-state.md`
- App code: `~/joose-labs/joosebooks/lib/main.dart`
- Branding: `~/joose-labs/branding/joosebooks/` (icon_512_v3_preview.png = launcher source)
- flutter_launcher_icons.yaml in repo root (icon regen: `dart pub global run flutter_launcher_icons`)
- Git: all committed through "Handoff: v1.0.0+3 submitted"; working tree clean at handoff.
- Tester list: "JB Testers" (2 users, insanlycrazy14@gmail.com + 1 more); feedback = bongjoose@jooselabs.com
- 14-day closed-test clock: starts when ~12 testers have the build (currently ~1). Production
  unlock needs 12 testers × 14 days. Next session can also prep that if user wants.