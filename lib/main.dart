import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:focusbell/services/alarm_service.dart';
import 'package:focusbell/services/focus_timer_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'services/app_controller.dart';
import 'services/standalone_note_controller.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/reminder_service.dart';
import 'services/geofence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // Orientation lock is synchronous — fine to await
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Render the app immediately — spinner shows while services boot
  runApp(const FocusBellApp());

  // Everything runs in background after first frame
  _initServices();
}

/// All service initialization — fully fire-and-forget.
/// Nothing here can block the UI.
void _initServices() {
  Future(() async {
    await _safe('NotificationService',
        () => NotificationService.instance.initialize());
    await _safe('ReminderService',
        () => ReminderService.instance.init());  
    await _safe('AppController',
        () => AppController.instance.boot());
    await _safe('StandaloneNoteController',
        () => StandaloneNoteController.instance.boot());
    await _safe('FocusTimerService',
        () => FocusTimerService.instance.init());
    await _safe('AlarmService',
        () => AlarmService.instance.init());
    // GeofenceService is already booted inside ReminderService.init(),
    // but calling it here as well is safe (init() is idempotent) and
    // ensures the poll timer starts even if ReminderService had no reminders.
    await _safe('GeofenceService',
        () => GeofenceService.instance.init());
  });
}

/// Runs [fn] with a 10s timeout, logs failures, never throws.
Future<void> _safe(String name, Future<void> Function() fn) async {
  try {
    await fn().timeout(
      const Duration(seconds: 10),
      onTimeout: () => debugPrint('[main] $name timed out after 10s'),
    );
    debugPrint('[main] $name ✓');
  } catch (e, st) {
    debugPrint('[main] $name failed: $e\n$st');
  }
}

class FocusBellApp extends StatelessWidget {
  const FocusBellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AlarmService.navigatorKey,
      title: 'FocusBell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          surface: Color(0xFF111111),
          onSurface: Colors.white,
        ),
        textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
      ),
      home: WithForegroundTask(child: const _Loader()),
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppController.instance,
      builder: (context, _) {
        final ctrl = AppController.instance;

        // Still booting
        if (ctrl.loading) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
                strokeWidth: 2,
              ),
            ),
          );
        }

        // Boot failed
        if (ctrl.bootError != null) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️ Startup failed',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Text(ctrl.bootError.toString(),
                          style: const TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.5)),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                        'Copy the error above and share it for debugging.',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }

        // Ready
        return const HomeScreen();
      },
    );
  }
}