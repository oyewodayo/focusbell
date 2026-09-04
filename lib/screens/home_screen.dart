// home_screen.dart — FULL REPLACEMENT

import 'package:flutter/material.dart';
import 'package:focusbell/screens/notes_screen.dart';
import 'package:focusbell/screens/reminders_screen.dart';
import 'package:focusbell/widgets/note_lock_button.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:flutter/cupertino.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../services/focus_timer_service.dart';
import '../services/notification_service.dart';
import '../utils/app_toast.dart';
import '../widgets/analytics_sheet.dart';
import '../widgets/focus_live_banner.dart';
import '../widgets/focus_timer_sheet.dart';
import '../widgets/project_view_sheet.dart';
import '../widgets/projects_bottom_sheet.dart';
import '../widgets/settings_bottom_sheet.dart';
import '../services/continuity_service.dart';
import '../widgets/continuity_card.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl     = AppController.instance;
  final _timerSvc = FocusTimerService.instance;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContinuityService.instance.addListener(_onContinuityChanged);
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _requestPerms();

    if (_timerSvc.pendingFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _timerSvc.clearPendingFinished();
        final active = _ctrl.activeProject;
        if (active != null) showFocusTimerSheet(context, active);
      });
    }
  }

  Future<void> _requestPerms() async {
    await NotificationService.instance.requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ContinuityService.instance.removeListener(_onContinuityChanged);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ContinuityService.instance.onAppResumed();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive) {
      ContinuityService.instance.onAppPaused();
    }
  }

  void _onContinuityChanged() {
    if (mounted) setState(() {});
  }

  void _resumeFocusSession() {
    final active = _ctrl.activeProject;
    if (active != null) {
      showFocusTimerSheet(context, active);
    } else {
      setState(() {});
    }
  }

  void _openProjects() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProjectsBottomSheet(),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SettingsBottomSheet(),
    );
  }

  void _openAnalytics() => showAnalyticsSheet(context, _ctrl.projects);

  void _openNotes() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotesScreen()),
    );
  }

  void _openReminders() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemindersScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb       = Theme.of(context).fb;
    final snapshot = ContinuityService.instance.pendingSnapshot;

    return Scaffold(
      backgroundColor: fb.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            if (snapshot != null)
              ContinuityCard(
                snapshot:        snapshot,
                onDismiss:       ContinuityService.instance.dismissSnapshot,
                onResumeSession: snapshot.activeSessionProject != null
                    ? _resumeFocusSession
                    : null,
              ),
            Expanded(
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (context, _) {
                  final active   = _ctrl.activeProject;
                  final settings = _ctrl.settings;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                // ── Top bar ──────────────────────
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 20, 24, 0),
                                  child: Row(
                                    children: [
                                      Text(
                                        'FocusBell',
                                        style: TextStyle(
                                          color:         fb.isDark?fb.onSurfaceFaint:fb.onSurface,
                                          fontSize:      13,
                                          fontWeight:    FontWeight.w600,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      _NotifBadge(
                                        enabled:
                                            settings.notificationsEnabled,
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _openSettings,
                                        child: Container(
                                          padding: const EdgeInsets.all(7),                                          
                                          child: Icon(
                                            CupertinoIcons.settings,
                                            color: fb.isDark?fb.onSurfaceFaint:fb.onSurface,
                                            size:  24,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Main content ─────────────────
                                Flexible(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 28, vertical: 16),
                                      child: active == null
                                          ? _EmptyState(onAdd: _openProjects)
                                          : _ActiveCard(
                                              project:   active,
                                              pulseAnim: _pulse,
                                            ),
                                    ),
                                  ),
                                ),

                                // ── Bottom bar ───────────────────
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 8, 24, 20),
                                  child: Row(
                                    children: [
                                      _IconOnlyButton(
                                        icon:  CupertinoIcons.square_pencil,
                                        size:  28,
                                        onTap: _openNotes,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ActionButton(
                                          icon:  CupertinoIcons.layers,
                                          label: 'Projects',
                                          onTap: _openProjects,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ActionButton(
                                          icon:  CupertinoIcons.chart_bar,
                                          label: 'Analytics',
                                          onTap: _openAnalytics,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _IconOnlyButton(
                                        icon:  CupertinoIcons.bell,
                                        size:  28,
                                        onTap: _openReminders,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActiveCard
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveCard extends StatelessWidget {
  final Project           project;
  final Animation<double> pulseAnim;
  const _ActiveCard({required this.project, required this.pulseAnim});

  void _openViewSheet(BuildContext context) {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectViewSheet(project: project),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb              = Theme.of(context).fb;
    final p               = project.priority;
    final incompleteTasks = project.tasks
        .where((t) => t.status != TaskStatus.completed)
        .length;
    final hasTasks     = project.tasks.isNotEmpty;
    final overdueTasks = project.tasks.where((t) => t.isOverdue).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Priority orb ───────────────────────────────────────
        ScaleTransition(
          scale: pulseAnim,
          child: Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
            shape:  BoxShape.circle,
            color:  p.bgColor(fb.isDark),
            border: Border.all(
                color: p.color.withValues(alpha: 0.5), width: 2),
            boxShadow: [
                BoxShadow(
                // In light mode, reduce glow spread — it bleeds on white bg
                color:        p.color.withValues(alpha: fb.isDark ? 0.30 : 0.18),
                blurRadius:   fb.isDark ? 24 : 16,
                spreadRadius: fb.isDark ? 4  : 1,
                ),
            ],
            ),
            child: Center(
              child: Text(p.emoji,
                  style: const TextStyle(fontSize: 30)),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // ── Priority pill ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color:        p.bgColor(fb.isDark),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.color.withValues(alpha: 0.35)),
          ),
          child: Text(
            '${p.label.toUpperCase()} PRIORITY',
            style: TextStyle(
              color:         p.color,
              fontSize:      11,
              fontWeight:    FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Project name ───────────────────────────────────────
        Text(
          project.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            color:         fb.onSurface,
            fontSize:      28,
            fontWeight:    FontWeight.w800,
            letterSpacing: -0.8,
            height:        1.2,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          "Stay locked in. You've got this.",
          style: TextStyle(color: fb.onSurfaceFaint, fontSize: 14),
        ),
        const SizedBox(height: 16),

        // ── Action chips ───────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CardIconButton(
                onTap: () => _openViewSheet(context),
                icon:  Icons.open_in_new_rounded,
                label: 'View',
                color: const Color(0xFF64D2FF),
              ),
              const SizedBox(width: 5),
              _TrayButton(
                icon:  Icons.sticky_note_2_outlined,
                label: 'Note',
                color: const Color(0xFF0A84FF),
                onTap: () async {
                  final canOpen =
                      await tryOpenLockedNote(context, project);
                  if (!canOpen || !context.mounted) return;
                  showProjectNoteSheet(context, project: project);
                },
              ),
              if (hasTasks) ...[
                const SizedBox(width: 5),
                _CardIconButton(
                  onTap: () => _openViewSheet(context),
                  icon:  Icons.checklist_rounded,
                  label: incompleteTasks == 0
                      ? 'All done'
                      : '$incompleteTasks left',
                  color: incompleteTasks == 0
                      ? const Color(0xFF34C759)
                      : const Color(0xFFFFD60A),
                ),
              ],
              if (overdueTasks > 0) ...[
                const SizedBox(width: 5),
                _CardIconButton(
                  onTap: () => _openViewSheet(context),
                  icon:  Icons.warning_amber_rounded,
                  label: '$overdueTasks overdue',
                  color: const Color(0xFFFF3B30),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        FocusSessionButton(project: project),
        const SizedBox(height: 32),

        _PrioritySwitcher(project: project),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TrayButton
// ─────────────────────────────────────────────────────────────────────────────

class _TrayButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _TrayButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).fb.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          // Low alpha reads fine tinting a near-black surface, but washes
          // out almost to nothing over a light one — bump it up there.
          color:        color.withValues(alpha: isDark ? 0.12 : 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: color.withValues(alpha: isDark ? 0.3 : 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color:      color,
                    fontSize:   12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CardIconButton
// ─────────────────────────────────────────────────────────────────────────────

class _CardIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData     icon;
  final String       label;
  final Color        color;

  const _CardIconButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).fb.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          // Low alpha reads fine tinting a near-black surface, but washes
          // out almost to nothing over a light one — bump it up there.
          color:        color.withValues(alpha: isDark ? 0.10 : 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: color.withValues(alpha: isDark ? 0.28 : 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color:      color,
                    fontSize:   12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PrioritySwitcher
// ─────────────────────────────────────────────────────────────────────────────

class _PrioritySwitcher extends StatelessWidget {
  final Project project;
  const _PrioritySwitcher({required this.project});

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Column(
      children: [
        Text(
          'ADJUST PRIORITY',
          style: TextStyle(
            color:         fb.onSurfaceFaint,
            fontSize:      10,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: Priority.values.map((p) {
            final selected = p == project.priority;
            return GestureDetector(
              onTap: () async {
                if (selected) return;
                await AppController.instance
                    .updateProjectPriority(project.id, p);
                if (!context.mounted) return;
                AppToast.show(
                  context,
                  msg:             '${p.emoji} Priority → ${p.label}',
                  backgroundColor: p.bgColor(fb.isDark),
                  textColor:       p.color,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin:   const EdgeInsets.symmetric(horizontal: 4),
                width:    selected ? 48 : 36,
                height:   36,
                decoration: BoxDecoration(
                  color: selected ? p.bgColor(fb.isDark) : fb.surfaceVar,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? p.color.withValues(alpha: 0.6)
                        : fb.border,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(p.emoji,
                      style: TextStyle(fontSize: selected ? 18 : 14)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🔔', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 20),
        Text(
          'No active project',
          style: TextStyle(
            color:         fb.onSurface,
            fontSize:      22,
            fontWeight:    FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add a project and set it active\nto start your focus reminders.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: fb.onSurfaceDim, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 13),
            decoration: BoxDecoration(
            color:        fb.surfaceVar,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: fb.border),
            boxShadow: fb.isDark ? null : [
                BoxShadow(
                color:       Colors.black.withValues(alpha: 0.05),
                blurRadius:  6,
                offset:      const Offset(0, 2),
                ),
            ],
            ),
            child: Text(
              '+ Add Project',
              style: TextStyle(
                color:      fb.onSurface,
                fontSize:   15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionButton
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final int?         count;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fb     = Theme.of(context).fb;
    // In light mode step the icon/label up from dim → surface (near-black)
    final fgColor = fb.isDark ? fb.onSurfaceDim : fb.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:        fb.card,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: fb.border),
          boxShadow: fb.isDark ? null : [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fgColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color:      fgColor,
                fontSize:   14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color:        fb.border,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color:      fgColor,
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconOnlyButton extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final double       size;

  const _IconOnlyButton({
    required this.icon,
    this.size = 22.0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fb      = Theme.of(context).fb;
    // Light mode: use onSurface (near-black) so the icons are clearly visible
    final color   = fb.isDark ? fb.onSurfaceFaint : fb.onSurfaceDim;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:   Icon(icon, color: color, size: size),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IconOnlyButton
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// _NotifBadge
// ─────────────────────────────────────────────────────────────────────────────

class _NotifBadge extends StatelessWidget {
  final bool enabled;
  const _NotifBadge({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final fb      = Theme.of(context).fb;
    const green   = Color(0xFF4CAF50);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // Active: a tinted green surface. Inactive: neutral surface.
        color: enabled
            ? green.withValues(alpha: 0.12)
            : fb.surfaceVar,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? green.withValues(alpha: 0.35)
              : fb.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size:  12,
            color: enabled ? green : fb.onSurfaceFaint,
          ),
          const SizedBox(width: 4),
          Text(
            enabled ? 'ON' : 'OFF',
            style: TextStyle(
              color:         enabled ? green : fb.onSurfaceFaint,
              fontSize:      10,
              fontWeight:    FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point (kept here to avoid breaking existing call sites)
// ─────────────────────────────────────────────────────────────────────────────

void showProjectNoteSheet(BuildContext context, {required Project project}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ProjectNoteSheet(project: project),
  ));
}