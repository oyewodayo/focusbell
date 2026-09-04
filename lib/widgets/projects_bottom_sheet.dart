import 'package:flutter/material.dart';
import 'package:focusbell/screens/home_screen.dart' hide showProjectNoteSheet;
import 'package:focusbell/widgets/project_note_sheet.dart';
import '../models/project.dart';
import '../models/settings.dart';
import '../services/app_controller.dart';
import '../services/pin_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'pin_entry_sheet.dart';
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

  Priority? _filterPriority;
  bool      _priorityDropOpen = false;

  bool                        _searchOpen  = false;
  String                      _searchQuery = '';
  final TextEditingController _searchCtrl  = TextEditingController();

  bool _showArchive = false;

  static const _priorityOrder = {
    Priority.critical: 0,
    Priority.high:     1,
    Priority.medium:   2,
    Priority.low:      3,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Project> _process(List<Project> raw) {
    var pool = _showArchive
        ? raw.where((p) => p.isArchived).toList()
        : raw.where((p) => !p.isArchived).toList();

    if (_filterPriority != null) {
      pool = pool.where((p) => p.priority == _filterPriority).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      pool = pool.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    if (_showArchive) return pool;

    final active = pool.where((p) => p.isActive).toList();
    final rest   = pool.where((p) => !p.isActive).toList();

    if (_sortMode == _SortMode.priority) {
      rest.sort((a, b) =>
          (_priorityOrder[a.priority] ?? 99)
              .compareTo(_priorityOrder[b.priority] ?? 99));
    }

    return [...active, ...rest];
  }

  void _toggleSort() => setState(() {
        _sortMode = _sortMode == _SortMode.manual
            ? _SortMode.priority
            : _SortMode.manual;
      });

  static const _priorityMeta = [
    (priority: Priority.critical, emoji: '🔴', label: 'Critical'),
    (priority: Priority.high,     emoji: '🟠', label: 'High'),
    (priority: Priority.medium,   emoji: '🟡', label: 'Medium'),
    (priority: Priority.low,      emoji: '🟢', label: 'Low'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final fb = Theme.of(context).fb;
        final projects     = _process(_ctrl.projects);
        final archivedCount =
            _ctrl.projects.where((p) => p.isArchived).length;

        return Container(
          decoration: BoxDecoration(
            color: fb.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: fb.onSurfaceFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Header row ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        _showArchive      = !_showArchive;
                        _filterPriority   = null;
                        _searchQuery      = '';
                        _searchCtrl.clear();
                        _searchOpen       = false;
                        _priorityDropOpen = false;
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _showArchive ? 'Archive' : 'Projects',
                              key: ValueKey(_showArchive),
                              style: TextStyle(
                                color: fb.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _showArchive
                                  ? const Color(0xFFFF9F0A)
                                      .withValues(alpha: 0.2)
                                  : fb.onSurface
                                      .withValues(alpha: fb.isDark ? 0.06 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _showArchive
                                    ? const Color(0xFFFF9F0A)
                                        .withValues(alpha: 0.5)
                                    : fb.border,
                              ),
                            ),
                            child: Icon(
                              _showArchive
                                  ? Icons.inventory_2_rounded
                                  : Icons.inventory_2_outlined,
                              size: 13,
                              color: _showArchive
                                  ? const Color(0xFFFF9F0A)
                                  : fb.onSurface.withValues(alpha: 0.38),
                            ),
                          ),
                          if (archivedCount > 0 && !_showArchive) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9F0A)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$archivedCount',
                                style: const TextStyle(
                                  color: Color(0xFFFF9F0A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    if (!_showArchive)
                      GestureDetector(
                        onTap: _toggleSort,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _sortMode == _SortMode.priority
                                ? const Color(0xFFFFD60A)
                                    .withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _sortMode == _SortMode.priority
                                  ? const Color(0xFFFFD60A)
                                      .withValues(alpha: 0.4)
                                  : fb.border,
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
                                    : fb.onSurface.withValues(alpha: 0.38),
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

                    const SizedBox(width: 6),

                    GestureDetector(
                      onTap: () => setState(
                          () => _priorityDropOpen = !_priorityDropOpen),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _filterPriority != null
                              ? _filterPriority!.color
                                  .withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _filterPriority != null
                                ? _filterPriority!.color
                                    .withValues(alpha: 0.45)
                                : fb.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_filterPriority != null) ...[
                              Text(
                                _priorityMeta
                                    .firstWhere(
                                        (m) => m.priority == _filterPriority)
                                    .emoji,
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 3),
                            ],
                            AnimatedRotation(
                              turns: _priorityDropOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: _filterPriority != null
                                    ? _filterPriority!.color
                                    : fb.onSurface.withValues(alpha: 0.38),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchOpen = !_searchOpen;
                          if (!_searchOpen) {
                            _searchQuery = '';
                            _searchCtrl.clear();
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _searchOpen
                              ? const Color(0xFF0A84FF).withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _searchOpen
                                ? const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.45)
                                : fb.border,
                          ),
                        ),
                        child: Icon(
                          _searchOpen
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                          size: 15,
                          color: _searchOpen
                              ? const Color(0xFF0A84FF)
                              : fb.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ),

                    const Spacer(),

                    if (!_showArchive)
                      _AddButton(onAdded: () => setState(() {})),
                  ],
                ),
              ),

              // ── Priority dropdown ──────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _priorityDropOpen
                    ? Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: fb.surfaceVar,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: fb.border),
                          ),
                          child: Column(
                            children: [
                              _PriorityFilterOption(
                                emoji: '🔘',
                                label: 'All Priorities',
                                selected: _filterPriority == null,
                                color: fb.onSurface.withValues(alpha: 0.54),
                                onTap: () => setState(() {
                                  _filterPriority   = null;
                                  _priorityDropOpen = false;
                                }),
                              ),
                              Divider(height: 1, color: fb.border),
                              ..._priorityMeta.map((m) => _PriorityFilterOption(
                                    emoji:    m.emoji,
                                    label:    m.label,
                                    selected: _filterPriority == m.priority,
                                    color:    m.priority.color,
                                    onTap: () => setState(() {
                                      _filterPriority   = m.priority;
                                      _priorityDropOpen = false;
                                    }),
                                  )),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Search bar ─────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _searchOpen
                    ? Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: TextStyle(
                              color: fb.onSurface,
                              fontSize: 14),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Search projects…',
                            hintStyle: TextStyle(
                                color: fb.onSurface.withValues(alpha: 0.38), fontSize: 14),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: fb.onSurface.withValues(alpha: 0.38), size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () => setState(() {
                                      _searchQuery = '';
                                      _searchCtrl.clear();
                                    }),
                                    child: Icon(Icons.close_rounded,
                                        color: fb.onSurface.withValues(alpha: 0.38), size: 16),
                                  )
                                : null,
                            filled: true,
                            fillColor: fb.surfaceVar,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0A84FF), width: 1.5),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      _showArchive
                          ? 'Tap archive icon to go back'
                          : 'Double-tap to activate · Drag to reorder',
                      style: TextStyle(
                          color: fb.onSurfaceFaint, fontSize: 11),
                    ),
                    if (_filterPriority != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _filterPriority = null),
                        child: Text(
                          'Clear filter',
                          style: TextStyle(
                            color: _filterPriority!.color
                                .withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text(
                        _showArchive ? '📦' : '📋',
                        style: TextStyle(
                            fontSize: 40, color: fb.onSurfaceFaint),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _showArchive
                            ? 'No archived projects.'
                            : _searchQuery.isNotEmpty
                                ? 'No projects match "$_searchQuery".'
                                : _filterPriority != null
                                    ? 'No ${_filterPriority!.label} projects.'
                                    : 'No projects yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: fb.onSurface.withValues(alpha: 0.38),
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
                    maxHeight:
                        (MediaQuery.of(context).size.height * 0.5) -
                            MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: projects.length,
                    proxyDecorator: (child, index, animation) =>
                        Material(color: Colors.transparent, child: child),
                    onReorder: (oldIndex, newIndex) {
                      if (_showArchive) return;
                      final hasActive =
                          projects.any((p) => p.isActive);
                      if (hasActive &&
                          (oldIndex == 0 || newIndex == 0)) return;
                      if (newIndex > oldIndex) newIndex--;
                      final reordered = [...projects];
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      _ctrl.reorderProjects(
                          reordered.map((p) => p.id).toList());
                    },
                    itemBuilder: (ctx, i) {
                      final project = projects[i];
                      return _ProjectTile(
                        key: ValueKey(project.id),
                        project: project,
                        isArchiveView: _showArchive,
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

// ── Priority filter option ────────────────────────────────────────

class _PriorityFilterOption extends StatelessWidget {
  final String       emoji;
  final String       label;
  final bool         selected;
  final Color        color;
  final VoidCallback onTap;

  const _PriorityFilterOption({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : fb.onSurfaceDim,
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (selected) ...[
              const Spacer(),
              Icon(Icons.check_rounded, color: color, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Single project tile ───────────────────────────────────────────

class _ProjectTile extends StatefulWidget {
  final Project project;
  final bool    isArchiveView;

  const _ProjectTile({
    Key? key,
    required this.project,
    this.isArchiveView = false,
  }) : super(key: key);

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  bool _actionTrayOpen = false;

  void _closeTray() => setState(() => _actionTrayOpen = false);

  void _showViewSheet() {
    _closeTray();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectViewSheet(project: widget.project),
    );
  }

  void _showEditSheet() {
    _closeTray();
    showProjectEditSheet(context, widget.project);
  }

  // ── PIN-gated note open ─────────────────────────────────────────
  //
  // Always read the LIVE project from AppController so we never act
  // on a stale `isNoteLocked` captured at widget construction time.
  Future<void> _openNote() async {
    _closeTray();

    // Re-read from controller — widget.project may be stale.
    final live = AppController.instance.projects
        .where((p) => p.id == widget.project.id)
        .firstOrNull;
    if (live == null) return;

    if (live.isNoteLocked) {
      final settings = AppController.instance.settings;

      // Edge case: note locked but PIN was later removed — auto-unlock.
      if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
        await AppController.instance.updateProjectLockState(
          live.id,
          isNoteLocked: false,
        );
        if (!mounted) return;
        showProjectNoteSheet(context, project: live);
        return;
      }

      final ok = await showPinEntry<bool>(
        context,
        mode:       PinEntryMode.verify,
        storedHash: settings.pinHash,
        title:      'Enter PIN to open note',
        subtitle:   live.name,
      );
      if (ok != true || !mounted) return;
    }

    if (!mounted) return;
    showProjectNoteSheet(context, project: live);
  }

  // ── Lock / Unlock from the action tray ─────────────────────────

  Future<void> _toggleLock() async {
    _closeTray();

    // Always read live state to avoid stale captures.
    final live = AppController.instance.projects
        .where((p) => p.id == widget.project.id)
        .firstOrNull;
    if (live == null || !mounted) return;

    final settings = AppController.instance.settings;

    if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
      _showNoPinDialog();
      return;
    }

    if (live.isNoteLocked) {
      // Unlock: verify PIN first.
      final ok = await showPinEntry<bool>(
        context,
        mode:       PinEntryMode.verify,
        storedHash: settings.pinHash,
        title:      'Enter PIN to unlock note',
      );
      if (ok != true || !mounted) return;

      await AppController.instance.updateProjectLockState(
        live.id,
        isNoteLocked: false,
      );

      if (mounted) {
        AppToast.success(context, '🔓 Note unlocked');
      }
    } else {
      // Lock: no PIN needed — user is in the app.
      await AppController.instance.updateProjectLockState(
        live.id,
        isNoteLocked: true,
      );

      if (mounted) {
        // NOTE: kept as a fixed navy/cyan "info" tint — not a success/
        // warning/danger case, and there's no theme token for it yet.
        AppToast.show(
          context,
          msg: '🔒 Note locked',
          backgroundColor: const Color(0xFF1A1A2E),
          textColor: const Color(0xFF64D2FF),
        );
      }
    }
  }

  void _showNoPinDialog() {
    final fb = Theme.of(context).fb;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: fb.surfaceVar,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('No PIN set',
            style: TextStyle(color: fb.onSurface, fontSize: 17)),
        content: Text(
          'Go to Settings → Security to set a PIN before locking notes.',
          style: TextStyle(color: fb.onSurfaceDim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: TextStyle(color: fb.success)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb       = Theme.of(context).fb;
    final ctrl     = AppController.instance;
    final p        = widget.project;
    final isActive = p.isActive;

    // Read live lock state so the tray label updates reactively.
    final liveLocked = ctrl.projects
        .where((lp) => lp.id == p.id)
        .firstOrNull
        ?.isNoteLocked ??
        p.isNoteLocked;

    // ── Archive view ──────────────────────────────────────────────
    if (widget.isArchiveView) {
      return Dismissible(
        key: ValueKey('arch_${p.id}'),
        direction: DismissDirection.startToEnd,
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: fb.successBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.unarchive_rounded,
                  color: Color(0xFF34C759), size: 18),
              SizedBox(width: 6),
              Text('Unarchive',
                  style: TextStyle(
                      color: Color(0xFF34C759),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        confirmDismiss: (_) async {
          await ctrl.unarchiveProject(p.id);
          if (context.mounted) {
            AppToast.success(context, '"${p.name}" restored');
          }
          return false;
        },
        child: _buildTileBody(context, ctrl, p, isActive, liveLocked),
      );
    }

    // ── Live view ─────────────────────────────────────────────────
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
            backgroundColor: fb.surfaceVar,
            title: Text('Delete project?',
                style: TextStyle(color: fb.onSurface, fontSize: 17)),
            content: Text('"${p.name}" will be permanently removed.',
                style: TextStyle(
                    color: fb.onSurfaceDim, fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: fb.onSurface.withValues(alpha: 0.54))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete',
                    style: TextStyle(color: fb.danger)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final name = p.name;
        await ctrl.removeProject(p.id);
        if (!context.mounted) return;
        AppToast.show(context, msg: '"$name" deleted');
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: fb.warningBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_rounded,
                color: Color(0xFFFF9F0A), size: 18),
            SizedBox(width: 6),
            Text('Archive',
                style: TextStyle(
                    color: Color(0xFFFF9F0A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: fb.dangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: fb.danger),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTileBody(context, ctrl, p, isActive, liveLocked),

          // ── Action tray ────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            firstCurve:  Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: _actionTrayOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: fb.surfaceVar,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                border: Border.all(color: fb.border),
              ),
              child: Row(
                children: [
                  Text('Actions',
                      style: TextStyle(
                          color: fb.onSurface.withValues(alpha: 0.30), fontSize: 11)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // ── Note (PIN-gated) ────────────────
                          _TrayButton(
                            icon:  Icons.sticky_note_2_outlined,
                            label: 'Note',
                            color: const Color(0xFF0A84FF),
                            // Show a lock badge on the icon when locked.
                            badge: liveLocked ? Icons.lock_rounded : null,
                            onTap: _openNote,
                          ),
                          const SizedBox(width: 8),

                          // ── Lock / Unlock ───────────────────
                          _TrayButton(
                            icon: liveLocked
                                ? Icons.lock_open_rounded
                                : Icons.lock_outline_rounded,
                            label: liveLocked ? 'Unlock' : 'Lock',
                            color: liveLocked
                                ? const Color(0xFFFF9F0A)
                                : fb.success,
                            onTap: _toggleLock,
                          ),
                          const SizedBox(width: 8),

                          // ── View ────────────────────────────
                          _TrayButton(
                            icon:  Icons.visibility_outlined,
                            label: 'View',
                            color: const Color(0xFF64D2FF),
                            onTap: _showViewSheet,
                          ),
                          const SizedBox(width: 8),

                          // ── Edit ────────────────────────────
                          _TrayButton(
                            icon:  Icons.edit_outlined,
                            label: 'Edit',
                            color: const Color(0xFFFFD60A),
                            onTap: _showEditSheet,
                          ),
                          const SizedBox(width: 8),

                          // ── Archive ─────────────────────────
                          _TrayButton(
                            icon:  Icons.inventory_2_outlined,
                            label: 'Archive',
                            color: const Color(0xFFFF9F0A),
                            onTap: () async {
                              _closeTray();
                              await ctrl.archiveProject(p.id);
                              if (context.mounted) {
                                AppToast.warning(
                                    context, '"${p.name}" archived');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTileBody(
    BuildContext   context,
    AppController  ctrl,
    Project        p,
    bool           isActive,
    bool           liveLocked,
  ) {
    final fb = Theme.of(context).fb;
    return GestureDetector(
      onTap: () {
        if (!widget.isArchiveView) {
          setState(() => _actionTrayOpen = !_actionTrayOpen);
        }
      },
      onDoubleTap: () async {
        if (isActive || widget.isArchiveView) return;
        await ctrl.setActive(p.id);
        if (!context.mounted) return;
        AppToast.show(context,
            msg: '${p.priority.emoji} Now: ${p.name}',
            backgroundColor: p.priority.bgColor(fb.isDark),
            textColor:       p.priority.color);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin:  const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: widget.isArchiveView
              ? fb.card
              : isActive
                  ? p.priority.bgColor(fb.isDark)
                  : fb.surfaceVar,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isArchiveView
                ? const Color(0xFFFF9F0A).withValues(alpha: 0.2)
                : isActive
                    ? p.priority.color.withValues(alpha: 0.6)
                    : fb.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (widget.isArchiveView)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.inventory_2_outlined,
                    size: 13, color: Color(0xFFFF9F0A)),
              )
            else if (isActive)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.push_pin_rounded,
                    size: 13,
                    color: p.priority.color.withValues(alpha: 0.8)),
              ),
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: widget.isArchiveView
                    ? p.priority.color.withValues(alpha: 0.4)
                    : p.priority.color,
                shape: BoxShape.circle,
                boxShadow: isActive && !widget.isArchiveView
                    ? [BoxShadow(
                        color:      p.priority.color.withValues(alpha: 0.5),
                        blurRadius: 6,
                      )]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p.name,
                style: TextStyle(
                  color: widget.isArchiveView
                      ? fb.onSurface.withValues(alpha: 0.38)
                      : isActive
                          ? fb.onSurface
                          : fb.onSurface.withValues(alpha: 0.70),
                  fontSize:   15,
                  fontWeight: isActive && !widget.isArchiveView
                      ? FontWeight.w600
                      : FontWeight.w400,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // ── Lock indicator dot on the tile ───────────────
            if (liveLocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded,
                  size: 12, color: fb.success),
            ],

            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.priority.color.withValues(
                    alpha: widget.isArchiveView
                        ? (fb.isDark ? 0.08 : 0.12)
                        : (fb.isDark ? 0.15 : 0.20)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p.priority.label,
                style: TextStyle(
                  color: p.priority.color.withValues(
                      alpha: widget.isArchiveView ? 0.5 : 1),
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (isActive && !widget.isArchiveView) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded,
                  color: p.priority.color, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tray button ───────────────────────────────────────────────────

class _TrayButton extends StatelessWidget {
  final IconData   icon;
  final String     label;
  final Color      color;
  final VoidCallback onTap;
  /// Optional small badge icon overlaid on the top-right of the main icon.
  final IconData?  badge;

  const _TrayButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main icon with optional badge overlay.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 14),
                if (badge != null)
                  Positioned(
                    top: -4, right: -4,
                    child: Icon(badge, size: 8, color: color),
                  ),
              ],
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color:      color,
                fontSize:   12,
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
    final fb = Theme.of(context).fb;
    return GestureDetector(
      onTap: () => showProjectAddDialog(context, onAdded: onAdded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:        fb.surfaceVar,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: fb.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: fb.onSurface.withValues(alpha: 0.54), size: 16),
            const SizedBox(width: 4),
            Text('Add', style: TextStyle(color: fb.onSurface.withValues(alpha: 0.54), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
