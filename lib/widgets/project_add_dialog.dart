import 'package:flutter/material.dart';
import 'package:focusbell/widgets/finance_info_dialog.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';

Future<void> showProjectAddDialog(
  BuildContext context, {
  required VoidCallback onAdded,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    builder: (ctx) => _ProjectAddSheet(onAdded: onAdded),
  );
}

class _ProjectAddSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _ProjectAddSheet({required this.onAdded});

  @override
  State<_ProjectAddSheet> createState() => _ProjectAddSheetState();
}

class _ProjectAddSheetState extends State<_ProjectAddSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Priority _priority = Priority.medium;
  ProjectCategory _category = ProjectCategory.general;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = keyboardHeight > 0
        ? keyboardHeight + 24
        : MediaQuery.of(context).padding.bottom + 24;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding),
        child: SingleChildScrollView(
          // Prevent scroll from fighting the sheet's own resize
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ───────────────────────────────────────
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // ── Title ────────────────────────────────────────
              const Text(
                'New Project',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),

              // ── Name field ───────────────────────────────────
              TextField(
                controller: _nameCtrl,
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
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── Description field ─────────────────────────────
              TextField(
                maxLines: 3,
                controller: _descCtrl,
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
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),

           

            // ── Category label ────────────────────────────────────────────
            Row(
              children: [
                const Text(
                'Category',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                SizedBox(width: 4),
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
              ],
            ),
             
            const SizedBox(height: 8),


            // ── Category chips ────────────────────────────────────────────
            Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ProjectCategory.values.map((c) {
                final selected = c == _category;
                return GestureDetector(
                onTap: () => setState(() => _category = c),
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF0A84FF).withValues(alpha: 0.15)
                        : const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.6)
                            : Colors.white10,
                        width: 1.5,
                    ),
                    ),
                    child: Text(
                    '${c.emoji} ${c.label}',
                    style: TextStyle(
                        color: selected ? const Color(0xFF0A84FF) : Colors.white38,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    ),
                ),
                );
            }).toList(),
            ),
              // ── Priority label ────────────────────────────────
              const Text(
                'Priority',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),

              // ── Priority chips ────────────────────────────────
              Row(
                children: Priority.values.map((p) {
                  final selected = p == _priority;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _priority = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? p.bgColor : const Color(0xFF252525),
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
                            Text(p.emoji, style: const TextStyle(fontSize: 14)),
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
              const SizedBox(height: 24),

              // ── Actions ───────────────────────────────────────
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        // Dismiss keyboard BEFORE closing sheet so the
                        // padding animates away cleanly with no overflow.
                        FocusScope.of(context).unfocus();
                        await Future.delayed(const Duration(milliseconds: 150));
                        if (!context.mounted) return;
                        await AppController.instance.addProject(
                          name,                         
                          _priority,
                          _descCtrl.text.trim(),
                           _category
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        widget.onAdded();
                        AppToast.show(
                          context,
                          msg: '${_priority.emoji} "$name" added',
                          backgroundColor: _priority.bgColor,
                          textColor: _priority.color,
                        );
                      },
                      child: const Text(
                        'Add Project',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
