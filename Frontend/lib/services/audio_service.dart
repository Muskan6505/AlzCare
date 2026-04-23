// flutter-app/lib/services/audio_service.dart
// Web-compatible audio handling using the 'record' and 'just_audio' packages.
//
// On Web:
//   record   → uses browser MediaRecorder API (no permission_handler needed;
//               browser will show its own mic permission prompt automatically)
//   just_audio → uses Web Audio API; can play from URL directly
//
// This file replaces all path_provider + File I/O usage from the mobile version.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../services/app_config.dart';

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer   _player   = AudioPlayer();

  bool _isRecording = false;

  // ── Recording ─────────────────────────────────────────────────────────────

  /// Start recording. On web, this triggers the browser mic permission prompt.
  /// Returns true if recording started successfully.
  Future<bool> startRecording() async {
    try {
      // On web: record package uses MediaRecorder API — no permission_handler needed
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      // Web records to a Blob (in-memory); path is null on web
      await _recorder.start(
        RecordConfig(
          encoder:    AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate:    128000,
        ),
        path: '', // empty path → web uses in-memory Blob
      );
      _isRecording = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop recording and return raw WAV bytes (web returns Blob bytes directly).
  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;
    try {
      // On web, stop() returns the path to a Blob URL; we read the Blob bytes
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || path.isEmpty) return null;

      if (kIsWeb) {
        // Web: path is a blob: URL — fetch its bytes
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) return response.bodyBytes;
        return null;
      } else {
        // Fallback for non-web (should not reach here in web-only build)
        return null;
      }
    } catch (_) {
      _isRecording = false;
      return null;
    }
  }

  bool get isRecording => _isRecording;

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Play TTS audio reply from the Python pipeline by URL.
  Future<void> playFromUrl(String audioPath) async {
    if (audioPath.trim().isEmpty) return;
    try {
      final url = audioPath.startsWith('http')
          ? audioPath
          : '${AppConfig.pythonBaseUrl}$audioPath';

      // just_audio uses Web Audio API on web — setUrl works natively
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {}
  }

  /// Play audio from raw bytes (Blob URL approach for web)
  Future<void> playFromBytes(Uint8List bytes) async {
    try {
      // On web: create an object URL from bytes and stream it
      final source = _BytesAudioSource(bytes);
      await _player.setAudioSource(source);
      await _player.play();
    } catch (_) {}
  }

  Future<void> stop()  async => await _player.stop();
  Future<void> pause() async => await _player.pause();

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}

/// Custom AudioSource that serves bytes via a StreamAudioSource.
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes) : super(tag: 'BytesAudioSource');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end   ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength:   _bytes.length,
      contentLength:  end - start,
      offset:         start,
      stream:         Stream.value(_bytes.sublist(start, end)),
      contentType:    'audio/wav',
    );
  }
}
