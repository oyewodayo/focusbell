import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/settings.dart';
import '../services/app_controller.dart';
import '../services/notification_service.dart';
import '../utils/app_toast.dart';

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
    AppToast.show(
      context,
      msg: '✓ Settings saved',
      backgroundColor: const Color(0xFF1C2E1C),
      textColor: const Color(0xFF4CAF50),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
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
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2E1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Notifications toggle
          _Section(
            children: [
              _Row(
                icon: Icons.notifications_outlined,
                label: 'Reminders',
                trailing: CupertinoSwitch(
                  value: _draft.notificationsEnabled,
                  activeTrackColor: const Color(0xFF4CAF50),
                  onChanged: (v) async {
                    if (v) {
                      final granted = await NotificationService.instance
                          .requestPermissions();
                      if (!mounted) return;
                      if (!granted) {
                        AppToast.show(
                          context,
                          msg: 'Notification permission denied.',
                          backgroundColor: const Color(0xFF2E0A0A),
                          textColor: const Color(0xFFFF3B30),
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

          // Interval
          _Section(
            header: 'Remind me',
            children: ReminderInterval.values.map((interval) {
              final selected = _draft.interval == interval;
              return _SelectRow(
                label: interval.label,
                selected: selected,
                onTap: () => setState(
                    () => _draft = _draft.copyWith(interval: interval)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Quiet hours
          _Section(
            header: 'Quiet hours (no notifications)',
            children: [
              _TimePickerRow(
                icon: Icons.bedtime_outlined,
                label: 'From',
                hour: _draft.quietStartHour,
                onChanged: (h) => setState(
                    () => _draft = _draft.copyWith(quietStartHour: h)),
              ),
              const Divider(color: Colors.white10, height: 1),
              _TimePickerRow(
                icon: Icons.wb_sunny_outlined,
                label: 'Until',
                hour: _draft.quietEndHour,
                onChanged: (h) =>
                    setState(() => _draft = _draft.copyWith(quietEndHour: h)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Reusable section card ─────────────────────────────────────────

class _Section extends StatelessWidget {
  final String? header;
  final List<Widget> children;
  const _Section({this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(header!,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5)),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: children
                  .asMap()
                  .entries
                  .expand((entry) {
                    final isLast = entry.key == children.length - 1;
                    return [
                      entry.value,
                      if (!isLast)
                        const Divider(height: 1, color: Colors.white10),
                    ];
                  })
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable row widget ─────────────────────────────────────────
class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  const _Row({required this.icon, required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 15))),
          trailing,
        ],
      ),
    );
  }
}


// Selectable row for reminder interval options
class _SelectRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectRow(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.normal)),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  color: Color(0xFF4CAF50), size: 18),
          ],
        ),
      ),
    );
  }
}


// Time picker row for quiet hours
class _TimePickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int hour;
  final ValueChanged<int> onChanged;
  const _TimePickerRow(
      {required this.icon,
      required this.label,
      required this.hour,
      required this.onChanged});

  String _fmt(int h) {
    final suffix = h < 12 ? 'AM' : 'PM';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display:00 $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF4CAF50),
                onSurface: Colors.white,
                surface: Color(0xFF1A1A1A),
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
            Icon(icon, color: Colors.white38, size: 18),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15))),
            Text(_fmt(hour),
                style: const TextStyle(
                    color: Color(0xFF4CAF50), fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}