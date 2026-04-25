// flutter-app/lib/services/api_service.dart
// Web-compatible HTTP service.
// Key change from mobile: processMultimodal() accepts raw bytes (Uint8List)
// instead of a file path, because Flutter Web has no file system.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../services/app_config.dart';
import '../models/models.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  Future<PatientProfile?> fetchPatientProfile(String patientId) async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.nodeBaseUrl}/api/patients/$patientId'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return PatientProfile.fromJson(jsonDecode(resp.body));
      }
    } catch (_) {}
    return null;
  }

  Future<PatientProfile?> createPatientProfile({
    required String patientId,
    required String name,
    List<String> caregiverIds = const [],
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/patients'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_id': patientId,
          'name': name,
          'caregiver_ids': caregiverIds,
        }),
      );
      if (resp.statusCode == 201) {
        return fetchPatientProfile(patientId);
      }
    } catch (_) {}
    return null;
  }

  // ── Python pipeline ────────────────────────────────────────────────────────

  /// Upload WAV bytes for full multimodal pipeline.
  /// Web: sends bytes directly as multipart (no File needed).
  Future<MultimodalResult?> processMultimodal({
    required Uint8List audioBytes,
    required String patientId,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.pythonBaseUrl}/process-multimodal'),
      );
      request.fields['patient_id'] = patientId;
      request.files.add(
        http.MultipartFile.fromBytes(
          'audio',
          audioBytes,
          filename: 'audio.wav',
        ),
      );
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final body     = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        return MultimodalResult.fromJson(jsonDecode(body));
      }
    } catch (e) {
      throw Exception('Pipeline error: $e');
    }
    return null;
  }

  // ── Node.js — Reminders ────────────────────────────────────────────────────

  Future<List<Reminder>> fetchReminders(String patientId) async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders?patient_id=$patientId'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List)
            .map((j) => Reminder.fromJson(j))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> addReminder({
    required String patientId,
    required String task,
    required String time,
    required String frequency,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'patient_id': patientId, 'task': task, 'time': time, 'frequency': frequency}),
      );
      return resp.statusCode == 201;
    } catch (_) { return false; }
  }

  Future<bool> acknowledgeReminder({required String reminderId, required String patientId}) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders/$reminderId/ack?patient_id=$patientId'),
      );
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> snoozeReminder({
    required String reminderId,
    required String patientId,
    int minutes = 10,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders/$reminderId/snooze?patient_id=$patientId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'minutes': minutes}),
      );
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> dismissReminder({
    required String reminderId,
    required String patientId,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders/$reminderId/dismiss?patient_id=$patientId'),
      );
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> deleteReminder(String id, String patientId) async {
    try {
      final resp = await http.delete(
          Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders/$id?patient_id=$patientId'));
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> toggleReminder(String id, String patientId, String status) async {
    try {
      final resp = await http.patch(
        Uri.parse('${AppConfig.nodeBaseUrl}/api/reminders/$id?patient_id=$patientId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Node.js — Notes ────────────────────────────────────────────────────────

  Future<List<CaregiverNote>> fetchNotes(String patientId) async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.nodeBaseUrl}/api/notes?patient_id=$patientId&limit=30'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List)
            .map((j) => CaregiverNote.fromJson(j))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Node.js — Memories ─────────────────────────────────────────────────────

  Future<List<PatientMemory>> fetchMemories(String patientId) async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.nodeBaseUrl}/api/memories?patient_id=$patientId'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List)
            .map((j) => PatientMemory.fromJson(j))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Node.js — Distress Logs ────────────────────────────────────────────────

  Future<List<DistressEntry>> fetchDistressLogs(String patientId, {int limit = 50}) async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.nodeBaseUrl}/api/distress?patient_id=$patientId&limit=$limit'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List)
            .map((j) => DistressEntry.fromJson(j))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Python — Embed and store ───────────────────────────────────────────────

  Future<bool> embedAndStore({
    required String patientId,
    required String collection,
    required String text,
    List<String> tags = const [],
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.pythonBaseUrl}/embed-and-store'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_id': patientId, 'collection': collection,
          'content': text, 'note': text, 'tags': tags,
        }),
      );
      return resp.statusCode == 201;
    } catch (_) { return false; }
  }
}
