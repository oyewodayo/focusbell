import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';

class ProjectsBottomSheet extends StatefulWidget {
  const ProjectsBottomSheet({super.key});

  @override
  State<ProjectsBottomSheet> createState() => _ProjectsBottomSheetState();
}

class _ProjectsBottomSheetState extends State<ProjectsBottomSheet> {
  final _ctrl = AppController.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final projects = _ctrl.projects;
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
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
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
                    const Spacer(),
                    _AddButton(onAdded: () => setState(() {})),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text('📋',
                          style: TextStyle(fontSize: 40, color: Colors.white24)),
                      SizedBox(height: 12),
                      Text(
                        'No projects yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white38, fontSize: 14, height: 1.6),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: projects.length,
                    itemBuilder: (ctx, i) =>
                        _ProjectTile(project: projects[i]),
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
  const _ProjectTile({required this.project});

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  /// Tracks whether the right-swipe action tray is open.
  bool _actionTrayOpen = false;

  void _closeTray() => setState(() => _actionTrayOpen = false);

  // ── View bottom sheet ────────────────────────────────────────

  void _showViewSheet(BuildContext context) {
    _closeTray();
    final p = widget.project;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: p.priority.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              p.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              p.description.isEmpty ? 'No description provided.' : p.description,
              style: TextStyle(
                color: p.description.isEmpty ? Colors.white30 : Colors.white60,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Edit bottom sheet ────────────────────────────────────────

  void _showEditSheet(BuildContext context) {
    _closeTray();
    final p = widget.project;
    final nameCtrl = TextEditingController(text: p.name);
    final descCtrl = TextEditingController(text: p.description);
    Priority selectedPriority = p.priority;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // so keyboard doesn't cover the sheet
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Edit Project',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                // Name field
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Project name…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF252525),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                // Description field
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Project description (optional)…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF252525),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Priority',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: Priority.values.map((pr) {
                    final selected = pr == selectedPriority;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedPriority = pr),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? pr.bgColor
                                : const Color(0xFF252525),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? pr.color.withValues(alpha: 0.7)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(pr.emoji,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                pr.label,
                                style: TextStyle(
                                  color:
                                      selected ? pr.color : Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A2A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          await AppController.instance.updateProject(
                            p.id,
                            name: name,
                            description: descCtrl.text.trim(),
                            priority: selectedPriority,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          AppToast.show(
                            context,
                            msg: '${selectedPriority.emoji} "$name" updated',
                            backgroundColor: selectedPriority.bgColor,
                            textColor: selectedPriority.color,
                          );
                        },
                        child: const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AppController.instance;
    final p = widget.project;
    final isActive = p.isActive;

    return Dismissible(
      key: ValueKey(p.id),
      // Only left-to-right opens the tray (startToEnd),
      // right-to-left stays as delete (endToStart).
      direction: DismissDirection.horizontal,
      // Confirm lets us intercept the swipe direction.
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Toggle the action tray; never actually dismiss.
          setState(() => _actionTrayOpen = !_actionTrayOpen);
          return false;
        }
        // endToStart → delete confirmation.
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Delete project?',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            content: Text(
              '"${p.name}" will be removed.',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete',
                      style: TextStyle(color: Color(0xFFFF3B30)))),
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
      // Left background: delete hint
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.more_horiz_rounded,
            color: Color(0xFF34C759)),
      ),
      // Right background: delete hint
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
          // ── Tile ──────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              if (_actionTrayOpen) {
                _closeTray();
                return;
              }
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isActive
                    ? p.priority.bgColor
                    : const Color(0xFF1C1C1C),
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
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.priority.color,
                      shape: BoxShape.circle,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: p.priority.color
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                              )
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
                        horizontal: 8, vertical: 3),
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
                    Icon(Icons.check_circle_rounded,
                        color: p.priority.color, size: 18),
                  ],
                ],
              ),
            ),
          ),

          // ── Action tray (slides in below the tile) ────────────
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Text('Actions',
                      style:
                          TextStyle(color: Colors.white30, fontSize: 11)),
                  const Spacer(),
                  // View
                  _TrayButton(
                    icon: Icons.visibility_outlined,
                    label: 'View',
                    color: const Color(0xFF64D2FF),
                    onTap: () => _showViewSheet(context),
                  ),
                  const SizedBox(width: 8),
                  // Edit
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

// ── Small tray action button ──────────────────────────────────────

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
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
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
      onTap: () => _showAddDialog(context),
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
            Text('Add',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    Priority selectedPriority = Priority.medium;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('New Project',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Project name…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Project description (optional)…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Priority',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: Priority.values.map((p) {
                  final selected = p == selectedPriority;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedPriority = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? p.bgColor
                              : const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? p.color.withValues(alpha: 0.7)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(p.emoji,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              p.label,
                              style: TextStyle(
                                color: selected ? p.color : Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final priority = selectedPriority;
                await AppController.instance
                    .addProject(name, priority, descriptionCtrl.text.trim());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                onAdded();
                if (!context.mounted) return;
                AppToast.show(
                  context,
                  msg: '${priority.emoji} "$name" added',
                  backgroundColor: priority.bgColor,
                  textColor: priority.color,
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}