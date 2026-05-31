import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';
import 'project_add_dialog.dart';
import 'project_edit_sheet.dart';
import 'project_view_sheet.dart';

// ── Sort mode ─────────────────────────────────────────────────────

enum _SortMode { manual, priority }

// ── Main sheet ────────────────────────────────────────────────────

class ProjectsBottomSheet extends StatefulWidget {
  const ProjectsBottomSheet({super.key});

  @override
  State<ProjectsBottomSheet> createState() => _ProjectsBottomSheetState();
}

class _ProjectsBottomSheetState extends State<ProjectsBottomSheet> {
  final _ctrl = AppController.instance;
  _SortMode _sortMode = _SortMode.manual;

  /// Priority sort order: Critical → High → Medium → Low
  static const _priorityOrder = {
    Priority.critical: 0,
    Priority.high: 1,
    Priority.medium: 2,
    Priority.low: 3,
  };

  List<Project> _sorted(List<Project> raw) {
    // Active project is ALWAYS first regardless of sort mode.
    final active = raw.where((p) => p.isActive).toList();
    final rest = raw.where((p) => !p.isActive).toList();

    if (_sortMode == _SortMode.priority) {
      rest.sort(
        (a, b) => (_priorityOrder[a.priority] ?? 99).compareTo(
          _priorityOrder[b.priority] ?? 99,
        ),
      );
    }
    // manual: rest keeps its existing sort_order from DB

    return [...active, ...rest];
  }

  void _toggleSort() {
    setState(() {
      _sortMode = _sortMode == _SortMode.manual
          ? _SortMode.priority
          : _SortMode.manual;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final projects = _sorted(_ctrl.projects);

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Header row ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'Projects',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // ── Sort toggle ──────────────────────────
                    GestureDetector(
                      onTap: _toggleSort,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _sortMode == _SortMode.priority
                              ? const Color(0xFFFFD60A).withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _sortMode == _SortMode.priority
                                ? const Color(0xFFFFD60A).withValues(alpha: 0.4)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sort_rounded,
                              size: 14,
                              color: _sortMode == _SortMode.priority
                                  ? const Color(0xFFFFD60A)
                                  : Colors.white38,
                            ),
                            if (_sortMode == _SortMode.priority) ...[
                              const SizedBox(width: 4),
                              const Text(
                                'Priority',
                                style: TextStyle(
                                  color: Color(0xFFFFD60A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),
                    _AddButton(onAdded: () => setState(() {})),
                  ],
                ),
              ),

              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Double-tap to activate · Drag to reorder',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),

              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text(
                        '📋',
                        style: TextStyle(fontSize: 40, color: Colors.white24),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No projects yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: projects.length,
                    proxyDecorator: (child, index, animation) =>
                        Material(color: Colors.transparent, child: child),
                    onReorder: (oldIndex, newIndex) {
                      // Don't allow reordering the active project away from top
                      // or reordering other items to index 0 if active exists.
                      final hasActive = projects.any((p) => p.isActive);
                      if (hasActive && (oldIndex == 0 || newIndex == 0)) return;

                      if (newIndex > oldIndex) newIndex--;
                      final reordered = [...projects];
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      _ctrl.reorderProjects(
                        reordered.map((p) => p.id).toList(),
                      );
                    },
                    itemBuilder: (ctx, i) {
                      final project = projects[i];
                      return _ProjectTile(
                        key: ValueKey(project.id),
                        project: project,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ── Single project row ────────────────────────────────────────────

class _ProjectTile extends StatefulWidget {
  final Project project;
  const _ProjectTile({Key? key, required this.project}) : super(key: key);

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  bool _actionTrayOpen = false;

  void _closeTray() => setState(() => _actionTrayOpen = false);

  void _showViewSheet(BuildContext context) {
    _closeTray();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectViewSheet(project: widget.project),
    );
  }

  void _showEditSheet(BuildContext context) {
    _closeTray();
    showProjectEditSheet(context, widget.project);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AppController.instance;
    final p = widget.project;
    final isActive = p.isActive;

    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          setState(() => _actionTrayOpen = !_actionTrayOpen);
          return false;
        }
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text(
              'Delete project?',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            content: Text(
              '"${p.name}" will be removed.',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFFF3B30)),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final name = p.name;
        await ctrl.removeProject(p.id);
        if (!context.mounted) return;
        AppToast.show(
          context,
          msg: '"$name" deleted',
          backgroundColor: const Color(0xFF222222),
          textColor: Colors.white70,
        );
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: Color(0xFF34C759)),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2E0A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tile ───────────────────────────────────────────
          GestureDetector(
            onTap: () {
              if (_actionTrayOpen) _closeTray();
            },
            onDoubleTap: () async {
              if (isActive) return;
              await ctrl.setActive(p.id);
              if (!context.mounted) return;
              AppToast.show(
                context,
                msg: '${p.priority.emoji} Now: ${p.name}',
                backgroundColor: p.priority.bgColor,
                textColor: p.priority.color,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isActive ? p.priority.bgColor : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? p.priority.color.withValues(alpha: 0.6)
                      : Colors.white10,
                  width: isActive ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Active pin icon
                  if (isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: p.priority.color.withValues(alpha: 0.8),
                      ),
                    ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.priority.color,
                      shape: BoxShape.circle,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: p.priority.color.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white70,
                        fontSize: 15,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.priority.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      p.priority.label,
                      style: TextStyle(
                        color: p.priority.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      color: p.priority.color,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Action tray ─────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: _actionTrayOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Text(
                    'Actions',
                    style: TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                  const Spacer(),
                  _TrayButton(
                    icon: Icons.visibility_outlined,
                    label: 'View',
                    color: const Color(0xFF64D2FF),
                    onTap: () => _showViewSheet(context),
                  ),
                  const SizedBox(width: 8),
                  _TrayButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: const Color(0xFFFFD60A),
                    onTap: () => _showEditSheet(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tray action button ────────────────────────────────────────────

class _TrayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TrayButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
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

// ── Add project button ────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final VoidCallback onAdded;
  const _AddButton({required this.onAdded});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showProjectAddDialog(context, onAdded: onAdded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: Colors.white54, size: 16),
            SizedBox(width: 4),
            Text('Add', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
