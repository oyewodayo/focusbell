import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';
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

  // ── Feature 1: Priority filter dropdown ──────────────────────
  Priority? _filterPriority;        // null = show all
  bool      _priorityDropOpen = false;

  // ── Feature 2: Search ────────────────────────────────────────
  bool                        _searchOpen = false;
  String                      _searchQuery = '';
  final TextEditingController _searchCtrl  = TextEditingController();

  // ── Feature 3: Archive toggle ─────────────────────────────────
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

  // ── Filtering + sorting pipeline ─────────────────────────────

  List<Project> _process(List<Project> raw) {
    // 1. Split archive vs live
    var pool = _showArchive
        ? raw.where((p) => p.isArchived).toList()
        : raw.where((p) => !p.isArchived).toList();

    // 2. Priority filter (Feature 1 — dropdown)
    if (_filterPriority != null) {
      pool = pool.where((p) => p.priority == _filterPriority).toList();
    }

    // 3. Search filter (Feature 2)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      pool = pool.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    if (_showArchive) return pool; // archive list: no active pinning

    // 4. Active-first + sort (only for live projects)
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

  // ── Priority labels for the dropdown ─────────────────────────

  static const _priorityMeta = [
    (priority: Priority.critical, emoji: '🔴', label: 'Critical'),
    (priority: Priority.high,     emoji: '🟠', label: 'High'),
    (priority: Priority.medium,   emoji: '🟡', label: 'Medium'),
    (priority: Priority.low,      emoji: '🟢', label: 'Low'),
  ];

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final projects = _process(_ctrl.projects);
        final archivedCount =
            _ctrl.projects.where((p) => p.isArchived).length;

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
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Header row ──────────────────────────────────
             Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                    children: [
                    // Title + archive toggle
                    GestureDetector(
                        onTap: () => setState(() {
                        _showArchive = !_showArchive;
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
                                style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                ),
                            ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: _showArchive
                                    ? const Color(0xFFFF9F0A).withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                color: _showArchive
                                    ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
                                    : Colors.white12,
                                ),
                            ),
                            child: Icon(
                                _showArchive
                                    ? Icons.inventory_2_rounded
                                    : Icons.inventory_2_outlined,
                                size: 13,
                                color: _showArchive
                                    ? const Color(0xFFFF9F0A)
                                    : Colors.white38,
                            ),
                            ),
                            if (archivedCount > 0 && !_showArchive) ...[
                            const SizedBox(width: 4),
                            Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                color: const Color(0xFFFF9F0A).withValues(alpha: 0.2),
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

                    // Sort toggle
                    if (!_showArchive)
                        GestureDetector(
                        onTap: _toggleSort,
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                            color: _sortMode == _SortMode.priority
                                ? const Color(0xFFFFD60A).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _sortMode == _SortMode.priority
                                    ? const Color(0xFFFFD60A).withValues(alpha: 0.4)
                                    : Colors.white12,
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
                                    : Colors.white38,
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

                    // Priority filter caret
                    GestureDetector(
                        onTap: () =>
                            setState(() => _priorityDropOpen = !_priorityDropOpen),
                        child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: _filterPriority != null
                                ? _filterPriority!.color.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                            color: _filterPriority != null
                                ? _filterPriority!.color.withValues(alpha: 0.45)
                                : Colors.white12,
                            ),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            if (_filterPriority != null) ...[
                                Text(
                                _priorityMeta
                                    .firstWhere((m) => m.priority == _filterPriority)
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
                                    : Colors.white38,
                                ),
                            ),
                            ],
                        ),
                        ),
                    ),

                    const SizedBox(width: 6),

                    // Search icon
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: _searchOpen
                                ? const Color(0xFF0A84FF).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                            color: _searchOpen
                                ? const Color(0xFF0A84FF).withValues(alpha: 0.45)
                                : Colors.white12,
                            ),
                        ),
                        child: Icon(
                            _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                            size: 15,
                            color: _searchOpen ? const Color(0xFF0A84FF) : Colors.white38,
                        ),
                        ),
                    ),

                    const Spacer(),

                    if (!_showArchive)
                        _AddButton(onAdded: () => setState(() {})),
                    ],
                ),
            ),

              // ── Feature 1: Priority dropdown ──────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _priorityDropOpen
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              // "All" option
                              _PriorityFilterOption(
                                emoji: '🔘',
                                label: 'All Priorities',
                                selected: _filterPriority == null,
                                color: Colors.white54,
                                onTap: () => setState(() {
                                  _filterPriority   = null;
                                  _priorityDropOpen = false;
                                }),
                              ),
                              const Divider(
                                  height: 1, color: Colors.white10),
                              ..._priorityMeta.map((m) =>
                                  _PriorityFilterOption(
                                    emoji: m.emoji,
                                    label: m.label,
                                    selected:
                                        _filterPriority == m.priority,
                                    color: m.priority.color,
                                    onTap: () => setState(() {
                                      _filterPriority = m.priority;
                                      _priorityDropOpen = false;
                                    }),
                                  )),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Feature 2: Search bar ──────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _searchOpen
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: const TextStyle(
                              color: Color.fromARGB(255, 204, 201, 201), fontSize: 14),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Search projects…',
                            hintStyle: const TextStyle(
                                color: Colors.white38, fontSize: 14),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: Colors.white38, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () => setState(() {
                                      _searchQuery = '';
                                      _searchCtrl.clear();
                                    }),
                                    child: const Icon(Icons.close_rounded,
                                        color: Colors.white38, size: 16),
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF1C1C1C),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0A84FF),
                                  width: 1.5),
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
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11),
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
                        style: const TextStyle(
                            fontSize: 40, color: Colors.white24),
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
                        style: const TextStyle(
                          color: Colors.white38,
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
                    maxHeight: (MediaQuery.of(context).size.height * 0.5) -
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
                    final hasActive = projects.any((p) => p.isActive);
                    if (hasActive && (oldIndex == 0 || newIndex == 0)) return;
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = [...projects];
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    _ctrl.reorderProjects(reordered.map((p) => p.id).toList());
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

// ── Priority filter option row ────────────────────────────────────

class _PriorityFilterOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final Color color;
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white60,
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

// ── Single project row ────────────────────────────────────────────

class _ProjectTile extends StatefulWidget {
  final Project project;
  final bool isArchiveView;

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

  void _showViewSheet(BuildContext context) {
    _closeTray();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectViewSheet(project: widget.project),
    );
  }

  void _showEditSheet(BuildContext context) {
    _closeTray();
    showProjectEditSheet(context, widget.project);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AppController.instance;
    final p = widget.project;
    final isActive = p.isActive;

    // ── Archive view: simpler swipe-to-unarchive tile ─────────
    if (widget.isArchiveView) {
      return Dismissible(
        key: ValueKey('arch_${p.id}'),
        direction: DismissDirection.startToEnd,
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F0A),
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
            AppToast.show(context,
                msg: '"${p.name}" restored',
                backgroundColor: const Color(0xFF1A2A1A),
                textColor: const Color(0xFF34C759));
          }
          return false; // controller handles removal from list
        },
        child: _buildTileBody(context, ctrl, p, isActive),
      );
    }

    // ── Live view: swipe right = archive tray, left = delete ──
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Right swipe → open action tray (archive + original actions)
          setState(() => _actionTrayOpen = !_actionTrayOpen);
          return false;
        }
        // Left swipe → confirm delete
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Delete project?',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            content: Text('"${p.name}" will be permanently removed.',
                style: const TextStyle(
                    color: Colors.white60, fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Color(0xFFFF3B30))),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final name = p.name;
        await ctrl.removeProject(p.id);
        if (!context.mounted) return;
        AppToast.show(context,
            msg: '"$name" deleted',
            backgroundColor: const Color(0xFF222222),
            textColor: Colors.white70);
      },
      // Right-swipe background: archive icon
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1200),
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
      // Left-swipe background: delete
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2E0A0A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline,
            color: Color(0xFFFF3B30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTileBody(context, ctrl, p, isActive),

          // ── Action tray (archive + view + edit) ──────────
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Text('Actions',
                      style: TextStyle(
                          color: Colors.white30, fontSize: 11)),
                  const Spacer(),
                  // ── Archive action ──────────────────────
                  _TrayButton(
                    icon: Icons.inventory_2_outlined,
                    label: 'Archive',
                    color: const Color(0xFFFF9F0A),
                    onTap: () async {
                      _closeTray();
                      await ctrl.archiveProject(p.id);
                      if (context.mounted) {
                        AppToast.show(context,
                            msg: '"${p.name}" archived',
                            backgroundColor:
                                const Color(0xFF1A1200),
                            textColor: const Color(0xFFFF9F0A));
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _TrayButton(
                    icon: Icons.visibility_outlined,
                    label: 'View',
                    color: const Color(0xFF64D2FF),
                    onTap: () => _showViewSheet(context),
                  ),
                  const SizedBox(width: 8),
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

  Widget _buildTileBody(
      BuildContext context, AppController ctrl, Project p, bool isActive) {
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
            backgroundColor: p.priority.bgColor,
            textColor: p.priority.color);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: widget.isArchiveView
              ? const Color(0xFF161616)
              : isActive
                  ? p.priority.bgColor
                  : const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isArchiveView
                ? const Color(0xFFFF9F0A).withValues(alpha: 0.2)
                : isActive
                    ? p.priority.color.withValues(alpha: 0.6)
                    : Colors.white10,
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
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.isArchiveView
                    ? p.priority.color.withValues(alpha: 0.4)
                    : p.priority.color,
                shape: BoxShape.circle,
                boxShadow: isActive && !widget.isArchiveView
                    ? [
                        BoxShadow(
                          color: p.priority.color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p.name,
                style: TextStyle(
                  color: widget.isArchiveView
                      ? Colors.white38
                      : isActive
                          ? Colors.white
                          : Colors.white70,
                  fontSize: 15,
                  fontWeight: isActive && !widget.isArchiveView
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
                color: p.priority.color.withValues(
                    alpha: widget.isArchiveView ? 0.08 : 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p.priority.label,
                style: TextStyle(
                  color: p.priority.color
                      .withValues(alpha: widget.isArchiveView ? 0.5 : 1),
                  fontSize: 11,
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

// ── Tray action button ────────────────────────────────────────────

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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
      onTap: () => showProjectAddDialog(context, onAdded: onAdded),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                style:
                    TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}