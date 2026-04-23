// flutter-app/lib/main.dart
// AlzCare Web — Flutter Web entry point.
// Runs in any modern browser via flutter build web.

import 'package:flutter/material.dart';

import '../../screens/patient_screen.dart';
import '../../screens/caregiver_screen.dart';
import '../../services/socket_service.dart';
import '../../widgets/shared_widgets.dart';

void main() {
  // Ensure Flutter web bindings are initialised
  WidgetsFlutterBinding.ensureInitialized();

  // Dispatch the flutter-first-frame event for the HTML loading overlay
  // (handled automatically by Flutter web engine)

  runApp(const AlzCareWebApp());
}

enum _AppMode { patient, caregiver }

class AlzCareWebApp extends StatefulWidget {
  const AlzCareWebApp({super.key});

  @override
  State<AlzCareWebApp> createState() => _AlzCareWebAppState();
}

class _AlzCareWebAppState extends State<AlzCareWebApp> {
  _AppMode _mode = _AppMode.patient;

  @override
  void dispose() {
    SocketService.instance.dispose();
    super.dispose();
  }

  void _switchMode() =>
      setState(() => _mode = _mode == _AppMode.patient
          ? _AppMode.caregiver
          : _AppMode.patient);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AlzCare AI',
        debugShowCheckedModeBanner: false,
        // Use URL strategy on web — removes the # from URLs
        // (requires flutter_web_plugins and url_strategy package for hash-free URLs)
        theme: _buildTheme(),
        home: _mode == _AppMode.patient
            ? PatientScreen(onSwitchMode: _switchMode)
            : CaregiverScreen(onSwitchMode: _switchMode),
      );

  ThemeData _buildTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary:   AlzColors.navy,
          secondary: AlzColors.ocean,
          surface:   AlzColors.warm,
          error:     AlzColors.red,
        ),
        scaffoldBackgroundColor: AlzColors.warm,
        // Web-friendly font stack
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          displayLarge:   TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AlzColors.textDark),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          titleLarge:     TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          bodyLarge:      TextStyle(fontSize: 18, height: 1.6),
          bodyMedium:     TextStyle(fontSize: 16, height: 1.5),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AlzColors.navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(120, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
