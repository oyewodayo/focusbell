import 'package:flutter/material.dart';
import 'package:focusbell/widgets/finance_info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../utils/task_value_parser.dart';

// ─────────────────────────────────────────────────────────────────
// Finance summary bar
// Shown above the task list when project.category == finance and
// at least one task has a parseable numeric value in its title.
//
// • First render → shows a one-time tip snackbar.
// • ⓘ icon on the bar → opens the info dialog on demand.
// • Tap the bar body → opens the full breakdown dialog.
// ─────────────────────────────────────────────────────────────────

const _kTipSeenKey = 'finance_summary_tip_seen';

class TaskSummaryBar extends StatefulWidget {
  final List<Task> tasks;

  const TaskSummaryBar({super.key, required this.tasks});

  @override
  State<TaskSummaryBar> createState() => _TaskSummaryBarState();
}

class _TaskSummaryBarState extends State<TaskSummaryBar> {
  // ── Compute totals ────────────────────────────────────────────

  _Summary _compute() {
    double total = 0, paid = 0, owed = 0;
    final paidTasks = <Task>[];
    final owedTasks = <Task>[];

    for (final t in widget.tasks) {
      final v = parseTaskValue(t.title);
      if (v == null) continue;
      total += v;
      if (t.status == TaskStatus.completed) {
        paid += v;
        paidTasks.add(t);
      } else {
        owed += v;
        owedTasks.add(t);
      }
    }

    return _Summary(
      total: total,
      paid: paid,
      owed: owed,
      paidTasks: paidTasks,
      owedTasks: owedTasks,
    );
  }

  // ── One-time tip snackbar ─────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTip());
  }

  Future<void> _maybeShowTip() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kTipSeenKey) ?? false;
    if (seen || !mounted) return;
    await prefs.setBool(_kTipSeenKey, true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E2D1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFF30D158).withValues(alpha: 0.35),
          ),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 5),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Finance Tracker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Include amounts like "1.3m" or "500k" in task names to auto-track totals. Tap the bar for a full breakdown.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Got it',
          textColor: const Color(0xFF30D158),
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  // ── Info dialog ───────────────────────────────────────────────

  void _showInfoDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (_) => const InfoDialog(),
    );
  }

  // ── Breakdown dialog ──────────────────────────────────────────

  void _showBreakdown(_Summary s) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _BreakdownDialog(summary: s),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _compute();
    if (s.total == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showBreakdown(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A2A14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF30D158).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            // ⓘ icon — always visible, opens info dialog
            GestureDetector(
              onTap: () {
                // Stop the tap propagating to the breakdown dialog.
                _showInfoDialog();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: const Color(0xFF30D158).withValues(alpha: 0.6),
                ),
              ),
            ),

            _SummaryCell(
              label: 'Total',
              value: formatTaskValue(s.total),
              color: Colors.white70,
            ),
            _divider(),
            _SummaryCell(
              label: 'Paid',
              value: formatTaskValue(s.paid),
              color: const Color(0xFF30D158),
            ),
            _divider(),
            _SummaryCell(
              label: 'Owed',
              value: formatTaskValue(s.owed),
              color: const Color(0xFFFF9F0A),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: Colors.white10,
  );
}

// ─────────────────────────────────────────────────────────────────
// Summary data class
// ─────────────────────────────────────────────────────────────────

class _Summary {
  final double total;
  final double paid;
  final double owed;
  final List<Task> paidTasks;
  final List<Task> owedTasks;

  const _Summary({
    required this.total,
    required this.paid,
    required this.owed,
    required this.paidTasks,
    required this.owedTasks,
  });
}

// ─────────────────────────────────────────────────────────────────
// Breakdown Dialog
// ─────────────────────────────────────────────────────────────────

class _BreakdownDialog extends StatelessWidget {
  final _Summary summary;

  const _BreakdownDialog({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
              child: Row(
                children: [
                  const Text(
                    '💰 Finance Breakdown',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Totals strip ─────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  _TotalCell(
                    label: 'Total',
                    compact: formatTaskValue(summary.total),
                    full: formatTaskValueFull(summary.total),
                    color: Colors.white70,
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white10,
                  ),
                  _TotalCell(
                    label: 'Paid',
                    compact: formatTaskValue(summary.paid),
                    full: formatTaskValueFull(summary.paid),
                    color: const Color(0xFF30D158),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white10,
                  ),
                  _TotalCell(
                    label: 'Owed',
                    compact: formatTaskValue(summary.owed),
                    full: formatTaskValueFull(summary.owed),
                    color: const Color(0xFFFF9F0A),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Scrollable task rows ──────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.owedTasks.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Owed',
                        count: summary.owedTasks.length,
                        color: const Color(0xFFFF9F0A),
                      ),
                      const SizedBox(height: 6),
                      ...summary.owedTasks.map(
                        (t) => _TaskBreakdownRow(
                          task: t,
                          valueColor: const Color(0xFFFF9F0A),
                        ),
                      ),
                      if (summary.paidTasks.isNotEmpty)
                        const SizedBox(height: 14),
                    ],
                    if (summary.paidTasks.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Paid',
                        count: summary.paidTasks.length,
                        color: const Color(0xFF30D158),
                      ),
                      const SizedBox(height: 6),
                      ...summary.paidTasks.map(
                        (t) => _TaskBreakdownRow(
                          task: t,
                          valueColor: const Color(0xFF30D158),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Total cell (compact + full on two lines) ──────────────────────

class _TotalCell extends StatelessWidget {
  final String label;
  final String compact;
  final String full;
  final Color color;

  const _TotalCell({
    required this.label,
    required this.compact,
    required this.full,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            compact,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            full,
            style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count item${count == 1 ? '' : 's'}',
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
      ],
    );
  }
}

// ── Per-task breakdown row ────────────────────────────────────────

class _TaskBreakdownRow extends StatelessWidget {
  final Task task;
  final Color valueColor;

  const _TaskBreakdownRow({required this.task, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    final value = parseTaskValue(task.title);
    final fullValue = value != null ? formatTaskValueFull(value) : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Text(task.status.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            fullValue,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Summary bar cell
// ─────────────────────────────────────────────────────────────────

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
