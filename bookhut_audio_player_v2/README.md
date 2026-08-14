# BookHut Audio Player — proposed fix

This directory contains a proposed fix based on the current `AviranHub/BookHutFlutterApp` main branch.

**Important:** the original `BookHutFlutterApp` repository is not modified by this work.

Reviewed source files:
- `lib/main.dart`
- `lib/screens/audio_player_screen.dart`
- `lib/models/book.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `pubspec.yaml`

Main fixes:
- initialize `audio_service` centrally instead of creating an unrelated `AudioPlayer` in the screen
- use `MediaItem` metadata for single files and chapters
- support next/previous chapter from `audio_service`
- synchronize current chapter metadata
- fix resume condition
- fix bookmark persistence by using JSON instead of `List.toString()`
- use `AudioSource.file()` for local files
- add proper Android media playback service/receiver configuration
- keep Java/Kotlin target at 17

The original project remains untouched.