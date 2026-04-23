// flutter-app/lib/services/app_config.dart
// Server endpoints — update these to match your deployment.
// On web, the browser enforces CORS, so both services must set
// Access-Control-Allow-Origin appropriately (already configured in backends).

class AppConfig {
  AppConfig._();

  // ── Development (local) ─────────────────────────────────────────────────────
  static const String nodeBaseUrl   = 'http://localhost:4000';
  static const String pythonBaseUrl = 'http://localhost:8001';
  static const String socketUrl     = 'http://localhost:4000';

  // ── Production — replace with your domain / cloud IP ────────────────────────
  // static const String nodeBaseUrl   = 'https://api.alzcare.app';
  // static const String pythonBaseUrl = 'https://ai.alzcare.app';
  // static const String socketUrl     = 'https://api.alzcare.app';

  // Demo patient — replace with real auth in production
  static const String demoPatientId   = 'PATIENT_001';
  static const String demoCaregiverId = 'CAREGIVER_001';
}
