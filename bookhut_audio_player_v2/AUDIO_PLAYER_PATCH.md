# BookHut Audio Player patch

Source reviewed from `AviranHub/BookHutFlutterApp` main branch. The source project was **not modified**.

## 1. Architecture change

The current screen creates its own `AudioPlayer`:

```dart
_player = AudioPlayer();
```

and the app's `main.dart` currently only runs `MyApp`. This means the screen player and `audio_service` are not the same playback engine.

The proposed version uses one `AudioPlayer` owned by `AudioPlayerHandler` and accessed through `globalAudioHandler.player`.

## 2. Resume bug

Current code checks:

```dart
if (savedPos != null && savedPos > 0 && !_isFirstLoad)
```

but `_restoreProgress()` is called before `_isFirstLoad` is changed to `false`. Therefore resume is skipped.

Replace with:

```dart
Future<void> _restoreProgress() async {
  final prefs = await SharedPreferences.getInstance();
  final savedPos = prefs.getDouble('resume_${widget.book.title}');

  if (savedPos == null || savedPos <= 0) return;

  try {
    await _player.seek(Duration(seconds: savedPos.round()));
  } catch (e) {
    debugPrint('خطا در بازیابی موقعیت: $e');
  }
}
```

The `_isFirstLoad` flag can then be removed.

## 3. Bookmark bug

The current code writes:

```dart
prefs.setString(key, _bookmarks.toString());
```

but reads the resulting string as if it were a List. That is a runtime type error.

Add:

```dart
import 'dart:convert';
```

Save:

```dart
await prefs.setString(key, jsonEncode(_bookmarks));
```

Load:

```dart
Future<void> _loadBookmarks() async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString('bookmarks_${widget.book.title}');

  if (data == null || data.isEmpty) return;

  try {
    final decoded = jsonDecode(data);
    if (decoded is! List) return;

    final bookmarks = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    if (mounted) {
      setState(() => _bookmarks = bookmarks);
    }
  } catch (e) {
    debugPrint('خطا در خواندن نشان‌گذاری‌ها: $e');
  }
}
```

The bookmark delete action must also use `jsonEncode(_bookmarks)`.

## 4. Chapters and lock-screen metadata

The current chapter source uses:

```dart
AudioSource.uri(Uri.parse(c.url), tag: c.title)
```

Use a `MediaItem` as the tag instead:

```dart
final item = MediaItem(
  id: chapter.url,
  album: widget.book.title,
  title: chapter.title,
  artist: widget.book.author,
  artUri: Uri.tryParse(widget.book.coverImage),
);

AudioSource.uri(
  Uri.parse(chapter.url),
  tag: item,
);
```

The handler listens to `currentIndexStream` and publishes the current `MediaItem`, so the notification/lock screen follows the active chapter.

## 5. Next / Previous

The notification exposes next/previous controls. The handler must implement:

```dart
@override
Future<void> skipToNext() async {
  if (player.hasNext) {
    await player.seekToNext();
  }
}

@override
Future<void> skipToPrevious() async {
  if (player.hasPrevious) {
    await player.seekToPrevious();
  }
}
```

The proposed `lib/main.dart` contains these methods.

## 6. Local files

Replace:

```dart
_player.setUrl('file://${file.path}');
```

with a local `AudioSource.file`:

```dart
await _player.setAudioSource(
  AudioSource.file(file.path, tag: mediaItem),
);
```

This is also handled by `_sourceFor()` in the proposed handler.

## 7. Stream subscriptions

The screen currently creates position/duration/player-state listeners without retaining their subscriptions.

Use fields such as:

```dart
StreamSubscription<Duration>? _positionSub;
StreamSubscription<Duration?>? _durationSub;
StreamSubscription<PlayerState>? _playerStateSub;
```

Assign the listeners to those fields and cancel them in `dispose()`.

## 8. Screen player instance

Remove:

```dart
_player = AudioPlayer();
```

and use:

```dart
_player = globalAudioHandler.player;
```

Do **not** dispose this player from the screen. The central audio handler owns it.

## 9. Initialization

Instead of configuring the screen-local player directly, build the source through the central handler. For chapters, call `setNewBookWithChapters`; for a single audio file, call `setNewBook`.

The screen should then subscribe to the central player's streams.

## 10. Android manifest

The current main manifest has media/storage/camera permissions but no audio-service declaration. Add:

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Inside `<application>` add:

```xml
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>

<receiver
    android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</receiver>
```

## 11. Java warning

The actual project already uses Java 17 and Kotlin JVM 17 in `android/app/build.gradle.kts`. No Java 8 downgrade is required.

If the build still prints `source value 8 is obsolete`, the warning is likely coming from another dependency/toolchain component rather than this app module.

## 12. Dependency note

The checked project currently declares `device_info_plus: ^10.1.0`, while the dependency list supplied separately by the user used `^13.2.0`. This patch does not silently change the project's dependency file. Upgrade dependencies only after confirming the installed Flutter/Dart toolchain is compatible.

## 13. Important integration note

`BookHutFlutterApp` contains a `Book` model with `chapters` and `audioUrl`. The proposed handler is designed around that model but does not modify the original model.

The original repository remains untouched throughout this patch.