import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../services/pin_service.dart';
import '../theme/app_theme.dart';
import 'pin_entry_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NoteLockButton
//
// Drop-in widget for locking/unlocking an individual note behind the app PIN.
//
// Two visual variants controlled by [compact]:
//   false (default) → labelled pill for the note sheet top bar
//   true            → icon-only for project/note list cards
//
// The widget is self-contained: it reads AppSettings, runs the PIN flow,
// then calls AppController.instance.updateProjectLockState() to persist.
// The parent only needs to supply [onChanged] for a local setState().
// ─────────────────────────────────────────────────────────────────────────────

class NoteLockButton extends StatelessWidget {
  final Project      project;

  /// Called after the lock state successfully changes so the parent
  /// widget can trigger a visual rebuild (e.g. setState(() {})).
  final VoidCallback onChanged;

  /// true  → small icon button (list cards)
  /// false → labelled pill (note sheet top bar)
  final bool compact;

  const NoteLockButton({
    super.key,
    required this.project,
    required this.onChanged,
    this.compact = false,
  });

  // ─────────────────────────────────────────────────────────────
  // Core toggle logic
  // ─────────────────────────────────────────────────────────────

  Future<void> _toggle(BuildContext context) async {
    final settings = AppController.instance.settings;

    // Guard: no PIN configured — guide user to Settings first.
    if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
      _showNoPinDialog(context);
      return;
    }

    HapticFeedback.lightImpact();

    if (project.isNoteLocked) {
      // ── Unlock requires PIN verification ───────────────────
      final ok = await showPinEntry<bool>(
        context,
        mode:       PinEntryMode.verify,
        storedHash: settings.pinHash,
        title:      'Enter PIN to unlock note',
      );
      if (ok != true) return;

      await AppController.instance.updateProjectLockState(
        project.id,
        isNoteLocked: false,
      );
    } else {
      // ── Lock needs no PIN — user is already in the app ─────
      await AppController.instance.updateProjectLockState(
        project.id,
        isNoteLocked: true,
      );
    }

    onChanged();
  }

  // ─────────────────────────────────────────────────────────────
  // No-PIN dialog
  // ─────────────────────────────────────────────────────────────

  void _showNoPinDialog(BuildContext context) {
    final fb = Theme.of(context).fb;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: fb.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'No PIN set',
          style: TextStyle(color: fb.onSurface, fontSize: 17),
        ),
        content: Text(
          'Go to Settings → Security to set a PIN before locking notes.',
          style: TextStyle(color: fb.onSurfaceDim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: fb.primary)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return compact ? _buildIconOnly(context) : _buildPill(context);
  }

  // ── Compact: small icon for list cards ──────────────────────

  Widget _buildIconOnly(BuildContext context) {
    final fb     = Theme.of(context).fb;
    final locked = project.isNoteLocked;
    return GestureDetector(
      onTap:    () => _toggle(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            key:   ValueKey(locked),
            size:  16,
            color: locked ? fb.success : fb.onSurfaceFaint,
          ),
        ),
      ),
    );
  }

  // ── Full pill: labelled button for the note sheet top bar ───

  Widget _buildPill(BuildContext context) {
    final fb     = Theme.of(context).fb;
    final locked = project.isNoteLocked;
    return GestureDetector(
      onTap: () => _toggle(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: locked ? fb.successBg : fb.surfaceVar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: locked
                ? fb.success.withValues(alpha: 0.4)
                : fb.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                key:   ValueKey(locked),
                size:  12,
                color: locked ? fb.success : fb.onSurface.withValues(alpha: 0.38),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              locked ? 'Locked' : 'Lock',
              style: TextStyle(
                color:      locked ? fb.success : fb.onSurface.withValues(alpha: 0.38),
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

// ─────────────────────────────────────────────────────────────────────────────
// tryOpenLockedNote — await this before pushing the note sheet
//
// Returns true  → note may be opened
//         false → user cancelled or gave wrong PIN
//
// Usage:
  // onTap: () async {
  //   final canOpen = await tryOpenLockedNote(context, project);
  //   if (!canOpen || !context.mounted) return;
  //   showProjectNoteSheet(context, project: project);
  // },
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> tryOpenLockedNote(BuildContext context, Project project) async {
  // Not locked — open immediately.
  if (!project.isNoteLocked) return true;

  final settings = AppController.instance.settings;

  // Edge case: note is locked but the PIN was removed after locking.
  // Auto-unlock so the user is never permanently locked out.
  if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
    await AppController.instance.updateProjectLockState(
      project.id,
      isNoteLocked: false,
    );
    return true;
  }

  // Show PIN entry and return whether it succeeded.
  final ok = await showPinEntry<bool>(
    context,
    mode:       PinEntryMode.verify,
    storedHash: settings.pinHash,
    title:      'Enter PIN to open note',
    subtitle:   project.name,
  );

  return ok == true;
}