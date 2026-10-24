import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'restore_service.dart';

void main() => runApp(const RestorerApp());

// Deep ink-blue base with a warm amber accent (VU-meter glow); mint is reserved
// for the offline indicator so it reads as "safe" at a glance.
const _bg = Color(0xFF12141A);
const _surface = Color(0xFF1B1E26);
const _amber = Color(0xFFF2B84B);
const _mint = Color(0xFF6FD6B8);
const _muted = Color(0xFF9AA0AE);

class RestorerApp extends StatelessWidget {
  const RestorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Track Restorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _amber,
          brightness: Brightness.dark,
          surface: _surface,
        ),
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(backgroundColor: _bg, elevation: 0),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _original = AudioPlayer();
  final _restored = AudioPlayer();
  final _subs = <StreamSubscription<PlayerState>>[];

  String? _inputPath;
  RestoreResult? _result;
  bool _busy = false;
  bool _isError = false;
  double _progress = 0;
  String _status = 'Choose an MP3 or WAV to begin.';

  @override
  void initState() {
    super.initState();
    for (final player in [_original, _restored]) {
      _subs.add(player.onPlayerStateChanged.listen((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _original.dispose();
    _restored.dispose();
    super.dispose();
  }

  Future<void> _stopAll() async {
    await _original.stop();
    await _restored.stop();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    await _stopAll();
    setState(() {
      _inputPath = path;
      _result = null;
      _progress = 0;
      _isError = false;
      _status = 'Ready. Tap Restore and export.';
    });
  }

  Future<void> _process() async {
    final input = _inputPath;
    if (input == null || _busy) return;

    final stale = _result?.previewPath;
    await _stopAll();
    if (stale != null) File(stale).delete().ignore();

    setState(() {
      _busy = true;
      _result = null;
      _progress = 0;
      _isError = false;
      _status = 'Removing hiss and mastering to -14 LUFS...';
    });

    try {
      final r = await RestoreService.restore(
        input,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _progress = 1;
        _status = r.inDownloads
            ? 'Saved to Download/${p.basename(r.savedPath)}'
            : 'Download folder was not writable. Saved to the app folder:\n${r.savedPath}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _progress = 0;
          _status = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(AudioPlayer player, AudioPlayer other, String path) async {
    switch (player.state) {
      case PlayerState.playing:
        await player.pause();
      case PlayerState.paused:
        await other.pause();
        await player.resume();
      default:
        await other.pause();
        await player.play(DeviceFileSource(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final input = _inputPath;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Track Restorer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const _OfflineBadge(),
            const SizedBox(height: 16),
            _Panel(
              onTap: _busy ? null : _pick,
              child: Row(
                children: [
                  const Icon(Icons.library_music_outlined, size: 34, color: _amber),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          input == null ? 'Select a track' : p.basename(input),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          input == null ? 'MP3 or WAV from this device' : 'Tap to choose a different file',
                          style: text.bodySmall?.copyWith(color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.folder_open, color: _muted),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: input != null && !_busy ? _process : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Restore and export'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: _amber,
                foregroundColor: _bg,
              ),
            ),
            const SizedBox(height: 12),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _busy && _progress == 0 ? null : _progress,
                      minHeight: 8,
                      color: _amber,
                      backgroundColor: _bg,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    style: text.bodyMedium?.copyWith(
                      color: _isError ? Colors.redAccent : null,
                    ),
                  ),
                ],
              ),
            ),
            _PlayerTile(
              title: 'Original',
              playing: _original.state == PlayerState.playing,
              onPressed: input == null ? null : () => _toggle(_original, _restored, input),
            ),
            _PlayerTile(
              title: 'Restored',
              playing: _restored.state == PlayerState.playing,
              onPressed: result == null ? null : () => _toggle(_restored, _original, result.previewPath),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _mint.withValues(alpha: 0.10),
        border: Border.all(color: _mint.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: _mint),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Offline protection on', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text(
                  'Audio is processed on this phone. The app has no internet permission.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.title, required this.playing, required this.onPressed});

  final String title;
  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          IconButton.filled(
            onPressed: onPressed,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            style: IconButton.styleFrom(backgroundColor: _amber, foregroundColor: _bg),
          ),
        ],
      ),
    );
  }
}
