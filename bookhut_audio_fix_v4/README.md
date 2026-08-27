# BookHut Audio Fix v4

This is a candidate fix for the BookHut Flutter background-audio issue. The original `AviranHub/BookHutFlutterApp` repository is intentionally not modified.

## Important finding

The app currently awaits `AudioService.init()` before `runApp()`. If Android service/plugin startup blocks or fails during startup, the user remains on the Android/Flutter launch screen and never reaches the Flutter UI. This explains the reported "stuck on loading" behavior much better than a normal player-screen loading state.

The current Android `MainActivity` also extends `FlutterActivity`. For `audio_service`, use `AudioServiceActivity` so the activity is wired for the audio service lifecycle/media controls.

## Apply these files to BookHutFlutterApp

1. `android/app/src/main/kotlin/com/example/bookhut/MainActivity.kt` -> use the version in this folder.
2. `android/app/src/main/AndroidManifest.xml` -> use the version in this folder. It includes the `tools` namespace because the service/receiver currently use `tools:ignore`.
3. `lib/main.dart` -> use the version in this folder.

## Also keep the caller fixes already required in `lib/screens/audio_player_screen.dart`

`setNewBook` and `setNewBookWithChapters` use named parameters. The three call sites must pass `title:`, `artist:`, `artUrl:`, `audioUrl:` / `chapterUrls:` / `chapterTitles:`.

## Build

```powershell
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

If the app still remains on the launch screen, capture Android logcat while launching; the next step is to identify exactly which initialization call is blocking/failing rather than changing the player blindly.
