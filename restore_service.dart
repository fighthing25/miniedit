import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RestoreException implements Exception {
  RestoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RestoreResult {
  const RestoreResult({
    required this.previewPath,
    required this.savedPath,
    required this.inDownloads,
  });

  /// Working copy in the app cache. Always readable, so playback uses this.
  final String previewPath;

  /// Where the exported file ended up.
  final String savedPath;

  /// False when /Download was not writable and the app folder was used instead.
  final bool inDownloads;
}

class RestoreService {
  RestoreService._();

  static const _downloadDir = '/storage/emulated/0/Download';

  // nr = reduction in dB, nf = assumed noise floor in dB, tn = keep tracking the noise.
  // Raise nr (up to ~30) for heavier hiss; too high gives watery artifacts.
  static const _filters = 'afftdn=nr=12:nf=-30:tn=1,loudnorm=I=-14:TP=-1.0';

  /// Equivalent shell command:
  /// ffmpeg -y -i in.mp3 -map 0:a:0 -map_metadata -1 -fflags +bitexact -flags:a +bitexact \
  ///   -af "afftdn=nr=12:nf=-30:tn=1,loudnorm=I=-14:TP=-1.0" \
  ///   -acodec pcm_s16le -ar 44100 -ac 2 out.wav
  static Future<RestoreResult> restore(
    String inputPath, {
    void Function(double progress)? onProgress,
  }) async {
    final cache = await getTemporaryDirectory();
    final safeName = p
        .basenameWithoutExtension(inputPath)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final outName =
        'restored_${safeName}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final workPath = p.join(cache.path, outName);

    final totalMs = await _durationMs(inputPath);

    // An argument list (not one string) means paths with spaces need no quoting.
    final args = <String>[
      '-y',
      '-i', inputPath,
      '-map', '0:a:0', // first audio stream only; cover art is a video stream and is dropped
      '-map_metadata', '-1', // wipe all global tags
      '-fflags', '+bitexact', // without these two, FFmpeg writes its own
      '-flags:a', '+bitexact', // "Lavf" encoder tag into the WAV
      '-af', _filters,
      '-acodec', 'pcm_s16le',
      '-ar', '44100',
      '-ac', '2',
      workPath,
    ];

    final done = Completer<void>();
    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final rc = await session.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          done.complete();
        } else {
          final logs = await session.getAllLogsAsString() ?? '';
          final tail =
              logs.length > 400 ? logs.substring(logs.length - 400) : logs;
          done.completeError(
            RestoreException('FFmpeg failed (code ${rc?.getValue()}).\n$tail'),
          );
        }
      },
      null,
      (stats) {
        if (totalMs > 0) {
          onProgress?.call((stats.getTime() / totalMs).clamp(0.0, 1.0).toDouble());
        }
      },
    );
    await done.future;

    final out = File(workPath);
    if (!await out.exists() || await out.length() == 0) {
      throw RestoreException('FFmpeg finished but produced no audio.');
    }
    return _export(workPath, outName);
  }

  static Future<double> _durationMs(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final seconds =
        double.tryParse(session.getMediaInformation()?.getDuration() ?? '');
    return (seconds ?? 0) * 1000;
  }

  static Future<RestoreResult> _export(String workPath, String name) async {
    // Android 13+ always reports Permission.storage as denied by design.
    // Creating our own new file in /Download still works there, so a denial is not fatal.
    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
    }

    try {
      final dir = Directory(_downloadDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final saved = await File(workPath).copy(p.join(dir.path, name));
      return RestoreResult(
        previewPath: workPath,
        savedPath: saved.path,
        inDownloads: true,
      );
    } on FileSystemException {
      // Scoped storage blocked the write (seen on Android 10). Keep the user's work.
      final fallback = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final saved = await File(workPath).copy(p.join(fallback.path, name));
      return RestoreResult(
        previewPath: workPath,
        savedPath: saved.path,
        inDownloads: false,
      );
    }
  }
}
