import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:focusbell/widgets/project_edit_sheet.dart';
import 'package:focusbell/widgets/task_form_sheet.dart';
import 'package:focusbell/widgets/task_row.dart';
import 'package:focusbell/widgets/task_summary_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../services/app_controller.dart';
import '../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────
// Project View Sheet
// Full-detail bottom sheet for a project, including its task list.
// ─────────────────────────────────────────────────────────────────

class ProjectViewSheet extends StatefulWidget {
  final Project project;
  const ProjectViewSheet({super.key, required this.project});

  @override
  State<ProjectViewSheet> createState() => _ProjectViewSheetState();
}

class _ProjectViewSheetState extends State<ProjectViewSheet> {
  final _ctrl = AppController.instance;
  final _listKey = GlobalKey<AnimatedListState>();

  late List<Task> _sortedTasks;

  static const _statusOrder = {
    TaskStatus.ongoing: 0,
    TaskStatus.todo: 1,
    TaskStatus.blocked: 2,
    TaskStatus.completed: 3,
  };

  Project get _liveProject =>
      _ctrl.findProject(widget.project.id) ?? widget.project;

  List<Task> _sorted(List<Task> tasks) => [...tasks]
    ..sort(
      (a, b) =>
          (_statusOrder[a.status] ?? 1).compareTo(_statusOrder[b.status] ?? 1),
    );

  @override
  void initState() {
    super.initState();
    _sortedTasks = _sorted(_liveProject.tasks);
    _ctrl.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerUpdate);
    super.dispose();
  }

  // ── Diffing engine ────────────────────────────────────────────

  void _onControllerUpdate() {
    final newSorted = _sorted(_liveProject.tasks);
    final oldIds = _sortedTasks.map((t) => t.id).toList();
    final newIds = newSorted.map((t) => t.id).toSet();
    final oldIdsSet = oldIds.toSet();

    // Pass 1: Remove deleted tasks (animated).
    for (int i = _sortedTasks.length - 1; i >= 0; i--) {
      final old = _sortedTasks[i];
      if (!newIds.contains(old.id)) {
        final removed = _sortedTasks.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (ctx, animation) => _buildAnimatedRow(removed, animation),
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    // Pass 2: Insert brand-new tasks (animated).
    for (int i = 0; i < newSorted.length; i++) {
      final newTask = newSorted[i];
      if (!oldIdsSet.contains(newTask.id)) {
        _sortedTasks.insert(i, newTask);
        _listKey.currentState?.insertItem(
          i,
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    // Pass 3: Update data + silently reorder (no animation).
    // AnimatedList doesn't support reorder; we replace backing list wholesale
    // and let setState re-render each existing item with updated data.
    for (int i = 0; i < newSorted.length; i++) {
      final newTask = newSorted[i];
      final oldIdx = _sortedTasks.indexWhere((t) => t.id == newTask.id);
      if (oldIdx != -1 && oldIdx != i) {
        final moving = _sortedTasks.removeAt(oldIdx);
        _sortedTasks.insert(i, moving);
      }
      final idx = _sortedTasks.indexWhere((t) => t.id == newTask.id);
      if (idx != -1) _sortedTasks[idx] = newTask;
    }

    if (mounted) setState(() {});
  }

  // ── Add / Edit task ───────────────────────────────────────────

  void _showTaskSheet({Task? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TaskFormSheet(
        existing: existing,
        onSave: (title, dueDate, clearDue) async {
          final project = _liveProject;
          if (existing == null) {
            // ── Add ──────────────────────────────────────────────
            await _ctrl.addTask(project.id, title, dueDate: dueDate);

            await NotificationService.instance.showTaskCreated(
              taskTitle: title,
              projectName: project.name,
              soundMode: _ctrl.settings.soundMode,
            );

            if (dueDate != null) {
              final fresh = _ctrl
                  .findProject(project.id)
                  ?.tasks
                  .lastWhere(
                    (t) => t.title == title,
                    orElse: () => Task(
                      id: '',
                      title: title,
                      createdAt: DateTime.now(),
                      dueDate: dueDate,
                    ),
                  );
              if (fresh != null && fresh.notifId != null) {
                await NotificationService.instance.scheduleForTask(
                  task: fresh,
                  projectName: project.name,
                );
              }
            }
          } else {
            // ── Edit ─────────────────────────────────────────────
            await _ctrl.updateTask(
              project.id,
              existing.id,
              title: title,
              dueDate: dueDate,
              clearDueDate: clearDue,
            );
            final updated = _ctrl
                .findProject(project.id)
                ?.tasks
                .firstWhere(
                  (t) => t.id == existing.id,
                  orElse: () => existing.copyWith(
                    title: title,
                    dueDate: clearDue ? null : dueDate,
                    clearDueDate: clearDue,
                  ),
                );
            if (updated != null) {
              if (clearDue || dueDate == null) {
                await NotificationService.instance.cancelForTask(
                  updated.notifId,
                );
              } else {
                await NotificationService.instance.scheduleForTask(
                  task: updated,
                  projectName: project.name,
                );
              }
            }
          }
        },
      ),
    );
  }

  // ── Status picker ─────────────────────────────────────────────

  void _showStatusPicker(Task task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Set status',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ...TaskStatus.values.map((s) {
              final selected = s == task.status;
              return GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _ctrl.updateTask(_liveProject.id, task.id, status: s);
                  if (s == TaskStatus.completed) {
                    await NotificationService.instance.cancelForTask(
                      int.tryParse(task.id),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? s.bgColor : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? s.color.withValues(alpha: 0.5)
                          : Colors.white10,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(s.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 12),
                      Text(
                        s.label,
                        style: TextStyle(
                          color: selected ? s.color : Colors.white70,
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (selected) ...[
                        const Spacer(),
                        Icon(Icons.check_rounded, color: s.color, size: 16),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Delete task ───────────────────────────────────────────────

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete task?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          '"${task.title}" will be removed.',
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
    if (confirmed != true) return;
    await NotificationService.instance.cancelForTask(int.tryParse(task.id));
    await _ctrl.removeTask(_liveProject.id, task.id);
  }

  // ── Animated row builder ──────────────────────────────────────

  Widget _buildAnimatedRow(Task task, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: FadeTransition(
        opacity: animation,
        child: TaskRow(
          key: ValueKey(task.id),
          task: task,
          onStatusTap: () => _showStatusPicker(task),
          onEdit: () => _showTaskSheet(existing: task),
          onDelete: () => _deleteTask(task),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final liveProject = _liveProject;
    final completedCount =
        _sortedTasks.where((t) => t.status == TaskStatus.completed).length;
    final isFinance = liveProject.category == ProjectCategory.finance;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 36,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ───────────────────────────────────────────────
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

          // ── Priority badge + action buttons ──────────────────────
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: liveProject.priority.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: liveProject.priority.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  liveProject.priority.label,
                  style: TextStyle(
                    color: liveProject.priority.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Category badge — shown when not General/Others
              if (liveProject.category != ProjectCategory.general &&
                  liveProject.category != ProjectCategory.others) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${liveProject.category.emoji} ${liveProject.category.label}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit project button
                  GestureDetector(
                    onTap: () => _showEditSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF0A84FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF0A84FF)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: Color(0xFF0A84FF),
                        size: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Add task button
                  GestureDetector(
                    onTap: () => _showTaskSheet(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF0A84FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF0A84FF)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            color: Color(0xFF0A84FF),
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Add Task',
                            style: TextStyle(
                              color: Color(0xFF0A84FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Project name ─────────────────────────────────────────
          Text(
            liveProject.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),

          // ── Scrollable body ──────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  if (liveProject.description.isEmpty)
                    const Text(
                      'No description provided.',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: liveProject.description,
                      selectable: true,
                      extensionSet: md.ExtensionSet(
                        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                        <md.InlineSyntax>[
                          md.EmojiSyntax(),
                          md.AutolinkExtensionSyntax(),
                          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                        ],
                      ),
                      onTapLink: (text, href, title) async {
                        if (href == null) return;
                        final uri = Uri.tryParse(href);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.6,
                        ),
                        a: const TextStyle(
                          color: Color.fromARGB(255, 212, 219, 222),
                          fontSize: 14,
                          decoration: TextDecoration.none,
                        ),
                        h1: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        h2: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        h3: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        strong: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        em: const TextStyle(
                          color: Colors.white60,
                          fontStyle: FontStyle.italic,
                        ),
                        code: const TextStyle(
                          color: Color(0xFF64D2FF),
                          backgroundColor: Color(0xFF252525),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        blockquoteDecoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(6),
                          border: const Border(
                            left: BorderSide(
                              color: Color(0xFF0A84FF),
                              width: 3,
                            ),
                          ),
                        ),
                        blockquote: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                        listBullet:
                            const TextStyle(color: Colors.white38),
                      ),
                    ),

                  // ── Task section ──────────────────────────────────
                  if (_sortedTasks.isNotEmpty) ...[
                    const SizedBox(height: 20),

                    // Tasks header with count
                    Row(
                      children: [
                        const Text(
                          'Tasks',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$completedCount/${_sortedTasks.length}',
                          style: const TextStyle(
                            color: Colors.white30,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Finance summary bar — only for Finance category projects.
                    if (isFinance)
                      TaskSummaryBar(tasks: _sortedTasks),

                    // Task list
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(context).size.height * 0.38,
                      ),
                      child: AnimatedList(
                        key: _listKey,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        initialItemCount: _sortedTasks.length,
                        itemBuilder: (ctx, i, animation) {
                          if (i >= _sortedTasks.length) {
                            return const SizedBox.shrink();
                          }
                          return _buildAnimatedRow(
                            _sortedTasks[i],
                            animation,
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    // Empty state
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            '📋',
                            style: TextStyle(
                              fontSize: 28,
                              color: Colors.white24,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No tasks yet.\nTap "Add Task" to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white30,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showProjectEditSheet(context, widget.project);
  }
}