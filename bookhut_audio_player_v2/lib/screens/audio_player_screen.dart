import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
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

      if (mounted) {
        setState(() => _isInitializing = false);
      }

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
      final duration = Duration(milliseconds: (seconds * 1000).round());

      await _player.seek(
        duration,
        index: widget.book.chapters.isEmpty ? null : safeIndex,
      );
      _currentChapterIndex = safeIndex;
    } catch (e) {
      // Backward compatibility with the old double-based format.
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

  void _showBookmarksList() {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هنوز نشان‌گذاری برای این کتاب ثبت نشده است.')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SizedBox(
        height: 360,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'نشان‌گذاری‌های من',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final mark = _bookmarks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark, color: _kPrimaryGreen),
                      title: Text(
                        mark['chapter']?.toString() ?? 'نشان‌گذاری ${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'زمان: ${mark['timeStr'] ?? ''}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          setState(() => _bookmarks.removeAt(index));
                          await _persistBookmarks();
                          if (sheetContext.mounted && _bookmarks.isEmpty) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                      onTap: () async {
                        final chapterIndex = (mark['index'] as num?)?.toInt() ?? 0;
                        final seconds = (mark['time'] as num?)?.toInt() ?? 0;
                        Navigator.pop(sheetContext);
                        await _player.seek(
                          Duration(seconds: seconds),
                          index: widget.book.chapters.isNotEmpty
                              ? chapterIndex.clamp(0, widget.book.chapters.length - 1)
                              : null,
                        );
                        await _player.play();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareCurrentTime() async {
    final text = '''📖 در حال گوش دادن به کتاب «${widget.book.title}»
نویسنده: ${widget.book.author}
⏳ زمان: ${_formatDuration(_currentPosition)}''';

    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _downloadAndPlayOffline() async {
    final sourceUrl = widget.book.audioUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برای این کتاب فایل صوتی مستقیمی وجود ندارد.')),
        );
      }
      return;
    }

    final path = await _getStoragePath();
    final file = File('$path/audio_${_safeName(widget.book.title)}.mp3');

    if (await file.exists()) {
      await _handler.setNewBook(
        title: widget.book.title,
        artist: widget.book.author,
        artUrl: widget.book.coverImage,
        audioUrl: file.path,
      );
      await _player.play();
      _showMessage('پخش آفلاین آغاز شد!', _kPrimaryGreen);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      await Dio().download(
        sourceUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      await _handler.setNewBook(
        title: widget.book.title,
        artist: widget.book.author,
        artUrl: widget.book.coverImage,
        audioUrl: file.path,
      );
      await _player.play();

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1;
        });
      }
      _showMessage('کتاب با موفقیت دانلود و آفلاین شد!', _kPrimaryGreen);
    } catch (e) {
      if (await file.exists()) {
        await file.delete();
      }
      if (mounted) setState(() => _isDownloading = false);
      _showMessage('خطا در دانلود: $e', Colors.red);
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  Future<void> _seekTo(Duration position) async {
    final duration = _totalDuration;
    final safe = duration > Duration.zero
        ? Duration(
            milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds),
          )
        : Duration.zero;
    await _player.seek(safe);
  }

  Future<void> _skipForward() async {
    await _seekTo(_currentPosition + const Duration(seconds: 10));
  }

  Future<void> _skipBackward() async {
    await _seekTo(_currentPosition - const Duration(seconds: 10));
  }

  Future<void> _toggleLoopMode() async {
    final next = _loopMode == LoopMode.off ? LoopMode.one : LoopMode.off;
    setState(() => _loopMode = next);
    await _player.setLoopMode(next);
  }

  Future<void> _changeSpeed(double speed) async {
    setState(() => _speed = speed);
    await _player.setSpeed(speed);
  }

  void _openSleepTimerBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تایمر خواب',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildSleepButton(15, '۱۵ دقیقه'),
                _buildSleepButton(30, '۳۰ دقیقه'),
                _buildSleepButton(60, '۶۰ دقیقه'),
                _buildSleepButton(90, '۹۰ دقیقه'),
              ],
            ),
            if (_sleepDuration != null)
              TextButton(
                onPressed: () {
                  _sleepTimer?.cancel();
                  setState(() => _sleepDuration = null);
                  Navigator.pop(context);
                },
                child: const Text('لغو تایمر', style: TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepButton(int minutes, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _sleepDuration?.inMinutes == minutes
            ? _kPrimaryGreen
            : Colors.grey.shade800,
      ),
      onPressed: () {
        _sleepTimer?.cancel();
        setState(() => _sleepDuration = Duration(minutes: minutes));
        _sleepTimer = Timer(Duration(minutes: minutes), () async {
          await _player.pause();
          if (mounted) setState(() => _sleepDuration = null);
        });
        Navigator.pop(context);
      },
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  void _openAudioSettingsBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تنظیمات صوتی',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.white54),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0,
                      max: 1,
                      onChanged: (value) {
                        setModalState(() => _volume = value);
                        _player.setVolume(value);
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white54),
                ],
              ),
              Row(
                children: [
                  const Text('زیر', style: TextStyle(color: Colors.white54)),
                  Expanded(
                    child: Slider(
                      value: _pitch,
                      min: 0.5,
                      max: 2,
                      divisions: 15,
                      label: _pitch.toStringAsFixed(1),
                      onChanged: (value) {
                        setModalState(() => _pitch = value);
                        _player.setPitch(value);
                      },
                    ),
                  ),
                  const Text('بم', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChaptersBottomSheet() {
    if (widget.book.chapters.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: 360,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'فهرست فصل‌ها',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.book.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = widget.book.chapters[index];
                  return ListTile(
                    selected: index == _currentChapterIndex,
                    selectedTileColor: _kPrimaryGreen.withOpacity(0.08),
                    leading: Icon(
                      index == _currentChapterIndex
                          ? Icons.play_circle
                          : Icons.play_circle_outline,
                      color: _kPrimaryGreen,
                    ),
                    title: Text(
                      chapter.title,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _player.seek(Duration.zero, index: index);
                      await _player.play();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    unawaited(_saveProgress());
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _indexSub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDarkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark, color: Colors.white70),
            onPressed: _showBookmarksList,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white70),
            onPressed: _shareCurrentTime,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 30,
                        offset: Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _cachedCoverPath.isNotEmpty
                        ? Image.file(File(_cachedCoverPath), fit: BoxFit.cover)
                        : Image.network(
                            widget.book.coverImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Colors.grey,
                              child: Icon(Icons.book, color: Colors.white54, size: 64),
                            ),
                          ),
                  ),
                ),
                const Spacer(),
                Text(
                  widget.book.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.book.chapters.isNotEmpty
                      ? '${widget.book.author} • فصل ${_currentChapterIndex + 1}'
                      : widget.book.author,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_currentPosition), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    Text(_formatDuration(_totalDuration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: _kPrimaryGreen,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: _kPrimaryGreen,
                    overlayColor: _kPrimaryGreen.withOpacity(0.2),
                  ),
                  child: Slider(
                    min: 0,
                    max: _totalDuration.inMilliseconds > 0
                        ? _totalDuration.inMilliseconds.toDouble()
                        : 1,
                    value: _totalDuration.inMilliseconds > 0
                        ? _currentPosition.inMilliseconds
                            .clamp(0, _totalDuration.inMilliseconds)
                            .toDouble()
                        : 0,
                    onChanged: (value) => _seekTo(Duration(milliseconds: value.round())),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: _toggleLoopMode,
                      icon: Icon(
                        _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                        color: _loopMode == LoopMode.one ? _kPrimaryGreen : Colors.white70,
                      ),
                    ),
                    _buildControlButton(icon: Icons.replay_10, onTap: _skipBackward),
                    _buildControlButton(
                      icon: _isInitializing
                          ? Icons.hourglass_empty
                          : (_isPlaying ? Icons.pause : Icons.play_arrow),
                      onTap: _isInitializing ? () {} : _togglePlayPause,
                      isMain: true,
                    ),
                    _buildControlButton(icon: Icons.forward_10, onTap: _skipForward),
                    IconButton(
                      onPressed: _openAudioSettingsBottomSheet,
                      icon: const Icon(Icons.equalizer, color: Colors.white70),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _isDownloading ? null : _downloadAndPlayOffline,
                        child: _isDownloading
                            ? SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0 ? _downloadProgress : null,
                                  color: _kPrimaryGreen,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download, color: Colors.white54),
                      ),
                      PopupMenuButton<double>(
                        icon: const Icon(Icons.speed, color: Colors.white54),
                        onSelected: _changeSpeed,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 0.5, child: Text('۰.۵x')),
                          PopupMenuItem(value: 0.75, child: Text('۰.۷۵x')),
                          PopupMenuItem(value: 1.0, child: Text('۱.۰x (عادی)')),
                          PopupMenuItem(value: 1.25, child: Text('۱.۲۵x')),
                          PopupMenuItem(value: 1.5, child: Text('۱.۵x')),
                          PopupMenuItem(value: 2.0, child: Text('۲.۰x')),
                        ],
                      ),
                      GestureDetector(
                        onTap: _openSleepTimerBottomSheet,
                        child: Icon(
                          _sleepDuration != null ? Icons.bedtime : Icons.bedtime_outlined,
                          color: _sleepDuration != null ? _kPrimaryGreen : Colors.white54,
                        ),
                      ),
                      GestureDetector(
                        onTap: _openChaptersBottomSheet,
                        child: const Icon(Icons.format_list_bulleted, color: Colors.white54),
                      ),
                      GestureDetector(
                        onTap: _saveBookmark,
                        child: const Icon(Icons.bookmark_add, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isMain = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isMain ? 72 : 56,
        height: isMain ? 72 : 56,
        decoration: BoxDecoration(
          color: isMain ? _kPrimaryGreen : Colors.transparent,
          shape: BoxShape.circle,
          border: isMain ? null : Border.all(color: Colors.white24, width: 1.5),
          boxShadow: isMain
              ? const [BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 8))]
              : null,
        ),
        child: Icon(
          icon,
          color: isMain ? Colors.white : Colors.white70,
          size: isMain ? 36 : 28,
        ),
      ),
    );
  }
}
