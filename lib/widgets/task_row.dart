import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────
// Single task row
// ─────────────────────────────────────────────────────────────────

class TaskRow extends StatefulWidget {
  final Task task;
  final VoidCallback onStatusTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskRow({
    super.key,
    required this.task,
    required this.onStatusTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
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
          color: overdue ? fb.dangerBg : fb.surfaceVar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: overdue
                ? fb.danger.withValues(alpha: 0.35)
                : fb.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status emoji tap target
                GestureDetector(
                  onTap: widget.onStatusTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Text(s.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),

                // Title (collapses/expands on row tap)
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
                          color: done
                              ? fb.onSurface.withValues(alpha: 0.38)
                              : fb.onSurface.withValues(alpha: 0.70),
                          fontSize: 14,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: fb.onSurface.withValues(alpha: 0.38),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondChild: Text(
                        widget.task.title,
                        style: TextStyle(
                          color: done
                              ? fb.onSurface.withValues(alpha: 0.38)
                              : fb.onSurface.withValues(alpha: 0.70),
                          fontSize: 14,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: fb.onSurface.withValues(alpha: 0.38),
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
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: fb.onSurface.withValues(alpha: 0.30),
                        size: 18,
                      ),
                      color: fb.surfaceVar,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (value == 'edit') widget.onEdit();
                        if (value == 'delete') widget.onDelete();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFFFFD60A),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: fb.onSurface.withValues(alpha: 0.70),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                color: fb.danger,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: fb.danger,
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

            // Due date pill — shown below the title row when not completed
            if (widget.task.dueDate != null && !done)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
                child: DuePill(
                  dueDate: widget.task.dueDate!,
                  overdue: overdue,
                  dueSoon: dueSoon,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Due date pill
// ─────────────────────────────────────────────────────────────────

class DuePill extends StatelessWidget {
  final DateTime dueDate;
  final bool overdue;
  final bool dueSoon;

  const DuePill({
    super.key,
    required this.dueDate,
    required this.overdue,
    required this.dueSoon,
  });

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    final Color pillColor = overdue
        ? fb.danger
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
    return '${DateFormat('MMM d').format(dt)} $timeStr';
  }
}
