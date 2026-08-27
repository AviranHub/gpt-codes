# Required AudioPlayerScreen v6 integration

`lib/screens/audio_player_screen.dart` currently declares:

```dart
late final AudioPlayerHandler _handler;
late final AudioPlayer _player;
```

and imports `../main.dart`.

Change the startup so the screen waits for the same handler Future created by v6:

```dart
bool _audioReady = false;
String? _audioInitError;

@override
void initState() {
  super.initState();
  _initAudio();
}

Future<void> _initAudio() async {
  try {
    final handler = await audioHandlerFuture;
    if (!mounted) return;

    _handler = handler;
    _player = handler.player;

    // KEEP the rest of the existing _initAudio body here, starting from
    // the first operation that previously assumed `_handler`/`_player`
    // were already initialized. Do not call the old global handler.
    setState(() => _audioReady = true);
  } catch (e) {
    if (!mounted) return;
    setState(() => _audioInitError = e.toString());
  }
}
```

If the existing `_initAudio()` already contains the book/chapter loading logic, split it into two methods rather than duplicating it:

```dart
Future<void> _initAudio() async {
  try {
    final handler = await audioHandlerFuture;
    if (!mounted) return;
    _handler = handler;
    _player = handler.player;
    await _loadBookIntoPlayer();
    if (mounted) setState(() => _audioReady = true);
  } catch (e) {
    if (mounted) setState(() => _audioInitError = e.toString());
  }
}
```

Move the existing code that resolves the local/remote audio URL, calls `setNewBook`, `setNewBookWithChapters`, subscribes to player streams, etc. into `_loadBookIntoPlayer()`.

At the top of `build()`, show a small loading/error state until `_audioReady` is true:

```dart
if (_audioInitError != null) {
  return Scaffold(
    body: Center(child: Text('خطا در راه‌اندازی پخش: $_audioInitError')),
  );
}
if (!_audioReady) {
  return const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}
```

The three already-fixed calls must remain named-argument calls:

```dart
await _handler.setNewBook(
  title: widget.book.title,
  artist: widget.book.author,
  artUrl: widget.book.coverImage,
  audioUrl: filePath,
);

await _handler.setNewBookWithChapters(
  title: widget.book.title,
  artist: widget.book.author,
  artUrl: widget.book.coverImage,
  chapterUrls: resolvedUrls,
  chapterTitles: chapterTitles,
);
```

and the other `setNewBook` call likewise uses `title`, `artist`, `artUrl`, and `audioUrl`.

## Why this is required

v6 intentionally starts `AudioService.init()` without awaiting it in `main()`. Therefore every direct read of the old `globalAudioHandler` must be removed/replaced with `await audioHandlerFuture` inside the player screen.
