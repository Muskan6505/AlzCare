import 'package:flutter/material.dart';

import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/caregiver_screen.dart';
import 'screens/patient_screen.dart';
import 'services/session_service.dart';
import 'services/socket_service.dart';
import 'widgets/shared_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlzCareWebApp());
}

class AlzCareWebApp extends StatefulWidget {
  const AlzCareWebApp({super.key});

  @override
  State<AlzCareWebApp> createState() => _AlzCareWebAppState();
}

class _AlzCareWebAppState extends State<AlzCareWebApp> {
  AppSession? _session;

  @override
  void initState() {
    super.initState();
    _session = SessionService.loadSession();
  }

  @override
  void dispose() {
    SocketService.instance.dispose();
    super.dispose();
  }

  void _handleAuthenticated(AppSession session) {
    SessionService.saveSession(session);
    setState(() => _session = session);
  }

  void _handleSignOut() {
    SessionService.clearSession();
    SocketService.instance.disconnect();
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AlzCare AI',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: _session == null
            ? AuthScreen(onAuthenticated: _handleAuthenticated)
            : _session!.isCaregiver
                ? CaregiverScreen(
                    session: _session!,
                    onSignOut: _handleSignOut,
                  )
                : PatientScreen(
                    session: _session!,
                    onSignOut: _handleSignOut,
                  ),
      );

  ThemeData _buildTheme() {
    final typography = Typography.material2021(platform: TargetPlatform.windows);
    final textTheme = typography.black.copyWith(
      displayLarge: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: AlzColors.textDark,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AlzColors.textDark,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AlzColors.textDark,
      ),
      bodyLarge: const TextStyle(
        fontSize: 18,
        height: 1.6,
        color: AlzColors.textDark,
      ),
      bodyMedium: const TextStyle(
        fontSize: 16,
        height: 1.5,
        color: AlzColors.textDark,
      ),
    );

    return ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AlzColors.navy,
          secondary: AlzColors.ocean,
          surface: AlzColors.warm,
          error: AlzColors.red,
        ),
        scaffoldBackgroundColor: AlzColors.warm,
        typography: typography,
        textTheme: textTheme,
        primaryTextTheme: typography.white,
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
}
