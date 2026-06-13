// widgets/analytics_sheet.dart
//
// Drop into lib/widgets/.
// Shows focus analytics across all projects or drilled into one project.
// Drill-down includes a full per-session log with actual start/end times,
// real duration (may exceed preset if user kept going), and overrun badge.
// Pure Flutter — no charting library required.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/focus_timer_service.dart';

// ── Entry point ───────────────────────────────────────────────────

void showAnalyticsSheet(BuildContext context, List<Project> projects) {
  showModalBottomSheet(
    context:            context,
    backgroundColor:    Colors.transparent,
    isScrollControlled: true,
    builder: (_) => AnalyticsSheet(projects: projects),
  );
}

// ── Main sheet ────────────────────────────────────────────────────

class AnalyticsSheet extends StatefulWidget {
  final List<Project> projects;
  const AnalyticsSheet({super.key, required this.projects});

  @override
  State<AnalyticsSheet> createState() => _AnalyticsSheetState();
}

class _AnalyticsSheetState extends State<AnalyticsSheet> {
  final _svc = FocusTimerService.instance;

  // 0 = 7 days, 1 = 30 days
  int _rangeIndex = 0;
  int get _days   => _rangeIndex == 0 ? 7 : 30;

  List<ProjectFocusSummary> _summaries = [];
  bool _loading = true;

  // Drill-down: null = overview, non-null = single project
  String? _drillProjectId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final liveProjects = widget.projects.where((p) => !p.isArchived).toList();
    final summaries    = await _svc.summariesForAllProjects(liveProjects, days: _days);
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _loading   = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height:     MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color:        Color(0xFF0E0E0E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),

          // ── Header ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (_drillProjectId != null)
                  GestureDetector(
                    onTap: () => setState(() => _drillProjectId = null),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color:        Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white54, size: 12),
                          SizedBox(width: 4),
                          Text('Back',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _drillProjectId != null
                        ? (_summaries
                            .firstWhere(
                                (s) => s.projectId == _drillProjectId,
                                orElse: () => _summaries.first)
                            .projectName)
                        : 'Focus Analytics',
                    style: const TextStyle(
                      color:         Colors.white,
                      fontSize:      20,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _RangeToggle(
                  index:    _rangeIndex,
                  onSelect: (i) {
                    setState(() => _rangeIndex = i);
                    _load();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                    color: Colors.white24, strokeWidth: 1.5),
              ),
            )
          else if (_summaries.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: _drillProjectId != null
                  ? _DrillView(
                      summary: _summaries.firstWhere(
                          (s) => s.projectId == _drillProjectId),
                      days:    _days,
                      svc:     _svc,
                    )
                  : _OverviewList(
                      summaries: _summaries,
                      days:      _days,
                      onDrill:   (id) =>
                          setState(() => _drillProjectId = id),
                    ),
            ),
        ],
      ),
    );
  }
}

// ── Range toggle ──────────────────────────────────────────────────

class _RangeToggle extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _RangeToggle({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(
              label: '7d', selected: index == 0, onTap: () => onSelect(0)),
          _ToggleChip(
              label: '30d', selected: index == 1, onTap: () => onSelect(1)),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      selected ? Colors.white : Colors.white38,
            fontSize:   12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Overview list ─────────────────────────────────────────────────

class _OverviewList extends StatelessWidget {
  final List<ProjectFocusSummary> summaries;
  final int days;
  final ValueChanged<String> onDrill;

  const _OverviewList({
    required this.summaries,
    required this.days,
    required this.onDrill,
  });

  @override
  Widget build(BuildContext context) {
    final totalSecs =
        summaries.fold(0, (s, e) => s + e.totalFocusSeconds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        _GrandTotalCard(totalSeconds: totalSecs, days: days),
        const SizedBox(height: 20),
        ...summaries.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProjectSummaryCard(
              summary:    s,
              maxSeconds: summaries
                  .map((x) => x.totalFocusSeconds)
                  .fold(0, math.max),
              onTap: () => onDrill(s.projectId),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Grand total card ──────────────────────────────────────────────

class _GrandTotalCard extends StatelessWidget {
  final int totalSeconds;
  final int days;
  const _GrandTotalCard(
      {required this.totalSeconds, required this.days});

  @override
  Widget build(BuildContext context) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total focus',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '${h}h ${m}m',
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   30,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                'last $days days',
                style:
                    const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          const Text('⏱', style: TextStyle(fontSize: 36)),
        ],
      ),
    );
  }
}

// ── Per-project summary card ──────────────────────────────────────

class _ProjectSummaryCard extends StatelessWidget {
  final ProjectFocusSummary summary;
  final int                 maxSeconds;
  final VoidCallback        onTap;

  const _ProjectSummaryCard({
    required this.summary,
    required this.maxSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h   = summary.totalFocusSeconds ~/ 3600;
    final m   = (summary.totalFocusSeconds % 3600) ~/ 60;
    final pct = maxSeconds == 0
        ? 0.0
        : (summary.totalFocusSeconds / maxSeconds).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary.projectName,
                    style: const TextStyle(
                      color:      Colors.white70,
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${h}h ${m}m',
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white24, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:           pct,
                minHeight:       5,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor:
                    const AlwaysStoppedAnimation(Color(0xFFFF453A)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatPill(
                  emoji: '🔥',
                  label: '${summary.currentStreak}d streak',
                  color: const Color(0xFFFF9F0A),
                ),
                const SizedBox(width: 8),
                _StatPill(
                  emoji: '✅',
                  label: '${summary.completedSessions} sessions',
                  color: const Color(0xFF32D74B),
                ),
                if (summary.totalSessions > 0) ...[
                  const SizedBox(width: 8),
                  _StatPill(
                    emoji: '📊',
                    label:
                        '${(summary.completionRate * 100).round()}% done',
                    color: const Color(0xFF0A84FF),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String emoji;
  final String label;
  final Color  color;
  const _StatPill(
      {required this.emoji, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color:      color,
              fontSize:   10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drill-down view ───────────────────────────────────────────────

class _DrillView extends StatefulWidget {
  final ProjectFocusSummary summary;
  final int                 days;
  final FocusTimerService   svc;

  const _DrillView({
    required this.summary,
    required this.days,
    required this.svc,
  });

  @override
  State<_DrillView> createState() => _DrillViewState();
}

class _DrillViewState extends State<_DrillView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<FocusSession> _sessions = [];
  bool _loadingSessions = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() => _loadingSessions = true);
    final sessions = await widget.svc.fetchSessionsForProject(
      projectId: widget.summary.projectId,
      days:      widget.days,
    );
    if (!mounted) return;
    // Show most recent first
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    setState(() {
      _sessions        = sessions;
      _loadingSessions = false;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.summary.totalFocusSeconds ~/ 3600;
    final m = (widget.summary.totalFocusSeconds % 3600) ~/ 60;

    return Column(
      children: [
        // ── Stats row ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _BigStat(
                value: '${h}h ${m}m',
                label: 'Total focus',
                color: const Color(0xFFFF453A),
              ),
              const SizedBox(width: 10),
              _BigStat(
                value: '${widget.summary.currentStreak}d',
                label: 'Streak',
                color: const Color(0xFFFF9F0A),
              ),
              const SizedBox(width: 10),
              _BigStat(
                value: '${widget.summary.completedSessions}',
                label: 'Done',
                color: const Color(0xFF32D74B),
              ),
              const SizedBox(width: 10),
              _BigStat(
                value: '${(widget.summary.completionRate * 100).round()}%',
                label: 'Rate',
                color: const Color(0xFF0A84FF),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Tab bar: Chart | Sessions ──────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller:         _tab,
            indicator:          BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize:      TabBarIndicatorSize.tab,
            dividerColor:       Colors.transparent,
            labelColor:         Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            tabs: const [
              Tab(text: 'Chart'),
              Tab(text: 'Sessions'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Tab views ─────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              // ── Chart tab ─────────────────────────────
              _ChartTab(summary: widget.summary, days: widget.days),

              // ── Sessions tab ──────────────────────────
              _loadingSessions
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white24, strokeWidth: 1.5),
                    )
                  : _sessions.isEmpty
                      ? const _EmptySessionsState()
                      : _SessionList(sessions: _sessions),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Chart tab ─────────────────────────────────────────────────────

class _ChartTab extends StatelessWidget {
  final ProjectFocusSummary summary;
  final int                 days;
  const _ChartTab({required this.summary, required this.days});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        const Text(
          'Daily focus (minutes)',
          style: TextStyle(
              color: Colors.white38, fontSize: 11, letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        _BarChart(stats: summary.dailyStats, days: days),
        const SizedBox(height: 24),
        _InfoRow(
          icon:  Icons.local_fire_department_rounded,
          color: const Color(0xFFFF9F0A),
          label: 'Longest streak',
          value: '${summary.longestStreak} day${summary.longestStreak == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon:  Icons.bar_chart_rounded,
          color: const Color(0xFF0A84FF),
          label: 'Completion rate',
          value: '${(summary.completionRate * 100).round()}%',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon:  Icons.timer_outlined,
          color: const Color(0xFFFF453A),
          label: 'Total sessions',
          value: '${summary.totalSessions}',
        ),
      ],
    );
  }
}

// ── Session list tab ──────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final List<FocusSession> sessions;
  const _SessionList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    // Group by date
    final Map<String, List<FocusSession>> grouped = {};
    for (final s in sessions) {
      final key = _dateHeader(s.startedAt);
      grouped.putIfAbsent(key, () => []).add(s);
    }
    final keys = grouped.keys.toList(); // already ordered newest-first

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key      = keys[i];
        final daySessions = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 20),
              child: Text(
                key,
                style: const TextStyle(
                  color:         Colors.white38,
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...daySessions.map((s) => _SessionRow(session: s)),
          ],
        );
      },
    );
  }

  static String _dateHeader(DateTime dt) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'TODAY';
    if (d == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    const months = [
      '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}

// ── Individual session row ────────────────────────────────────────

class _SessionRow extends StatefulWidget {
  final FocusSession session;
  const _SessionRow({required this.session});

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _expanded = false;

  Color get _typeColor => switch (widget.session.type) {
        SessionType.work       => const Color(0xFFFF453A),
        SessionType.shortBreak => const Color(0xFF32D74B),
        SessionType.longBreak  => const Color(0xFF0A84FF),
      };

  /// True when the user actually ran longer than the preset.
  bool get _isOverrun =>
      widget.session.actualSeconds > widget.session.plannedSeconds + 10;

  /// True when the session was cut short (skipped / abandoned).
  bool get _isUnderrun =>
      !widget.session.completed &&
      widget.session.actualSeconds <
          (widget.session.plannedSeconds * 0.85).floor();

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0 && s > 0) return '${m}m ${s}s';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  String _time(DateTime dt) {
    final h  = dt.hour;
    final m  = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final s     = widget.session;
    final color = _typeColor;

    // Overrun delta (extra time beyond preset)
    final overrunSec = s.actualSeconds - s.plannedSeconds;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _expanded ? 0.07 : 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: _expanded ? 0.30 : 0.12),
          ),
        ),
        child: Column(
          children: [
            // ── Collapsed row ─────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Type dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color:  color,
                      shape:  BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:      color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Type + time range
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.type.label,
                          style: TextStyle(
                            color:      color,
                            fontSize:   12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_time(s.startedAt)} → ${_time(s.endedAt)}',
                          style: const TextStyle(
                            color:    Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actual duration + badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(s.actualSeconds),
                        style: TextStyle(
                          color:      color,
                          fontSize:   14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (_isOverrun)
                        _MicroBadge(
                          label: '+${_fmt(overrunSec)}',
                          color: const Color(0xFFFF9F0A),
                        )
                      else if (_isUnderrun)
                        const _MicroBadge(
                          label: 'cut short',
                          color: Colors.white24,
                        )
                      else if (s.completed)
                        _MicroBadge(
                          label: '✓ done',
                          color: const Color(0xFF32D74B),
                        ),
                    ],
                  ),

                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns:    _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white24, size: 16),
                  ),
                ],
              ),
            ),

            // ── Expanded detail ───────────────────────────
            if (_expanded) ...[
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: Colors.white.withValues(alpha: 0.06),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Started',
                      value: '${_time(s.startedAt)}, ${_fullDate(s.startedAt)}',
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Ended',
                      value: '${_time(s.endedAt)}, ${_fullDate(s.endedAt)}',
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Actual',
                      value: _fmt(s.actualSeconds),
                      valueColor: color,
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Planned',
                      value: _fmt(s.plannedSeconds),
                    ),
                    if (_isOverrun) ...[
                      const SizedBox(height: 6),
                      _DetailRow(
                        label: 'Overrun',
                        value: '+${_fmt(overrunSec)} beyond preset',
                        valueColor: const Color(0xFFFF9F0A),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Preset',
                      value: s.preset.label,
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Status',
                      value: s.completed ? 'Completed' : 'Interrupted',
                      valueColor: s.completed
                          ? const Color(0xFF32D74B)
                          : Colors.white38,
                    ),
                    const SizedBox(height: 6),
                    // Efficiency bar
                    Row(
                      children: [
                        const Text('Efficiency',
                            style: TextStyle(
                                color: Colors.white30, fontSize: 11)),
                        const Spacer(),
                        Text(
                          '${(s.efficiency * 100).round()}%',
                          style: TextStyle(
                            color:      color,
                            fontSize:   11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:           s.efficiency.clamp(0.0, 1.0),
                        minHeight:       3,
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        valueColor:      AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fullDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
}

class _MicroBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const _MicroBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:      color,
          fontSize:   9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String  label;
  final String  value;
  final Color?  valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white30, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color:      valueColor ?? Colors.white70,
              fontSize:   11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────

class _BigStat extends StatelessWidget {
  final String value;
  final String label;
  final Color  color;
  const _BigStat(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                  color:      color,
                  fontSize:   16,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  final String   value;
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize:   13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Bar chart ─────────────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<DailyFocusStat> stats;
  final int                  days;
  const _BarChart({required this.stats, required this.days});

  @override
  Widget build(BuildContext context) {
    final recent = stats.length > days
        ? stats.sublist(stats.length - days)
        : stats;
    final maxSec =
        recent.fold(0, (m, e) => math.max(m, e.totalSeconds));

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: recent.map((d) {
          final frac    = maxSec == 0
              ? 0.0
              : (d.totalSeconds / maxSec).clamp(0.0, 1.0);
          final isToday = _dayKey(d.date) == _dayKey(DateTime.now());

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve:    Curves.easeOut,
                    height:   math.max(4.0, frac * 90),
                    decoration: BoxDecoration(
                      color: isToday
                          ? const Color(0xFFFF453A)
                          : (frac > 0
                              ? const Color(0xFFFF453A)
                                  .withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.05)),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (days <= 7)
                    Text(
                      _shortDay(d.date),
                      style: TextStyle(
                        color:    isToday
                            ? Colors.white54
                            : Colors.white24,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month}-${dt.day}';

  static String _shortDay(DateTime dt) {
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    return days[(dt.weekday - 1) % 7];
  }
}

// ── Empty states ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📊', style: TextStyle(fontSize: 40)),
          SizedBox(height: 16),
          Text('No sessions recorded yet.',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
          SizedBox(height: 6),
          Text('Start a focus session to see your data here.',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptySessionsState extends StatelessWidget {
  const _EmptySessionsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🕐', style: TextStyle(fontSize: 32)),
          SizedBox(height: 12),
          Text('No sessions in this period.',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          SizedBox(height: 4),
          Text('Switch to 30d to see older sessions.',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }
}