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
                          style:
                              TextStyle(fontSize: 40, color: Colors.white24)),
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

class _ProjectTile extends StatelessWidget {
  final Project project;
  const _ProjectTile({required this.project});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppController.instance;
    final isActive = project.isActive;

    return Dismissible(
      key: ValueKey(project.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2E0A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Delete project?',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            content: Text(
              '"${project.name}" will be removed.',
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
        final name = project.name;
        await ctrl.removeProject(project.id);
        if (!context.mounted) return;
        AppToast.show(
          context,
          msg: '"$name" deleted',
          backgroundColor: const Color(0xFF222222),
          textColor: Colors.white70,
        );
      },
      child: GestureDetector(
        onTap: () async {
          if (isActive) return;
          await ctrl.setActive(project.id);
          if (!context.mounted) return;
          AppToast.show(
            context,
            msg: '${project.priority.emoji} Now: ${project.name}',
            backgroundColor: project.priority.bgColor,
            textColor: project.priority.color,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? project.priority.bgColor
                : const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? project.priority.color.withValues(alpha: 0.6)
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
                  color: project.priority.color,
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: project.priority.color
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
                  project.name,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: project.priority.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  project.priority.label,
                  style: TextStyle(
                    color: project.priority.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded,
                    color: project.priority.color, size: 18),
              ],
            ],
          ),
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
            Text('Add', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
                autofocus: true,
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
                await AppController.instance.addProject(name, priority,descriptionCtrl.text.trim());
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