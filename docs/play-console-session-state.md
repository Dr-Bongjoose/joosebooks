# JooseBooks — Play Console session state (v4)

## Current state (2026-09-08 afternoon)
- **Alpha release 1.0.0 (versionCode 1) is LIVE** on Closed testing - Alpha, published Sep 8.
- Tester list **JB Testers** (2 users incl. insanlycrazy14@gmail.com) attached to Alpha; review cleared.
- User installed the app → **v1 build crashes on Android startup** and shows wrong name/icon.

## Root causes diagnosed (fixed in repo, awaiting new AAB upload)
1. **Crash**: `sqflite_common_ffi` + `databaseFactoryFfi` without `sqlite3_flutter_libs` → no bundled libsqlite3.so on Android → startup crash before UI. Desktop worked (system SQLite).
2. **Name**: `android:label="joosebooks_flutter"` (template default) → fixed to "JooseBooks".
3. **Icon**: default Flutter mipmap → replaced with JB monogram via flutter_launcher_icons
   (config: `flutter_launcher_icons.yaml`, source: `../branding/joosebooks/icon_512_v3_preview.png`,
   adaptive bg #0D0D10, foreground built with sips to 1024).

## Fixes committed (commit a499f71 + version bump)
- `pubspec.yaml`: + sqlite3_flutter_libs; version now **1.0.0+2**
- `AndroidManifest.xml`: label "JooseBooks"
- New AAB built + **verified with bundletool**: versionCode=2, versionName=1.0.0, label=JooseBooks, JB icon in mipmaps, libsqlite3.so bundled for arm64/armv7/x86_64
- AAB path: `~/joose-labs/joosebooks/build/app/outputs/bundle/release/app-release.aab` (52 MB, built 12:44)

## NEXT ACTIONS (in order)
1. ~~Upload new AAB~~ ✅ DONE — v1.0.0+2 uploaded, release name "1.0.0 (2) - crash fix", notes submitted, "Changes in review" on Publishing overview.
2. **WAIT for Google review** of the 1.0.0+2 release (app-update reviews usually fast: minutes–hours). Track page will show "Changes in review" until then.
3. After approval: Alpha track serves versionCode 2. User's phone auto-updates (Play may lag up to a few hours; force-stop Play Store or check My apps → Updates).
4. Verify on device: name "JooseBooks", JB icon, no startup crash. 14-day clock continues.
5. Version policy going forward: every console upload needs a NEW versionCode (bump + in pubspec.yaml).

## Gotchas learned this session
- `android:label` is the store/launcher name — pubspec `name:` is NOT it.
- Desktop-first sqflite_common_ffi apps MUST ship sqlite3_flutter_libs for Android/iOS.
- flutter_launcher_icons: foreground art should be ~66% of canvas (safe zone); whole-square art gets cropped by circular masks.
- bundletool dump manifest = reliable AAB verification (aapt2 can't read .aab directly).
- Publishing overview "Restart review" button appears if review already in progress.
- Testers email-list changes re-trigger review; "in review" blocks opt-in link until cleared.

## Tester install link
- Opt-in: https://play.google.com/apps/testing/com.jooselabs.joosebooks
- Store listing: https://play.google.com/store/apps/details?id=com.jooselabs.joosebooks
- 14-day closed-test clock starts when ~12 testers have the build. Currently 1 tester (user).