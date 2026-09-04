import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: fb.surfaceVar,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fb.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('💰', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finance Tracker',
                          style: TextStyle(
                            color: fb.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Finance category.',
                          style: TextStyle(
                            color: fb.onSurfaceFaint,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: fb.border,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: fb.onSurface.withValues(alpha: 0.54),
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              Text(
                'Automatically track money across your tasks.',
                style: TextStyle(
                  color: fb.onSurface.withValues(alpha: 0.38),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // How it works
              _InfoSection(
                icon: Icons.edit_note_rounded,
                iconColor: const Color(0xFF0A84FF),
                title: 'How it works',
                body:
                    'Include an amount anywhere in a task name. FocusBell will detect it automatically and add it to your totals.',
              ),

              const SizedBox(height: 14),

              // Supported formats
              _InfoSection(
                icon: Icons.tag_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: 'Supported formats',
                body: null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    ...[
                      ('Kenneth: 1.3m', '→  ₦1,300,000'),
                      ('Anchor 2.2m', '→  ₦2,200,000'),
                      ('Debt: 500k', '→  ₦500,000'),
                      ('Fee: 1,300,000', '→  ₦1,300,000'),
                      ('Misc: 2500', '→  ₦2,500'),
                    ].map(
                      (pair) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: fb.surfaceVar,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pair.$1,
                                style: TextStyle(
                                  color: fb.onSurfaceDim,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              pair.$2,
                              style: const TextStyle(
                                color: Color(0xFF30D158),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Suffixes: k = thousands · m = millions · b = billions',
                      style: TextStyle(
                        color: fb.onSurface.withValues(alpha: 0.30),
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Status
              _InfoSection(
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF30D158),
                title: 'Status tracking',
                body:
                    'Tasks marked Completed count as Paid. Everything else counts as Owed. Change a task\'s status to update the totals instantly.',
              ),

              const SizedBox(height: 20),

              // Got it button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFF30D158,
                    ).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFF30D158),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: const Color(0xFF30D158).withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info section row ──────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? child;

  const _InfoSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 15),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: fb.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 3),
                Text(
                  body!,
                  style: TextStyle(
                    color: fb.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
              if (child != null) child!,
            ],
          ),
        ),
      ],
    );
  }
}
