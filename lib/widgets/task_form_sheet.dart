import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────
// Task Form Bottom Sheet
// Used for both adding a new task and editing an existing one.
// ─────────────────────────────────────────────────────────────────

/// title, nullable dueDate, clearDueDate flag.
typedef TaskFormCallback =
    Future<void> Function(String title, DateTime? dueDate, bool clearDue);

class TaskFormSheet extends StatefulWidget {
  final Task? existing;
  final TaskFormCallback onSave;

  const TaskFormSheet({super.key, this.existing, required this.onSave});

  @override
  State<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<TaskFormSheet> {
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

  // Date/time pickers are intentionally always presented in the dark
  // Material palette (regardless of app theme) for consistent legibility.
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
        _clearDue = _isEdit; // signal controller to clear in DB
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
    final fb = Theme.of(context).fb;
    final hasDue = _dueDate != null;
    final overdue = hasDue && _dueDate!.isBefore(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: fb.surfaceVar,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  color: fb.onSurfaceFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              _isEdit ? 'Edit Task' : 'New Task',
              style: TextStyle(
                color: fb.onSurface,
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
              style: TextStyle(color: fb.onSurface, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Task title…',
                hintStyle:
                    TextStyle(color: fb.onSurface.withValues(alpha: 0.38), fontSize: 15),
                filled: true,
                fillColor: fb.surfaceVar,
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
                          ? fb.dangerBg
                          : const Color(0xFF001A33))
                      : fb.surfaceVar,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasDue
                        ? (overdue
                            ? fb.danger.withValues(alpha: 0.5)
                            : const Color(0xFF0A84FF).withValues(alpha: 0.5))
                        : fb.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: hasDue
                          ? (overdue
                              ? fb.danger
                              : const Color(0xFF0A84FF))
                          : fb.onSurface.withValues(alpha: 0.38),
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
                                  ? fb.danger
                                  : fb.onSurface.withValues(alpha: 0.70))
                              : fb.onSurface.withValues(alpha: 0.38),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (hasDue)
                      GestureDetector(
                        onTap: _removeDueDate,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: fb.onSurface.withValues(alpha: 0.38),
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
                    color: fb.danger.withValues(alpha: 0.8),
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
                      foregroundColor: fb.onSurface.withValues(alpha: 0.54),
                      side: BorderSide(color: fb.onSurface.withValues(alpha: 0.12)),
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
                      disabledBackgroundColor:
                          const Color(0xFF0A84FF).withValues(alpha: 0.4),
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
    return '${DateFormat('MMM d, yyyy').format(dt)} at $timeStr';
  }
}
