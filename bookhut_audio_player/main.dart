// Fixed BookHut audio service handler based on the supplied project files.

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'screens/main_screen.dart';

late AudioPlayerHandler globalAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    globalAudioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.bookhut.audio',
        androidNotificationChannelName: 'پخش کتاب صوتی',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e, stackTrace) {
    debugPrint('خطای راه‌اندازی سرویس صدا: $e');
    debugPrintStack(stackTrace: stackTrace);
    rethrow;
  }

  runApp(const MyApp());
}

class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer player = AudioPlayer();

  AudioPlayerHandler() {
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= player.sequence.length) {
        return;
      }

      final tag = player.sequence[index].tag;
      if (tag is MediaItem) {
        mediaItem.add(tag);
      }
    });
  }

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
      },
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
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() => player.stop();

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

  Future<AudioSource> _sourceFor(String audioUrl, MediaItem item) async {
    if (audioUrl.startsWith('file://')) {
      return AudioSource.file(
        Uri.parse(audioUrl).toFilePath(),
        tag: item,
      );
    }

    return AudioSource.uri(
      Uri.parse(audioUrl),
      tag: item,
    );
  }

  Future<void> setNewBook(
    String title,
    String artist,
    String artUrl,
    String audioUrl,
  ) async {
    final item = MediaItem(
      id: audioUrl,
      title: title,
      artist: artist,
      artUri: Uri.tryParse(artUrl),
    );

    final source = await _sourceFor(audioUrl, item);
    queue.add([item]);
    await player.setAudioSource(source);
    mediaItem.add(item);
  }

  Future<void> setNewBookWithChapters(
    String title,
    String artist,
    String artUrl,
    List<String> chapterUrls,
    List<String> chapterTitles,
  ) async {
    if (chapterUrls.isEmpty) {
      throw ArgumentError('chapterUrls cannot be empty');
    }

    if (chapterUrls.length != chapterTitles.length) {
      throw ArgumentError(
        'chapterUrls and chapterTitles must have the same length',
      );
    }

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

    final sources = <AudioSource>[];
    for (var index = 0; index < chapterUrls.length; index++) {
      sources.add(await _sourceFor(chapterUrls[index], items[index]));
    }

    queue.add(items);
    await player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
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
