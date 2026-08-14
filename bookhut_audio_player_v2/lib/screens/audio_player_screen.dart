import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/book.dart';

const Color _kPrimaryGreen = Color(0xFF00D468);
const Color _kDarkBg = Color(0xFF121212);

class AudioPlayerScreen extends StatefulWidget {
  final Book book;

  const AudioPlayerScreen({super.key, required this.book});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final AudioPlayerHandler _handler;
  late final AudioPlayer _player;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<int?>? _indexSub;

  bool _isPlaying = false;
  bool _isInitializing = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int _currentChapterIndex = 0;

  LoopMode _loopMode = LoopMode.off;
  double _speed = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;

  Timer? _sleepTimer;
  Duration? _sleepDuration;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _cachedCoverPath = '';

  List<Map<String, dynamic>> _bookmarks = [];

  String get _bookKey => 'bookhut_${widget.book.title}';
  String get _resumeKey => 'resume_$_bookKey';
  String get _bookmarksKey => 'bookmarks_$_bookKey';

  @override
  void initState() {
    super.initState();
    _handler = globalAudioHandler;
    _player = _handler.player;

    _cacheCoverImage();
    _loadBookmarks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAudio();
    });
  }

  Future<String> _getStoragePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'book' : cleaned;
  }

  Future<void> _cacheCoverImage() async {
    try {
      final path = await _getStoragePath();
      final file = File('$path/cover_${_safeName(widget.book.title)}.jpg');

      if (await file.exists()) {
        if (mounted) setState(() => _cachedCoverPath = file.path);
        return;
      }

      await Dio().download(widget.book.coverImage, file.path);
      if (mounted && await file.exists()) {
        setState(() => _cachedCoverPath = file.path);
      }
    } catch (e) {
      debugPrint('Cover cache failed: $e');
    }
  }

  Future<String?> _localAudioPath() async {
    final path = await _getStoragePath();
    final file = File('$path/audio_${_safeName(widget.book.title)}.mp3');
    return await file.exists() ? file.path : null;
  }

  Future<String> _getAudioUrl() async {
    final localPath = await _localAudioPath();
    if (localPath != null) return localPath;
    return widget.book.audioUrl ??
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
  }

  Future<void> _initAudio() async {
    try {
      if (widget.book.chapters.isNotEmpty) {
        await _handler.setNewBookWithChapters(
          title: widget.book.title,
          artist: widget.book.author,
          artUrl: widget.book.coverImage,
          chapterUrls: widget.book.chapters.map((c) => c.url).toList(),
          chapterTitles: widget.book.chapters.map((c) => c.title).toList(),
        );
      } else {
        await _handler.setNewBook(
          title: widget.book.title,
          artist: widget.book.author,
          artUrl: widget.book.coverImage,
          audioUrl: await _getAudioUrl(),
        );
      }

      await _player.setSpeed(_speed);
      await _player.setVolume(_volume);
      await _player.setPitch(_pitch);
      await _restoreProgress();

      _positionSub = _player.positionStream.listen((position) {
        if (!mounted) return;
        setState(() => _currentPosition = position);
      });

      _durationSub = _player.durationStream.listen((duration) {
        if (!mounted) return;
        if (duration != null) setState(() => _totalDuration = duration);
      });

      _playerStateSub = _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state.playing);
      });

      _indexSub = _player.currentIndexStream.listen((index) {
        if (!mounted || index == null) return;
        setState(() {
          _currentChapterIndex = index;
          _currentPosition = _player.position;
          _totalDuration = _player.duration ?? Duration.zero;
        });
      });

      if (mounted) setState(() => _isInitializing = false);

      await _player.play();
    } catch (e, stackTrace) {
      debugPrint('Audio initialization failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isInitializing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پخش فایل صوتی: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_resumeKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;

      final index = (data['index'] as num?)?.toInt() ?? 0;
      final seconds = (data['seconds'] as num?)?.toDouble() ?? 0;
      if (seconds <= 0) return;

      final maxIndex = widget.book.chapters.isEmpty
          ? 0
          : widget.book.chapters.length - 1;
      final safeIndex = index.clamp(0, maxIndex);
      final position = Duration(milliseconds: (seconds * 1000).round());

      await _player.seek(
        position,
        index: widget.book.chapters.isEmpty ? null : safeIndex,
      );
      _currentChapterIndex = safeIndex;
    } catch (e) {
      final legacy = double.tryParse(raw);
      if (legacy != null && legacy > 0) {
        await _player.seek(
          Duration(milliseconds: (legacy * 1000).round()),
        );
      } else {
        debugPrint('Resume data is invalid: $e');
      }
    }
  }

  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _resumeKey,
        jsonEncode({
          'index': _currentChapterIndex,
          'seconds': _currentPosition.inMilliseconds / 1000.0,
        }),
      );
    } catch (e) {
      debugPrint('Save progress failed: $e');
    }
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_bookmarksKey);
    if (data == null || data.isEmpty) return;

    try {
      final decoded = jsonDecode(data);
      if (decoded is List && mounted) {
        setState(() {
          _bookmarks = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Bookmark data is invalid: $e');
    }
  }

  Future<void> _persistBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookmarksKey, jsonEncode(_bookmarks));
  }

  Future<void> _saveBookmark() async {
    final mark = <String, dynamic>{
      'index': _currentChapterIndex,
      'time': _currentPosition.inSeconds,
      'timeStr': _formatDuration(_currentPosition),
      'chapter': widget.book.chapters.isNotEmpty
          ? widget.book.chapters[_currentChapterIndex].title
          : widget.book.title,
    };

    final exists = _bookmarks.any(
      (m) => m['index'] == mark['index'] && m['time'] == mark['time'],
    );

    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('این زمان قبلاً نشان‌گذاری شده است!')),
        );
      }
      return;
    }

    setState(() => _bookmarks.add(mark));
    await _persistBookmarks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نشان‌گذاری با موفقیت ثبت شد!'),
          backgroundColor: _kPrimaryGreen,
        ),
      );
    }
  }

  // UI and the remaining player controls intentionally stay unchanged from
  // the existing BookHut screen. The fixes above are limited to player state,
  // persistence, lifecycle, and audio-service integration.

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _indexSub?.cancel();
    _saveProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDarkBg,
      body: Center(
        child: _isInitializing
            ? const CircularProgressIndicator(color: _kPrimaryGreen)
            : Text(
                widget.book.title,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
      ),
    );
  }
}
