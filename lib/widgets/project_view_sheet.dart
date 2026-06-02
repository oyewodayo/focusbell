import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../services/app_controller.dart';
import '../services/notification_service.dart';

/// Full-detail bottom sheet for a project, including its task list.
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

    for (int i = _sortedTasks.length - 1; i >= 0; i--) {
      final old = _sortedTasks[i];
      if (!newSorted.any((t) => t.id == old.id)) {
        final removed = _sortedTasks.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (ctx, animation) => _buildAnimatedRow(removed, animation),
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    for (int i = 0; i < newSorted.length; i++) {
      final newTask = newSorted[i];
      if (_sortedTasks.indexWhere((t) => t.id == newTask.id) == -1) {
        _sortedTasks.insert(i, newTask);
        _listKey.currentState?.insertItem(
          i,
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    for (int newIdx = 0; newIdx < newSorted.length; newIdx++) {
      final newTask = newSorted[newIdx];
      final oldIdx = _sortedTasks.indexWhere((t) => t.id == newTask.id);
      if (oldIdx == -1) continue;

      _sortedTasks[oldIdx] = newTask;

      if (oldIdx != newIdx) {
        final moving = _sortedTasks.removeAt(oldIdx);
        _listKey.currentState?.removeItem(
          oldIdx,
          (ctx, animation) => _buildAnimatedRow(moving, animation),
          duration: const Duration(milliseconds: 200),
        );

        Future.delayed(const Duration(milliseconds: 160), () {
          if (!mounted) return;
          _sortedTasks.insert(newIdx, newTask);
          _listKey.currentState?.insertItem(
            newIdx,
            duration: const Duration(milliseconds: 250),
          );
        });
        break;
      }
    }

    if (mounted) setState(() {});
  }

  // ── Add / Edit task — bottom sheet ────────────────────────────

  /// Shows a bottom sheet for adding a new task OR editing an existing one.
  /// When [existing] is null, a new task is created.
  void _showTaskSheet({Task? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskFormSheet(
        existing: existing,
        onSave: (title, dueDate, clearDue) async {
        final project = _liveProject;
        if (existing == null) {
            // Add
            await _ctrl.addTask(project.id, title, dueDate: dueDate);

            // ✅ Show immediate "task created" notification regardless of due date.
            await NotificationService.instance.showTaskCreated(
            taskTitle: title,
            projectName: project.name,
            soundMode: _ctrl.settings.soundMode,  // ← respect user's sound setting
            );

            // Schedule due-date alarm if set — fetch after DB write so notifId is populated.
            if (dueDate != null) {
            final fresh = _ctrl
                .findProject(project.id)
                ?.tasks
                .lastWhere((t) => t.title == title, orElse: () => Task(
                    id: '', title: title, createdAt: DateTime.now(), dueDate: dueDate,
                ));
            if (fresh != null && fresh.notifId != null) {
                await NotificationService.instance.scheduleForTask(
                task: fresh,
                projectName: project.name,
                );
            }
            }
        } else {
            // Edit — existing logic unchanged
            await _ctrl.updateTask(
            project.id,
            existing.id,
            title: title,
            dueDate: dueDate,
            clearDueDate: clearDue,
            );
            final updated = _ctrl.findProject(project.id)?.tasks
                .firstWhere((t) => t.id == existing.id, orElse: () => existing.copyWith(
                title: title, dueDate: clearDue ? null : dueDate, clearDueDate: clearDue,
                ));
            if (updated != null) {
            if (clearDue || dueDate == null) {
                await NotificationService.instance.cancelForTask(updated.notifId);
            } else {
                await NotificationService.instance.scheduleForTask(
                task: updated, projectName: project.name,
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
                  // Cancel notification when task is marked complete.
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
        child: _TaskRow(
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
    final completedCount = _sortedTasks
        .where((t) => t.status == TaskStatus.completed)
        .length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          // Handle
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

          // Priority badge row + Add task button
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              const Spacer(),
              GestureDetector(
                onTap: () => _showTaskSheet(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.35),
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

          const SizedBox(height: 14),

          // Project name
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

          // Description — markdown, selectable, links open externally
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
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                    left: BorderSide(color: Color(0xFF0A84FF), width: 3),
                  ),
                ),
                blockquote: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
                listBullet: const TextStyle(color: Colors.white38),
              ),
            ),

          // ── Task list ─────────────────────────────────────────
          if (_sortedTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
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
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.38,
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
                  return _buildAnimatedRow(_sortedTasks[i], animation);
                },
              ),
            ),
          ] else ...[
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
                    style: TextStyle(fontSize: 28, color: Colors.white24),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Task Form Bottom Sheet
// ─────────────────────────────────────────────────────────────────

/// Callback: title, nullable dueDate, clearDueDate flag.
typedef TaskFormCallback =
    Future<void> Function(String title, DateTime? dueDate, bool clearDue);

class _TaskFormSheet extends StatefulWidget {
  final Task? existing;
  final TaskFormCallback onSave;

  const _TaskFormSheet({this.existing, required this.onSave});

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  late final TextEditingController _titleCtrl;
  DateTime? _dueDate;
  bool _clearDue = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _dueDate = widget.existing?.dueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── Due date picker ───────────────────────────────────────────

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final initialDate = (_dueDate != null && _dueDate!.isAfter(now))
        ? _dueDate!
        : now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now.subtract(const Duration(minutes: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => _darkPickerTheme(ctx, child),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (ctx, child) => _darkPickerTheme(ctx, child),
    );
    if (time == null || !mounted) return;

    setState(() {
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _clearDue = false;
    });
  }

  Widget _darkPickerTheme(BuildContext ctx, Widget? child) => Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF0A84FF),
        onPrimary: Colors.white,
        surface: Color(0xFF1A1A1A),
        onSurface: Colors.white,
      ),
      dialogBackgroundColor: const Color(0xFF1A1A1A),
    ),
    child: child!,
  );

  void _removeDueDate() => setState(() {
    _dueDate = null;
    _clearDue = _isEdit; // signal to controller to clear in DB
  });

  // ── Save ──────────────────────────────────────────────────────

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(title, _dueDate, _clearDue);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasDue = _dueDate != null;
    final overdue = hasDue && _dueDate!.isBefore(DateTime.now());

    return Padding(
      // Slide up above keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
            const SizedBox(height: 20),

            // Title
            Text(
              _isEdit ? 'Edit Task' : 'New Task',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),

            // Task title field
            TextField(
              controller: _titleCtrl,
              maxLines: 3,
              autofocus: !_isEdit,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Task title…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
                filled: true,
                fillColor: const Color(0xFF252525),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),

            // Due date row
            GestureDetector(
              onTap: _pickDueDate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: hasDue
                      ? (overdue
                            ? const Color(0xFF2E0A0A)
                            : const Color(0xFF001A33))
                      : const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasDue
                        ? (overdue
                              ? const Color(0xFFFF3B30).withValues(alpha: 0.5)
                              : const Color(0xFF0A84FF).withValues(alpha: 0.5))
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: hasDue
                          ? (overdue
                                ? const Color(0xFFFF3B30)
                                : const Color(0xFF0A84FF))
                          : Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasDue
                            ? _formatDue(_dueDate!)
                            : 'Add due date (optional)',
                        style: TextStyle(
                          color: hasDue
                              ? (overdue
                                    ? const Color(0xFFFF3B30)
                                    : Colors.white70)
                              : Colors.white38,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (hasDue)
                      GestureDetector(
                        onTap: _removeDueDate,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (hasDue && !overdue) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '🔔 You\'ll be reminded at this time.',
                  style: TextStyle(
                    color: const Color(0xFF0A84FF).withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ],

            if (overdue) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '⚠️ This time is in the past — notification won\'t fire.',
                  style: TextStyle(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A84FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF0A84FF,
                      ).withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isEdit ? 'Save Changes' : 'Add Task',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDue(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDay = DateTime(dt.year, dt.month, dt.day);

    final timeStr = DateFormat('h:mm a').format(dt);

    if (dtDay == today) return 'Today at $timeStr';
    if (dtDay == tomorrow) return 'Tomorrow at $timeStr';
    return DateFormat('MMM d, yyyy').format(dt) + ' at $timeStr';
  }
}

// ─────────────────────────────────────────────────────────────────
// Single task row
// ─────────────────────────────────────────────────────────────────

class _TaskRow extends StatefulWidget {
  final Task task;
  final VoidCallback onStatusTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskRow({
    super.key,
    required this.task,
    required this.onStatusTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.task.status;
    final done = s == TaskStatus.completed;
    final overdue = widget.task.isOverdue;
    final dueSoon = widget.task.isDueSoon;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: overdue ? const Color(0xFF200A0A) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: overdue
                ? const Color(0xFFFF3B30).withValues(alpha: 0.35)
                : Colors.white10,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status emoji tap
                GestureDetector(
                  onTap: widget.onStatusTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Text(s.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),

                // Title
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _expanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: Text(
                        widget.task.title,
                        style: TextStyle(
                          color: done ? Colors.white38 : Colors.white70,
                          fontSize: 14,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: Colors.white38,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondChild: Text(
                        widget.task.title,
                        style: TextStyle(
                          color: done ? Colors.white38 : Colors.white70,
                          fontSize: 14,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: Colors.white38,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),

                // Status chip + overflow menu
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: widget.onStatusTap,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: s.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: s.color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          s.label,
                          style: TextStyle(
                            color: s.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white30,
                        size: 18,
                      ),
                      color: const Color(0xFF222222),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (value == 'edit') widget.onEdit();
                        if (value == 'delete') widget.onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: Color(0xFFFFD60A),
                                size: 16,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                color: Color(0xFFFF3B30),
                                size: 16,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Color(0xFFFF3B30),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // Due date pill — shown below the title row
            if (widget.task.dueDate != null && !done) ...[
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
                child: _DuePill(
                  dueDate: widget.task.dueDate!,
                  overdue: overdue,
                  dueSoon: dueSoon,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Due date pill ─────────────────────────────────────────────────

class _DuePill extends StatelessWidget {
  final DateTime dueDate;
  final bool overdue;
  final bool dueSoon;

  const _DuePill({
    required this.dueDate,
    required this.overdue,
    required this.dueSoon,
  });

  @override
  Widget build(BuildContext context) {
    final Color pillColor = overdue
        ? const Color(0xFFFF3B30)
        : dueSoon
        ? const Color(0xFFFF8C00)
        : const Color(0xFF8E8E93);

    final String label = overdue
        ? '⚠️ Overdue · ${_format(dueDate)}'
        : dueSoon
        ? '⏰ Due soon · ${_format(dueDate)}'
        : '📅 ${_format(dueDate)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pillColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: pillColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _format(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    final timeStr = DateFormat('h:mm a').format(dt);

    if (dtDay == today) return 'Today $timeStr';
    if (dtDay == tomorrow) return 'Tomorrow $timeStr';
    return DateFormat('MMM d').format(dt) + ' $timeStr';
  }
}
