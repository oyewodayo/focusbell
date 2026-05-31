// project_view_sheet.dart — full replacement
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/project.dart';
import '../services/app_controller.dart';

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

  /// Mutable sorted snapshot that AnimatedList tracks.
  late List<Task> _sortedTasks;

  static const _statusOrder = {
    TaskStatus.ongoing: 0,
    TaskStatus.todo: 1,
    TaskStatus.completed: 2,
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

  /// Diffing engine: animates items that changed position.
  void _onControllerUpdate() {
    final newSorted = _sorted(_liveProject.tasks);

    // Handle deletions first.
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

    // Handle insertions.
    for (int i = 0; i < newSorted.length; i++) {
      final newTask = newSorted[i];
      final existingIdx = _sortedTasks.indexWhere((t) => t.id == newTask.id);
      if (existingIdx == -1) {
        _sortedTasks.insert(i, newTask);
        _listKey.currentState?.insertItem(
          i,
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    // Handle moves (status changed → position changed).
    // Strategy: remove from old index, insert at new index.
    for (int newIdx = 0; newIdx < newSorted.length; newIdx++) {
      final newTask = newSorted[newIdx];
      final oldIdx = _sortedTasks.indexWhere((t) => t.id == newTask.id);
      if (oldIdx == -1) continue; // Already handled above.

      // Update the task data in place (title/status may have changed).
      _sortedTasks[oldIdx] = newTask;

      if (oldIdx != newIdx) {
        // Remove from old position.
        final moving = _sortedTasks.removeAt(oldIdx);
        _listKey.currentState?.removeItem(
          oldIdx,
          (ctx, animation) => _buildAnimatedRow(moving, animation),
          duration: const Duration(milliseconds: 200),
        );

        // Insert at new position after a short delay so remove animates first.
        Future.delayed(const Duration(milliseconds: 160), () {
          if (!mounted) return;
          _sortedTasks.insert(newIdx, newTask);
          _listKey.currentState?.insertItem(
            newIdx,
            duration: const Duration(milliseconds: 250),
          );
        });
        // Only move one item per update cycle to avoid index drift.
        break;
      }
    }

    // If nothing moved, just call setState to refresh chips/labels.
    if (mounted) setState(() {});
  }

  // ── Add task ──────────────────────────────────────────────────

  void _showAddTaskDialog() {
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'New Task',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Task title…',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF252525),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onSubmitted: (_) => _submitAddTask(ctx, titleCtrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => _submitAddTask(ctx, titleCtrl),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAddTask(
    BuildContext ctx,
    TextEditingController titleCtrl,
  ) async {
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    await _ctrl.addTask(_liveProject.id, title);
    if (!ctx.mounted) return;
    Navigator.pop(ctx);
  }

  // ── Rename task ───────────────────────────────────────────────

  void _showRenameDialog(Task task) {
    final titleCtrl = TextEditingController(text: task.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Rename Task',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Task title…',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF252525),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onSubmitted: (_) => _submitRename(ctx, task, titleCtrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => _submitRename(ctx, task, titleCtrl),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRename(
    BuildContext ctx,
    Task task,
    TextEditingController c,
  ) async {
    final title = c.text.trim();
    if (title.isEmpty) return;
    await _ctrl.updateTask(_liveProject.id, task.id, title: title);
    if (!ctx.mounted) return;
    Navigator.pop(ctx);
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
    await _ctrl.removeTask(_liveProject.id, task.id);
  }

  // ── Animated row builder (used by AnimatedList for exit too) ──

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
          onRename: () => _showRenameDialog(task),
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
                onTap: _showAddTaskDialog,
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

          // Description
         // Description — markdown rendered, links clickable, text selectable
          if (liveProject.description.isEmpty)
            const Text(
              'No description provided.',
              style: TextStyle(color: Colors.white30, fontSize: 14, height: 1.6),
            )
          else
            MarkdownBody(
              data: liveProject.description,
              selectable: true,           // ← enables text selection + copy
              extensionSet: md.ExtensionSet(
                md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                <md.InlineSyntax>[
                  md.EmojiSyntax(),
                  md.AutolinkExtensionSyntax(), // ← auto-detects bare URLs
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
                p: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                a: const TextStyle(
                  color: Color.fromARGB(255, 212, 219, 222),
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
                h1: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                h2: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                h3: const TextStyle(
                    color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                strong: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
                em: const TextStyle(
                    color: Colors.white60, fontStyle: FontStyle.italic),
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
                blockquote: const TextStyle(color: Colors.white54, fontSize: 14),
                listBullet: const TextStyle(color: Colors.white38),
              ),
            ),

          // ── Task list ────────────────────────────────────────
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
                  // Guard against index-out-of-range during animations.
                  if (i >= _sortedTasks.length) return const SizedBox.shrink();
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

// ── Single task row ───────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final Task task;
  final VoidCallback onStatusTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TaskRow({
    super.key,
    required this.task,
    required this.onStatusTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = task.status;
    final done = s == TaskStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onStatusTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(s.emoji, style: const TextStyle(fontSize: 16)),
            ),
          ),
          Expanded(
            child: Text(
              task.title,
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
          ),
          GestureDetector(
            onTap: onStatusTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: s.color.withValues(alpha: 0.3)),
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
              Icons.more_vert_rounded,
              color: Colors.white30,
              size: 18,
            ),
            color: const Color(0xFF222222),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'rename') onRename();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      color: Color(0xFFFFD60A),
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Rename',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
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
                      style: TextStyle(color: Color(0xFFFF3B30), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
