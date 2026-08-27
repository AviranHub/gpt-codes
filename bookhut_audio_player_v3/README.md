# BookHut Audio Service — v3 candidate fix

This folder is a **non-invasive patch workspace** for `AviranHub/BookHutFlutterApp`.

The original repository is intentionally untouched.

## Findings from the current source

1. `audio_service: ^0.18.19` and `just_audio: ^0.10.6` are already present.
2. The main manifest already declares `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, and the `AudioService`/`MediaButtonReceiver` components.
3. The screen already uses the same `AudioPlayer` owned by `globalAudioHandler`, so the old "two players" problem has already been fixed.
4. `AudioService.init()` is wrapped in a catch-all fallback. If initialization fails in Release, the app silently replaces the real background service with a plain `AudioPlayerHandler`. This can make normal in-app playback work while background playback does not.
5. The current config uses `androidStopForegroundOnPause: true`. For BookHut, v3 intentionally keeps the service foreground while paused to avoid Android 12+ foreground-service restart restrictions when playback resumes from the background.
6. The Android activity is an empty `FlutterActivity`. The current `audio_service` setup documentation recommends using `AudioServiceActivity`; v3 provides a safe migration because BookHut's existing `MainActivity` contains no custom native code.

## Files

- `lib/main.dart` — replacement audio-service initialization/handler.
- `android/AndroidManifest.xml.additions` — exact manifest changes.
- `android/app/proguard-rules.pro.additions` — additional R8 safety rules.
- `android/app/src/main/kotlin/.../MainActivity.kt` — Activity migration.

## Important

These are candidate changes, not a commit to the production repository. Build and test them in a copy of BookHut before merging anything into `BookHutFlutterApp`.
