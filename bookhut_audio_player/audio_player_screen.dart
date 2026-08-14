// Corrected BookHut AudioPlayerScreen based on the supplied project file.
// Key fixes: JSON bookmark persistence, resume restoration, stream subscription cleanup,
// and local-file playback compatibility with the central AudioPlayerHandler.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
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

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  LoopMode _loopMode = LoopMode.off;
  double _speed = 1.0;

  Timer? _sleepTimer;
  Duration? _sleepDuration;
  double _volume = 1.0;
  double _pitch = 1.0;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _cachedCoverPath = '';

  List<Map<String, dynamic>> _bookmarks = [];
  bool _isFirstLoad = true;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _handler = globalAudioHandler;
    _player = _handler.player;

    _cacheCoverImage();
    _loadBookmarks();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initAudio();
      await _restoreProgress();
      _isFirstLoad = false;
    });
  }

  Future<String> _getStoragePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _cacheCoverImage() async {
    try {
      final path = await _getStoragePath();
      final safeFileName =
          'cover_${widget.book.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.jpg';
      final File file = File('$path/$safeFileName');
      if (await file.exists()) {
        if (mounted) setState(() => _cachedCoverPath = file.path);
      } else {
        final dio = Dio();
        await dio.download(widget.book.coverImage, file.path);
        if (mounted) setState(() => _cachedCoverPath = file.path);
      }
    } catch (e) {
      debugPrint('خطا در ذخیره جلد: $e');
    }
  }

  Future<String> _getAudioUrl() async {
    final path = await _getStoragePath();
    final safeFileName =
        'audio_${widget.book.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.mp3';
    final File file = File('$path/$safeFileName');
    if (await file.exists()) return 'file://${file.path}';
    return widget.book.audioUrl ??
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPos = prefs.getDouble('resume_${widget.book.title}');

    if (savedPos == null || savedPos <= 0) return;

    try {
      await _player.seek(
        Duration(milliseconds: (savedPos * 1000).round()),
      );
    } catch (e) {
      debugPrint('خطا در بازیابی موقعیت: $e');
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      'resume_${widget.book.title}',
      _currentPosition.inSeconds.toDouble(),
    );
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bookmarks_${widget.book.title}';
    final data = prefs.getString(key);

    if (data == null || data.isEmpty) return;

    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        final bookmarks = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (mounted) {
          setState(() {
            _bookmarks = bookmarks;
          });
        }
      }
    } catch (e) {
      debugPrint('خطا در خواندن نشان‌گذاری‌ها: $e');
    }
  }

  Future<void> _persistBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bookmarks_${widget.book.title}',
      jsonEncode(_bookmarks),
    );
  }

  Future<void> _saveBookmark() async {
    final newMark = {
      'time': _currentPosition.inSeconds,
      'timeStr': _formatDuration(_currentPosition),
    };

    final exists = _bookmarks.any((m) => m['time'] == newMark['time']);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('این زمان قبلاً نشان‌گذاری شده است!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _bookmarks.add(newMark));
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
        const SnackBar(content: Text('هنوز نشان‌گذاری ثبت نشده است.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 300,
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
                    leading: const Icon(
                      Icons.bookmark,
                      color: _kPrimaryGreen,
                    ),
                    title: Text(
                      'نشان‌گذاری ${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'زمان: ${mark['timeStr']}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        setState(() => _bookmarks.removeAt(index));
                        await _persistBookmarks();
                      },
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _player.seek(
                        Duration(seconds: (mark['time'] as num).toInt()),
                      );
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

  Future<void> _shareCurrentTime() async {
    final String shareText = '''
📖 در حال گوش دادن به کتاب "${widget.book.title}"
نوشته شده توسط "${widget.book.author}"
⏳ زمان دقیق من: ${_formatDuration(_currentPosition)}
''';
    await Share.share(shareText);
  }

  Future<void> _downloadAndPlayOffline() async {
    final String audioUrl =
        widget.book.audioUrl ??
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
    final path = await _getStoragePath();
    final safeFileName =
        'audio_${widget.book.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.mp3';
    final File file = File('$path/$safeFileName');

    if (await file.exists()) {
      await _player.stop();
      await _handler.setNewBook(
        widget.book.title,
        widget.book.author,
        widget.book.coverImage,
        'file://${file.path}',
      );
      await _player.play();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('پخش آفلاین آغاز شد!'),
            backgroundColor: _kPrimaryGreen,
          ),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final dio = Dio();
      await dio.download(
        audioUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (!await file.exists()) {
        throw Exception('فایل دانلود شده پیدا نشد.');
      }

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
        });
      }

      await _player.stop();
      await _handler.setNewBook(
        widget.book.title,
        widget.book.author,
        widget.book.coverImage,
        'file://${file.path}',
      );
      await _player.play();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('کتاب با موفقیت دانلود شد!'),
            backgroundColor: _kPrimaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دانلود: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initAudio() async {
    try {
      await _player.stop();
      final url = await _getAudioUrl();

      if (widget.book.chapters.isNotEmpty) {
        final chapterUrls = widget.book.chapters.map((c) => c.url).toList();
        final chapterTitles =
            widget.book.chapters.map((c) => c.title).toList();

        await _handler.setNewBookWithChapters(
          widget.book.title,
          widget.book.author,
          widget.book.coverImage,
          chapterUrls,
          chapterTitles,
        );
      } else {
        await _handler.setNewBook(
          widget.book.title,
          widget.book.author,
          widget.book.coverImage,
          url,
        );
      }

      try {
        await _player.setSpeed(_speed);
      } catch (_) {}
      try {
        await _player.setVolume(_volume);
      } catch (_) {}
      try {
        await _player.setPitch(_pitch);
      } catch (_) {}

      await _positionSub?.cancel();
      await _durationSub?.cancel();
      await _playerStateSub?.cancel();

      _positionSub = _player.positionStream.listen((position) {
        if (mounted) setState(() => _currentPosition = position);
      });

      _durationSub = _player.durationStream.listen((duration) {
        if (mounted && duration != null) {
          setState(() => _totalDuration = duration);
        }
      });

      _playerStateSub = _player.playerStateStream.listen((playerState) {
        if (mounted) setState(() => _isPlaying = playerState.playing);
      });

      if (mounted) await _player.play();
    } catch (e) {
      debugPrint('خطا در لود فایل صوتی: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پخش فایل صوتی: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _seekTo(Duration position) => _player.seek(position);

  void _skipForward() {
    final newPos = _currentPosition + const Duration(seconds: 10);
    _seekTo(newPos > _totalDuration ? _totalDuration : newPos);
  }

  void _skipBackward() {
    final newPos = _currentPosition - const Duration(seconds: 10);
    _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void _toggleLoopMode() {
    setState(() {
      _loopMode =
          _loopMode == LoopMode.off ? LoopMode.one : LoopMode.off;
    });
    _player.setLoopMode(_loopMode);
  }

  void _changeSpeed(double newSpeed) async {
    setState(() => _speed = newSpeed);
    try {
      await _player.setSpeed(_speed);
    } catch (_) {}
  }

  void _openSleepTimerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تایمر خواب',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                child: const Text(
                  'لغو تایمر',
                  style: TextStyle(color: Colors.redAccent),
                ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {
        setState(() {
          _sleepTimer?.cancel();
          _sleepDuration = Duration(minutes: minutes);
          _sleepTimer = Timer(_sleepDuration!, () {
            if (mounted) {
              _player.pause();
              setState(() => _sleepDuration = null);
            }
          });
        });
        Navigator.pop(context);
      },
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  void _openAudioSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تنظیمات صوتی',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.volume_down, color: Colors.white54),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: _kPrimaryGreen,
                        inactiveColor: Colors.grey.shade800,
                        onChanged: (val) {
                          setModalState(() => _volume = val);
                          _player.setVolume(val);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up, color: Colors.white54),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'بم',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: _pitch,
                        min: 0.5,
                        max: 2.0,
                        activeColor: _kPrimaryGreen,
                        inactiveColor: Colors.grey.shade800,
                        divisions: 15,
                        label: _pitch.toStringAsFixed(1),
                        onChanged: (val) {
                          setModalState(() => _pitch = val);
                          _player.setPitch(val);
                        },
                      ),
                    ),
                    const Text(
                      'زیر',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openChaptersBottomSheet() {
    if (widget.book.chapters.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 300,
        child: Column(
          children: [
            const Text(
              'فهرست فصل‌ها',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.book.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = widget.book.chapters[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.play_circle_outline,
                      color: _kPrimaryGreen,
                    ),
                    title: Text(
                      chapter.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        await _player.seek(Duration.zero, index: index);
                        await _player.play();
                      } catch (e) {
                        debugPrint('خطا در تغییر فصل: $e');
                      }
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
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _saveProgress();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
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
        title: null,
        centerTitle: true,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.8),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _cachedCoverPath.isNotEmpty &&
                          File(_cachedCoverPath).existsSync()
                      ? Image.file(
                          File(_cachedCoverPath),
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          widget.book.coverImage,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              Container(color: Colors.grey),
                        ),
                ),
              ),
              const Spacer(flex: 1),
              Text(
                widget.book.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.book.author,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(flex: 2),
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_currentPosition),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(_totalDuration),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: _kPrimaryGreen,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: _kPrimaryGreen,
                      overlayColor: _kPrimaryGreen.withOpacity(0.2),
                    ),
                    child: Slider(
                      min: 0,
                      max: _totalDuration.inSeconds.toDouble() > 0
                          ? _totalDuration.inSeconds.toDouble()
                          : 1,
                      value: _totalDuration.inSeconds.toDouble() > 0
                          ? _currentPosition.inSeconds.toDouble().clamp(
                              0,
                              _totalDuration.inSeconds.toDouble(),
                            )
                          : 0,
                      onChanged: (value) =>
                          _seekTo(Duration(seconds: value.toInt())),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: _toggleLoopMode,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _loopMode == LoopMode.one
                            ? _kPrimaryGreen.withOpacity(0.2)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _loopMode == LoopMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: _loopMode == LoopMode.one
                            ? _kPrimaryGreen
                            : Colors.white70,
                        size: 22,
                      ),
                    ),
                  ),
                  _buildControlButton(
                    icon: Icons.replay_10,
                    onTap: _skipBackward,
                  ),
                  _buildControlButton(
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    onTap: _togglePlayPause,
                    isMain: true,
                  ),
                  _buildControlButton(
                    icon: Icons.forward_10,
                    onTap: _skipForward,
                  ),
                  GestureDetector(
                    onTap: _openAudioSettingsBottomSheet,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.equalizer,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
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
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(
                                  Icons.download,
                                  color: Colors.white54,
                                  size: 24,
                                ),
                                SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    value: _downloadProgress,
                                    color: _kPrimaryGreen,
                                    strokeWidth: 2,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                              ],
                            )
                          : const Icon(
                              Icons.download,
                              color: Colors.white54,
                              size: 24,
                            ),
                    ),
                    PopupMenuButton<double>(
                      icon: const Icon(
                        Icons.speed,
                        color: Colors.white54,
                        size: 24,
                      ),
                      onSelected: _changeSpeed,
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 0.5, child: Text('۰.۵x')),
                        PopupMenuItem(value: 0.75, child: Text('۰.۷۵x')),
                        PopupMenuItem(
                          value: 1.0,
                          child: Text('۱.۰x (عادی)'),
                        ),
                        PopupMenuItem(value: 1.25, child: Text('۱.۲۵x')),
                        PopupMenuItem(value: 1.5, child: Text('۱.۵x')),
                        PopupMenuItem(value: 2.0, child: Text('۲.۰x')),
                      ],
                    ),
                    GestureDetector(
                      onTap: _openSleepTimerBottomSheet,
                      child: Icon(
                        _sleepDuration != null
                            ? Icons.bedtime
                            : Icons.bedtime_outlined,
                        color: _sleepDuration != null
                            ? _kPrimaryGreen
                            : Colors.white54,
                        size: 24,
                      ),
                    ),
                    GestureDetector(
                      onTap: _openChaptersBottomSheet,
                      child: const Icon(
                        Icons.format_list_bulleted,
                        color: Colors.white54,
                        size: 24,
                      ),
                    ),
                    GestureDetector(
                      onTap: _saveBookmark,
                      child: const Icon(
                        Icons.bookmark_add,
                        color: Colors.white54,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 1),
            ],
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
          border: isMain
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
          boxShadow: isMain
              ? [
                  BoxShadow(
                    color: _kPrimaryGreen.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
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
