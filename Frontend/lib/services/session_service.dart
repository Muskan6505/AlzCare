import 'dart:convert';

import 'package:universal_html/html.dart' as html;

import '../models/models.dart';

class SessionService {
  SessionService._();

  static const _storageKey = 'alzcare_session_v1';

  static AppSession? loadSession() {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppSession.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppSession.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}

    return null;
  }

  static void saveSession(AppSession session) {
    html.window.localStorage[_storageKey] = jsonEncode(session.toJson());
  }

  static void clearSession() {
    html.window.localStorage.remove(_storageKey);
  }
}
