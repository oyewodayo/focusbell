import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../services/notification_service.dart';
import '../utils/app_toast.dart';
import '../widgets/project_view_sheet.dart';
import '../widgets/projects_bottom_sheet.dart';
import '../widgets/settings_bottom_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = AppController.instance;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _requestPerms();
  }

  Future<void> _requestPerms() async {
    await NotificationService.instance.requestPermissions();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _openProjects() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProjectsBottomSheet(),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SettingsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          final active = _ctrl.activeProject;
          final settings = _ctrl.settings;

          return SafeArea(
            child: Column(
              children: [
                // ── Top bar ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      const Text(
                        'FocusBell',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      _NotifBadge(enabled: settings.notificationsEnabled),
                    ],
                  ),
                ),

                // ── Main content ─────────────────────────────
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: active == null
                          ? _EmptyState(onAdd: _openProjects)
                          : _ActiveCard(project: active, pulseAnim: _pulse),
                    ),
                  ),
                ),

                // ── Bottom actions ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.layers_outlined,
                          label: 'Projects',
                          count: _ctrl.projects.length,
                          onTap: _openProjects,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.tune_rounded,
                          label: 'Settings',
                          onTap: _openSettings,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Active project card ───────────────────────────────────────────

class _ActiveCard extends StatelessWidget {
  final Project project;
  final Animation<double> pulseAnim;

  const _ActiveCard({required this.project, required this.pulseAnim});

  void _openViewSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectViewSheet(project: project),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = project.priority;
    final incompleteTasks = project.tasks
        .where((t) => t.status != TaskStatus.completed)
        .length;
    final hasTasks = project.tasks.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: pulseAnim,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.bgColor,
              border: Border.all(
                color: p.color.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: p.color.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(p.emoji, style: const TextStyle(fontSize: 30)),
            ),
          ),
        ),
        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: p.bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.color.withValues(alpha: 0.35)),
          ),
          child: Text(
            '${p.label.toUpperCase()} PRIORITY',
            style: TextStyle(
              color: p.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          project.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          "Stay locked in. You've got this.",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),

        // ── View + Task count row ─────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // View button
            _CardIconButton(
              onTap: () => _openViewSheet(context),
              icon: Icons.open_in_new_rounded,
              label: 'View',
              color: const Color(0xFF64D2FF),
            ),

            // Task count pill — only shown when there are tasks
            if (hasTasks) ...[
              const SizedBox(width: 10),
              _CardIconButton(
                onTap: () => _openViewSheet(context),
                icon: Icons.checklist_rounded,
                label: incompleteTasks == 0
                    ? 'All done'
                    : '$incompleteTasks left',
                color: incompleteTasks == 0
                    ? const Color(0xFF34C759)
                    : const Color(0xFFFFD60A),
              ),
            ],
          ],
        ),

        const SizedBox(height: 32),
        _PrioritySwitcher(project: project),
      ],
    );
  }
}

// ── Small icon+label pill used on the active card ─────────────────

class _CardIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;

  const _CardIconButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick priority switcher ───────────────────────────────────────

class _PrioritySwitcher extends StatelessWidget {
  final Project project;
  const _PrioritySwitcher({required this.project});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'ADJUST PRIORITY',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontSize: 10,
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
                await AppController.instance.updateProjectPriority(
                  project.id,
                  p,
                );
                if (!context.mounted) return;
                AppToast.show(
                  context,
                  msg: '${p.emoji} Priority → ${p.label}',
                  backgroundColor: p.bgColor,
                  textColor: p.color,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: selected ? 48 : 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? p.bgColor : const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? p.color.withValues(alpha: 0.6)
                        : Colors.white10,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    p.emoji,
                    style: TextStyle(fontSize: selected ? 18 : 14),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🔔', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 20),
        const Text(
          'No active project',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add a project and set it active\nto start your focus reminders.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              '+ Add Project',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bottom action buttons ─────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
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

// ── Notification badge ────────────────────────────────────────────

class _NotifBadge extends StatelessWidget {
  final bool enabled;
  const _NotifBadge({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF1A2E1A) : const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? const Color(0xFF4CAF50).withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 12,
            color: enabled ? const Color(0xFF4CAF50) : Colors.white24,
          ),
          const SizedBox(width: 4),
          Text(
            enabled ? 'ON' : 'OFF',
            style: TextStyle(
              color: enabled ? const Color(0xFF4CAF50) : Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
