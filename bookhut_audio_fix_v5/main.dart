// v5 bootstrap reference for BookHut.
// Goal: do not let AudioService.init() block the entire Flutter UI.
// IMPORTANT: this requires AudioPlayerScreen to await audioHandlerFuture before
// assigning _handler/_player. Do not replace BookHut's main.dart without that
// corresponding screen change.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'screens/main_screen.dart';

late final Future<AudioPlayerHandler> audioHandlerFuture;

Future<AudioPlayerHandler> _initAudioService() async {
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

  // Start initialization but do not await it before runApp().
  // The player screen awaits the same Future when it needs audio.
  audioHandlerFuture = _initAudioService();

  runApp(const MyApp());
}

class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  AudioPlayerHandler() {
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= player.sequence.length) {
        return;
      }
      final tag = player.sequence[index].tag;
      if (tag is MediaItem) mediaItem.add(tag);
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) => PlaybackState(
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
  Future<void> skipToNext() => player.hasNext ? player.seekToNext() : Future.value();
  @override
  Future<void> skipToPrevious() => player.hasPrevious ? player.seekToPrevious() : Future.value();

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
    await player.setAudioSource(_sourceFor(audioUrl, item));
    mediaItem.add(item);
  }

  Future<void> setNewBookWithChapters({
    required String title,
    required String artist,
    required String artUrl,
    required List<String> chapterUrls,
    required List<String> chapterTitles,
  }) async {
    if (chapterUrls.isEmpty) throw ArgumentError('chapterUrls cannot be empty');
    if (chapterUrls.length != chapterTitles.length) {
      throw ArgumentError('chapterUrls and chapterTitles must have the same length');
    }
    await player.stop();
    final items = List.generate(
      chapterUrls.length,
      (i) => MediaItem(
        id: chapterUrls[i],
        album: title,
        title: chapterTitles[i],
        artist: artist,
        artUri: Uri.tryParse(artUrl),
      ),
    );
    final sources = List<AudioSource>.generate(
      chapterUrls.length,
      (i) => _sourceFor(chapterUrls[i], items[i]),
    );
    queue.add(items);
    await player.setAudioSources(sources);
    mediaItem.add(items.first);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BookHut',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      );
}
