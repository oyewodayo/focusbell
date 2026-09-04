import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:focusbell/services/alarm_service.dart';
import 'package:focusbell/services/focus_timer_service.dart';
import 'package:focusbell/services/continuity_service.dart';
import 'package:focusbell/services/geofence_service.dart';
import 'package:focusbell/services/reminder_group_service.dart';
import 'package:focusbell/services/saved_places_service.dart';
import 'package:focusbell/theme/app_theme.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'services/app_controller.dart';
import 'services/standalone_note_controller.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/reminder_service.dart';
import 'models/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FocusBellApp());
  _initServices();
}

/// All service initialization — fully fire-and-forget.
void _initServices() {
  Future(() async {
    await _safe('ContinuityService',
        () => ContinuityService.instance.init());

    // Cold start counts as "returning" for continuity purposes —
    // didChangeAppLifecycleState only fires on paused→resumed
    // transitions, never on a fresh process launch, so we trigger
    // it manually here once init() has loaded _lastActiveAt.
    await _safe('ContinuityService.onAppResumed',
        () => ContinuityService.instance.onAppResumed());

    await _safe('NotificationService',
        () => NotificationService.instance.initialize());

    // ReminderService.init() boots GeofenceService internally after
    // loading reminders, so geofences are registered on first poll.
    await _safe('ReminderGroupService',
        () => ReminderGroupService.instance.init());

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

    await _safe('SavedPlacesService',
        () => SavedPlacesService.instance.init());

    // GeofenceService.init() is idempotent — safe to call again here.
    // This ensures the poll timer starts even when ReminderService
    // skips it (e.g. on a cold boot with no reminders yet).
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
    return ListenableBuilder(
      listenable: AppController.instance,
      builder: (ctx, _) {
        final settings = AppController.instance.settings;
        final mode     = settings.themeMode;

        // For AppThemeMode.auto we resolve now and pick a concrete theme.
        // For system/dark/light we let MaterialApp handle it normally.
        final platformBrightness =
            MediaQuery.platformBrightnessOf(ctx);
        final resolved = mode.resolve(platformBrightness);

        return MaterialApp(
          navigatorKey:             AlarmService.navigatorKey,
          title:                    'FocusBell',
          debugShowCheckedModeBanner: false,

          // Light + dark themes always provided; themeMode selects between them.
          theme:      AppTheme.light,
          darkTheme:  AppTheme.dark,

          // auto resolves to a concrete ThemeMode; system delegates to OS.
          themeMode: mode == AppThemeMode.auto
              ? (resolved == Brightness.dark ? ThemeMode.dark : ThemeMode.light)
              : mode.toFlutterThemeMode(),

          home: WithForegroundTask(child: const _Loader()),
        );
      },
    );
  }
}
class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> with TickerProviderStateMixin {
  static const _fullText = 'Keep your attention where it belongs.';
  static const _typeIntervalMs = 38;

  // How many characters are currently visible
  int _visibleChars = 0;
  Timer? _typeTimer;

  // Drives the rainbow wave sweep (loops forever)
  late final AnimationController _waveController;

  // Rainbow palette — cycles through these hues
  static const _hues = [
    Color(0xFF64B5F6), // blue
    Color(0xFF81C784), // green
    Color(0xFFFFD54F), // amber
    Color(0xFFFF8A65), // orange
    Color(0xFFBA68C8), // purple
    Color(0xFF4DD0E1), // cyan
    Color(0xFF64B5F6), // back to blue for seamless loop
  ];

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Start typewriter
    _typeTimer = Timer.periodic(
      const Duration(milliseconds: _typeIntervalMs),
      (t) {
        if (!mounted) { t.cancel(); return; }
        if (_visibleChars < _fullText.length) {
          setState(() => _visibleChars++);
        } else {
          t.cancel();
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  /// Interpolate through the _hues palette given a 0..1 position.
  Color _paletteColor(double t) {
    t = t.clamp(0.0, 1.0);
    final scaled = t * (_hues.length - 1);
    final i = scaled.floor().clamp(0, _hues.length - 2);
    return Color.lerp(_hues[i], _hues[i + 1], scaled - i)!;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppController.instance,
      builder: (context, _) {
        final ctrl = AppController.instance;
        final fb   = Theme.of(context).fb;

        if (ctrl.loading) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.blueAccent,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 40),
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, _) {
                      final wave = _waveController.value; // 0..1
                      final chars = _fullText.characters.toList();
                      final visible = _visibleChars.clamp(0, chars.length);

                      // Build one Text span per character
                      final spans = <InlineSpan>[];
                      for (int i = 0; i < visible; i++) {
                        // Position of this char within the full string (0..1)
                        final charPos = i / (_fullText.length - 1);
                        // Wave offset: shift charPos by wave progress,
                        // then wrap around so color sweeps continuously.
                        final wavePos = (charPos - wave * 1.6 + 1.6) % 1.0;
                        final color = _paletteColor(wavePos);
                        spans.add(TextSpan(
                          text: chars[i],
                          style: TextStyle(color: color),
                        ));
                      }

                      return Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.4,
                            height: 1.5,
                          ),
                          children: spans,
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }

        if (ctrl.bootError != null) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️ Startup failed',
                        style: TextStyle(
                            color: fb.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: fb.dangerBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: fb.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(ctrl.bootError.toString(),
                          style: TextStyle(
                              color: fb.danger,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.5)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                        'Copy the error above and share it for debugging.',
                        style: TextStyle(color: fb.onSurfaceFaint, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }

        return const HomeScreen();
      },
    );
  }
}