import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'screens/main_screen.dart';

/// The UI must not depend on AudioService initialization completing during
/// application bootstrap. AudioPlayerScreen awaits this future when needed.
late final Future<AudioPlayerHandler> audioHandlerFuture;

Future<AudioPlayerHandler> _initAudioService() {
  return AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bookhut.audio',
      androidNotificationChannelName: 'پخش کتاب صوتی',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start initialization without making the entire Flutter UI wait for it.
  audioHandlerFuture = _initAudioService();

  runApp(const MyApp());
}

class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler() {
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= player.sequence.length) return;
      final tag = player.sequence[index].tag;
      if (tag is MediaItem) mediaItem.add(tag);
    });
  }

  final AudioPlayer player = AudioPlayer();

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: player.currentIndex,
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (player.hasNext) await player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.hasPrevious) await player.seekToPrevious();
  }

  AudioSource _sourceFor(String url, MediaItem item) {
    if (url.startsWith('file://')) {
      return AudioSource.file(Uri.parse(url).toFilePath(), tag: item);
    }
    return AudioSource.uri(Uri.parse(url), tag: item);
  }

  Future<void> setNewBook({
    required String title,
    required String artist,
    required String artUrl,
    required String audioUrl,
  }) async {
    await player.stop();
    final item = MediaItem(
      id: audioUrl,
      title: title,
      artist: artist,
      artUri: Uri.tryParse(artUrl),
    );
    queue.add([item]);
    await player.setAudioSource(
      _sourceFor(audioUrl, item),
      preload: true,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Audio source loading timed out',
      ),
    );
    mediaItem.add(item);
  }

  Future<void> setNewBookWithChapters({
    required String title,
    required String artist,
    required String artUrl,
    required List<String> chapterUrls,
    required List<String> chapterTitles,
  }) async {
    if (chapterUrls.isEmpty) {
      throw ArgumentError('chapterUrls cannot be empty');
    }
    if (chapterUrls.length != chapterTitles.length) {
      throw ArgumentError(
        'chapterUrls and chapterTitles must have the same length',
      );
    }

    await player.stop();

    final items = List.generate(
      chapterUrls.length,
      (index) => MediaItem(
        id: chapterUrls[index],
        album: title,
        title: chapterTitles[index],
        artist: artist,
        artUri: Uri.tryParse(artUrl),
      ),
    );

    final sources = List<AudioSource>.generate(
      chapterUrls.length,
      (index) => _sourceFor(chapterUrls[index], items[index]),
    );

    queue.add(items);
    await player.setAudioSources(sources, preload: true).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Audio playlist loading timed out',
      ),
    );
    mediaItem.add(items.first);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookHut',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
