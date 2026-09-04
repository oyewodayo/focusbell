import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/settings.dart';
import '../services/app_controller.dart';
import '../services/notification_service.dart';
import '../services/pin_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'pin_entry_sheet.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({super.key});

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  late AppSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = AppController.instance.settings;
  }

  Future<void> _save() async {
    await AppController.instance.updateSettings(_draft);
    if (!mounted) return;
    AppToast.success(context, '✓ Settings saved');
    Navigator.pop(context);
  }

  // ─────────────────────────────────────────────────────────────
  // PIN management
  // ─────────────────────────────────────────────────────────────

  bool get _pinIsSet => PinService.isSet(_draft.pinHash) && _draft.pinEnabled;

  /// Called when the user taps "Set PIN" — opens the setup flow.
  Future<void> _onSetPin() async {
    final newPin = await showPinEntry<String?>(
      context,
      mode:     PinEntryMode.setup,
      subtitle: 'This PIN will be used to lock individual notes.',
    );
    if (newPin == null || !mounted) return;

    setState(() {
      _draft = _draft.copyWith(
        pinHash:    PinService.hash(newPin),
        pinEnabled: true,
      );
    });
    AppToast.success(context, '✓ PIN set successfully');
  }

  /// Called when the user taps "Change PIN" — verifies old then sets new.
  Future<void> _onChangePin() async {
    final newPin = await showPinEntry<String?>(
      context,
      mode:       PinEntryMode.change,
      storedHash: _draft.pinHash,
    );
    if (newPin == null || !mounted) return;

    setState(() {
      _draft = _draft.copyWith(pinHash: PinService.hash(newPin));
    });
    AppToast.success(context, '✓ PIN changed successfully');
  }

  /// Called when the user taps "Remove PIN" — verifies before removing.
  Future<void> _onRemovePin() async {
    // Require the current PIN before removal to prevent accidental lock-outs.
    final confirmed = await showPinEntry<bool>(
      context,
      mode:       PinEntryMode.verify,
      storedHash: _draft.pinHash,
      title:      'Enter PIN to remove it',
    );
    if (confirmed != true || !mounted) return;

    // Confirm destructive action.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogFb = Theme.of(ctx).fb;
        return AlertDialog(
          backgroundColor: dialogFb.surfaceVar,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Remove PIN?',
            style: TextStyle(color: dialogFb.onSurface, fontSize: 17),
          ),
          content: Text(
            'All locked notes will become accessible without a PIN.',
            style: TextStyle(color: dialogFb.onSurfaceDim, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: dialogFb.onSurface.withValues(alpha: 0.54)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: TextStyle(color: dialogFb.danger)),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    setState(() {
      // Clear the hash but keep pinEnabled=false.
      // Passing null explicitly via the sentinel in copyWith.
      _draft = _draft.copyWith(
        pinHash:    null,
        pinEnabled: false,
      );
    });
    if (!mounted) return;
    AppToast.error(context, 'PIN removed');
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Container(
      decoration: BoxDecoration(
        color: fb.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle + header ────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: fb.onSurfaceFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    color: fb.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: fb.successBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: fb.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        color: fb.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Scrollable body ────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Notifications ────────────────────────────────
                  _Section(
                    children: [
                      _Row(
                        icon: Icons.notifications_outlined,
                        label: 'Reminders',
                        trailing: CupertinoSwitch(
                          value: _draft.notificationsEnabled,
                          activeTrackColor: fb.primary,
                          onChanged: (v) async {
                            if (v) {
                              final granted = await NotificationService.instance
                                  .requestPermissions();
                              if (!mounted) return;
                              if (!granted) {
                                AppToast.error(
                                  context,
                                  'Notification permission denied.',
                                );
                                return;
                              }
                            }
                            setState(() {
                              _draft = _draft.copyWith(notificationsEnabled: v);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Alert style ──────────────────────────────────
                  _Section(
                    header: 'Alert style',
                    children: SoundMode.values.map((mode) {
                      final selected = _draft.soundMode == mode;
                      return _SelectRow(
                        label:    '${mode.emoji}  ${mode.label}',
                        selected: selected,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(soundMode: mode),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // ── Remind me interval ───────────────────────────
                  _Section(
                    header: 'Remind me',
                    children: ReminderInterval.displayOrder.map((interval) {
                      final selected = _draft.interval == interval;
                      return _SelectRow(
                        label:    interval.label,
                        selected: selected,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(interval: interval),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // ── Quiet hours ──────────────────────────────────
                  _Section(
                    header: 'Quiet hours (no notifications)',
                    children: [
                      _TimePickerRow(
                        icon:      Icons.bedtime_outlined,
                        label:     'From',
                        hour:      _draft.quietStartHour,
                        onChanged: (h) => setState(
                          () => _draft = _draft.copyWith(quietStartHour: h),
                        ),
                      ),
                      Divider(color: fb.border, height: 1),
                      _TimePickerRow(
                        icon:      Icons.wb_sunny_outlined,
                        label:     'Until',
                        hour:      _draft.quietEndHour,
                        onChanged: (h) => setState(
                          () => _draft = _draft.copyWith(quietEndHour: h),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Passed reminders ─────────────────────────────
                  _Section(
                    header: 'Delete passed reminders',
                    children: ReminderAutoDelete.values.map((option) {
                      final selected = _draft.reminderAutoDelete == option;
                      return _SelectRow(
                        label:    option.label,
                        selected: selected,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(reminderAutoDelete: option),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                    // ── Appearance ───────────────────────────────────────────────────
                    _Section(
                    header: 'Appearance',
                    children: AppThemeMode.values.map((mode) {
                        final selected = _draft.themeMode == mode;
                        return _SelectRow(
                        label:    '${mode.emoji}  ${mode.label}',
                        selected: selected,
                        onTap:    () => setState(
                            () => _draft = _draft.copyWith(themeMode: mode),
                        ),
                        );
                    }).toList(),
                    ),
                    const SizedBox(height: 12),
                  // ── Security / PIN ───────────────────────────────
                  _Section(
                    header: 'Security',
                    children: [
                      _PinRow(
                        pinIsSet:  _pinIsSet,
                        onSet:     _onSetPin,
                        onChange:  _onChangePin,
                        onRemove:  _onRemovePin,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PinRow — PIN management entry inside the Security section
// ─────────────────────────────────────────────────────────────────────────────

class _PinRow extends StatelessWidget {
  final bool           pinIsSet;
  final VoidCallback   onSet;
  final VoidCallback   onChange;
  final VoidCallback   onRemove;

  const _PinRow({
    required this.pinIsSet,
    required this.onSet,
    required this.onChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Lock icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: pinIsSet ? fb.successBg : fb.surfaceVar,
              shape: BoxShape.circle,
              border: Border.all(
                color: pinIsSet
                    ? fb.success.withValues(alpha: 0.35)
                    : fb.border,
              ),
            ),
            child: Icon(
              pinIsSet ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: pinIsSet ? fb.success : fb.onSurface.withValues(alpha: 0.38),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),

          // Label + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Note PIN lock',
                  style: TextStyle(color: fb.onSurface, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  pinIsSet ? 'PIN is active' : 'No PIN set',
                  style: TextStyle(
                    color: pinIsSet
                        ? fb.success.withValues(alpha: 0.8)
                        : fb.onSurface.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Action button(s)
          if (!pinIsSet)
            _PinActionButton(
              label: 'Set PIN',
              color: fb.success,
              onTap: onSet,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PinActionButton(
                  label: 'Change',
                  color: const Color(0xFF64D2FF),
                  onTap: onChange,
                ),
                const SizedBox(width: 8),
                _PinActionButton(
                  label:    'Remove',
                  color:    fb.danger,
                  onTap:    onRemove,
                  outlined: true,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PinActionButton extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  final bool         outlined;

  const _PinActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:        outlined ? Colors.transparent : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withValues(alpha: outlined ? 0.5 : 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      color,
            fontSize:   12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable section widgets (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String?       header;
  final List<Widget>  children;
  const _Section({this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                header!,
                style: TextStyle(
                  color: fb.onSurface.withValues(alpha: 0.38),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              color:        fb.surfaceVar,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: fb.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: children.asMap().entries.expand((entry) {
                final isLast = entry.key == children.length - 1;
                return [
                  entry.value,
                  if (!isLast) Divider(height: 1, color: fb.border),
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Widget   trailing;
  const _Row({required this.icon, required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: fb.onSurface.withValues(alpha: 0.38), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(color: fb.onSurface, fontSize: 15)),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _SelectRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color:      selected ? fb.onSurface : fb.onSurfaceDim,
                  fontSize:   15,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: fb.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TimePickerRow extends StatelessWidget {
  final IconData          icon;
  final String            label;
  final int               hour;
  final ValueChanged<int> onChanged;
  const _TimePickerRow({
    required this.icon,
    required this.label,
    required this.hour,
    required this.onChanged,
  });

  String _fmt(int h) {
    final suffix  = h < 12 ? 'AM' : 'PM';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display:00 $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;

    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary:   fb.primary,
                onSurface: fb.onSurface,
                surface:   fb.surfaceVar,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked.hour);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: fb.onSurface.withValues(alpha: 0.38), size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: fb.onSurface, fontSize: 15)),
            ),
            Text(_fmt(hour),
                style: TextStyle(color: fb.primary, fontSize: 14)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: fb.onSurfaceFaint, size: 16),
          ],
        ),
      ),
    );
  }
}
