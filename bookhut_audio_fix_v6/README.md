# BookHut Audio Fix v6

This is the comparison-driven v6 for `AviranHub/BookHutFlutterApp`. The original repository is intentionally NOT modified.

## References inspected

- Koel Player (`koel/player`): `MainActivity` extends `AudioServiceActivity`; Android manifest declares `AudioService` as a mediaPlayback foreground service; its `KoelAudioHandler` owns a single `just_audio.AudioPlayer`, subscribes to playback events, and adds a source-load timeout because a stalled source can remain in loading indefinitely.
- NoirPlayer: same basic `AudioService.init -> AudioPlayerHandler -> just_audio` architecture.

## BookHut changes in v6

1. Keep one `MainActivity` and make it extend `AudioServiceActivity`.
2. Keep one `AudioPlayer`, owned by `AudioPlayerHandler`.
3. Start AudioService initialization as a Future instead of blocking Flutter bootstrap.
4. `AudioPlayerScreen` awaits that Future before assigning its handler/player.
5. Add a timeout around `setAudioSource` / `setAudioSources` so a bad/stalled URL cannot leave the player waiting forever.
6. Preserve BookHut's offline-file-first behavior.
7. Do not create a second Activity.
8. Keep all proposed changes in this repository only.

## Important

Do NOT copy only `main.dart`. `audio_player_screen.dart` must also be changed to await `audioHandlerFuture`, otherwise the old `late globalAudioHandler` access can produce `LateInitializationError`.

## Build

flutter clean
flutter pub get
flutter analyze
flutter build apk --release
