# BookHut Audio Service Fix v5

This is a comparison-driven fix plan for `AviranHub/BookHutFlutterApp`.

## Findings

The reference project `Abdullah-Masood-05/NoirPlayer` uses the same fundamental architecture as BookHut:

- `MainActivity : AudioServiceActivity()`
- `AudioService.init(builder: () => AudioPlayerHandler(), config: ...)`
- one `AudioPlayer` owned by `AudioPlayerHandler`
- `BaseAudioHandler` forwards play/pause/seek/next/previous to `just_audio`
- `main()` currently initializes the service before `runApp()`.

The important difference for the current BookHut debugging case is that NoirPlayer explicitly catches initialization failure and still calls `runApp()`. BookHut currently awaits `AudioService.init()` directly, so a service initialization hang can keep the whole Flutter UI on the Android launch/loading screen.

## Important current BookHut observations

1. `MainActivity` is already `AudioServiceActivity`, matching NoirPlayer.
2. The BookHut manifest declares the audio service and foreground media-playback permissions.
3. BookHut currently uses `com.ryanheise.audioservice.MediaButtonReceiver`, while the inspected NoirPlayer manifest uses `androidx.media.session.MediaButtonReceiver` and also declares a MEDIA_BUTTON intent filter on `MainActivity`.
4. `AudioPlayerScreen` assumes `globalAudioHandler` has already been initialized in `main()`.
5. Therefore, simply moving `AudioService.init()` after `runApp()` requires changing the player screen to wait for the handler; otherwise `late final globalAudioHandler` can cause a `LateInitializationError`.

## v5 strategy

Do NOT create a second Activity.

Keep exactly one launcher Activity:

```kotlin
class MainActivity : AudioServiceActivity()
```

Keep exactly one `AudioPlayer` instance, owned by the `AudioPlayerHandler`.

Make audio initialization asynchronous from the UI bootstrap, but expose a Future/Completer so `AudioPlayerScreen` waits for the handler only when the audio player screen is actually opened.

This prevents a broken Android audio-service initialization from blocking Home/Explore/Library/Profile.

## Manifest comparison

Align BookHut's media button declarations with the working reference while retaining BookHut's existing Flutter activity attributes. In particular, verify:

- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `WAKE_LOCK`
- `POST_NOTIFICATIONS`
- `AudioService` with `android:foregroundServiceType="mediaPlayback"`
- `androidx.media.session.MediaButtonReceiver`
- `MEDIA_BUTTON` intent filter on the launcher Activity

Do not add a second Activity.

## Do not apply this package blindly

This folder is a reviewed implementation plan, not a claim that the APK has been compiled here. The actual BookHut project remains untouched.
