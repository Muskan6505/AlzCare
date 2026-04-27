// flutter-app/lib/services/audio_service.dart

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
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;

  // ───────────────── RECORDING ─────────────────

  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
        path: '', // web → blob
      );

      _isRecording = true;
      return true;
    } catch (e) {
      print("Recording start error: $e");
      return false;
    }
  }

  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || path.isEmpty) return null;

      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
      }

      return null;
    } catch (e) {
      _isRecording = false;
      print("Recording stop error: $e");
      return null;
    }
  }

  bool get isRecording => _isRecording;

  // ───────────────── PLAYBACK ─────────────────

  /// 🔥 FIXED: Prevent stale audio (cache + buffer issue)
  Future<void> playFromUrl(String audioPath) async {
    if (audioPath.trim().isEmpty) return;

    try {
      final baseUrl = audioPath.startsWith('http')
          ? audioPath
          : '${AppConfig.pythonBaseUrl}$audioPath';

      // 🔥 CRITICAL: cache-busting query param
      final url = "$baseUrl${baseUrl.contains('?') ? '&' : '?'}cb=${DateTime.now().millisecondsSinceEpoch}";

      print("🎧 Playing URL: $url");

      // 🔥 VERY IMPORTANT: clear previous buffer
      await _player.stop();

      // Optional but safer on web
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));

      await _player.play();
    } catch (e) {
      print("Audio playback error: $e");
    }
  }

  /// Best method (no caching issues at all)
  Future<void> playFromBytes(Uint8List bytes) async {
    try {
      await _player.stop();

      final source = _BytesAudioSource(bytes);
      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      print("Bytes playback error: $e");
    }
  }

  Future<void> stop() async => await _player.stop();
  Future<void> pause() async => await _player.pause();

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}

// ───────────────── BYTE AUDIO SOURCE ─────────────────

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes) : super(tag: 'BytesAudioSource');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;

    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}