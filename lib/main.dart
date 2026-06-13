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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await NotificationService.instance.initialize();
  await ReminderService.instance.init();
  await AppController.instance.boot().timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      debugPrint('[main] AppController.boot() timed out after 10s');
    },
  );

  try {
    await StandaloneNoteController.instance.boot();
  } catch (e, stack) {
    debugPrint('[StandaloneNoteController] boot() failed:\n$e\n$stack');
  }

  await FocusTimerService.instance.init();

  runApp(const FocusBellApp());

  // Init alarm AFTER runApp so the navigator is mounted and ready.
  // AlarmScreen pushes via navigatorKey — which only works once
  // MaterialApp has built.
  AlarmService.instance.init().catchError((e, st) {
    debugPrint('[AlarmService] init failed: $e\n$st');
  });
}

class FocusBellApp extends StatelessWidget {
  const FocusBellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AlarmService.navigatorKey, // required for AlarmScreen push
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

        // ── Still loading ────────────────────────────────────
        if (ctrl.loading) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
                strokeWidth: 2,
              ),
            ),
          );
        }

        // ── Boot failed — show error so we can diagnose ──────
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
                    const Text(
                      '⚠️ Startup failed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                      child: Text(
                        ctrl.bootError.toString(),
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Copy the error above and share it for debugging.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ── Ready ────────────────────────────────────────────
        return const HomeScreen();
      },
    );
  }
}