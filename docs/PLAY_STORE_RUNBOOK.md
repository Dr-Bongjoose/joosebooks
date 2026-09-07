# JooseBooks — Play Store Launch Runbook

**Status:** Signed AAB built ✅ · Play Console account = the remaining manual step.

## 1. What's already done (machine side)

- ✅ Android SDK working (Gradle + JDK 19 via `flutter config --jdk-dir`)
- ✅ Debug APK built & verified against emulator (install blocked only by the
  8GB AVD image being full — a non-issue for real devices)
- ✅ **Release signing**: `android/app/joosebooks-upload.jks` (alias `joosebooks`,
  passwords in `android/key.properties` — BOTH GIT-IGNORED, never commit them)
- ✅ **Signed release AAB**: `build/app/outputs/bundle/release/app-release.aab`
  (52MB, `jarsigner` verified)
- ✅ Application ID: `com.jooselabs.joosebooks_flutter`

## 2. Rebuild after any code change

```bash
cd ~/joose-labs/joosebooks_flutter
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

(The "failed to strip debug symbols" warning is benign — build succeeds.)

## 3. Play Console — CEO manual steps (~30 min + 1-2 day review)

1. **Create the account**: https://play.google.com/console — one-time $25 fee.
   Use the Joose Labs identity; personal account is fine to start.
2. **Identity verification**: Google requires government ID for new dev
   accounts; takes 1-2 days.
3. **App creation**: "Create app" →
   - Name: **JooseBooks**
   - Default language: English (US)
   - Type: **App** (not game)
   - Free or paid: **Free** (v1)
4. **Store listing** (draft text below) + screenshots:
   - Take screenshots from the running app: dashboard, add-entry sheet, year
     view. 1080×1920 PNG, 2-8 shots.
   - Feature graphic: 1024×500 (can generate from the icon + gold band)
   - App icon: 512×512 (see icon step below)
5. **Mandatory forms**: Content rating questionnaire (finance app, no user
   content = quick), Data Safety form (app collects NOTHING, all local —
   answer "No data collected", which is a genuine selling point), target
   audience (13+), ads: none.
6. **Upload the AAB** to Production → create release. First release must go
   through review (usually hours-few days for an offline utility).
7. **Privacy policy URL is required** even for no-data apps — host at
   `jooselabs.com/privacy` once the domain is live (CEO task), or use a GitHub
   Pages page in the interim.

## 4. App icon (before listing)

Replace the default Flutter icon: put a 1024×1024 PNG at
`assets/icon/icon.png`, add the `flutter_launcher_icons` package, run
`dart run flutter_launcher_icons`. The JB mark from the Godot SVG is the seed.

## 5. Version bumps

Every new upload needs a higher `version` in `pubspec.yaml`
(e.g. `1.0.1+2`). Version code = the number after `+`.

## 6. Notes

- The upload keystore is the **upload key**; Play re-signs for distribution.
  Back it up (Google also offers Play App Signing key reset — but don't rely
  on it; copy the .jks to two safe places).
- Internal testing track first (add yourself as tester), then production.
- $25 account fee + free app = total launch cost $25. The LLC can expense it
  (log it in JooseBooks, obviously).