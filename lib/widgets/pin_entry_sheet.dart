import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focusbell/services/pin_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PinEntryMode
// ─────────────────────────────────────────────────────────────────────────────

/// Controls which flow [PinEntrySheet] runs.
///
/// • [verify]  — asks for the current PIN; pops `true` if correct, `false`
///               if wrong or cancelled.
/// • [setup]   — enter new PIN + confirm; pops the raw PIN string so the
///               caller can hash and persist it, or `null` if cancelled.
/// • [change]  — verify current PIN, then enter + confirm a new one;
///               pops the new raw PIN string, or `null` if cancelled.
enum PinEntryMode { verify, setup, change }

// ─────────────────────────────────────────────────────────────────────────────
// showPinEntry — convenience navigator helper
// ─────────────────────────────────────────────────────────────────────────────

/// Pushes [PinEntrySheet] as a translucent overlay route and returns its result.
///
/// Type parameter [T] should be:
///   - `bool`    for [PinEntryMode.verify]
///   - `String?` for [PinEntryMode.setup] and [PinEntryMode.change]
Future<T?> showPinEntry<T>(
  BuildContext context, {
  required PinEntryMode mode,
  /// Required for [PinEntryMode.verify] and [PinEntryMode.change].
  String? storedHash,
  String? title,
  String? subtitle,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => PinEntrySheet(
        mode: mode,
        storedHash: storedHash,
        title: title,
        subtitle: subtitle,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PinEntrySheet
// ─────────────────────────────────────────────────────────────────────────────

class PinEntrySheet extends StatefulWidget {
  final PinEntryMode mode;
  final String? storedHash;
  final String? title;
  final String? subtitle;

  const PinEntrySheet({
    super.key,
    required this.mode,
    this.storedHash,
    this.title,
    this.subtitle,
  });

  @override
  State<PinEntrySheet> createState() => _PinEntrySheetState();
}

// Internal multi-step state machine.
enum _PinStep { initial, newPin, confirm }

class _PinEntrySheetState extends State<PinEntrySheet>
    with SingleTickerProviderStateMixin {
  // ── Constants ────────────────────────────────────────────────
  static const int _kPinLength = 6;

  // ── Input buffer ─────────────────────────────────────────────
  String _entered = '';

  // ── Step tracking (for setup / change flows) ─────────────────
  _PinStep _step = _PinStep.initial;

  /// Stores the first PIN entry while waiting for confirmation.
  String? _firstPin;

  // ── Shake animation (on wrong PIN) ───────────────────────────
  late final AnimationController _shakeCtrl;
  late final Animation<double>   _shakeAnim;

  // ─────────────────────────────────────────────────────────────
  // Derived UI text
  // ─────────────────────────────────────────────────────────────

  String get _title {
    switch (widget.mode) {
      case PinEntryMode.verify:
        return widget.title ?? 'Enter PIN to continue';
      case PinEntryMode.setup:
        return _step == _PinStep.initial
            ? (widget.title ?? 'Set a 6-digit PIN')
            : 'Confirm your PIN';
      case PinEntryMode.change:
        if (_step == _PinStep.initial)  return widget.title ?? 'Enter current PIN';
        if (_step == _PinStep.newPin)   return 'Enter new PIN';
        return 'Confirm new PIN';
    }
  }

  String? get _subtitle {
    // Only show the caller-supplied subtitle on the very first step.
    return _step == _PinStep.initial ? widget.subtitle : null;
  }

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    // Oscillating curve produces a left-right shake feel.
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end:  10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end:  8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0,  end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end:  0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Input handling
  // ─────────────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_entered.length >= _kPinLength) return;
    HapticFeedback.lightImpact();
    setState(() => _entered += digit);

    // Auto-submit once all digits are entered; defer one frame so the
    // last dot visually fills before the transition fires.
    if (_entered.length == _kPinLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _onClearAll() {
    if (_entered.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _entered = '');
  }

  // ─────────────────────────────────────────────────────────────
  // Flow dispatch
  // ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    switch (widget.mode) {
      case PinEntryMode.verify: await _handleVerify();
      case PinEntryMode.setup:  await _handleSetup();
      case PinEntryMode.change: await _handleChange();
    }
  }

  // ── Verify ───────────────────────────────────────────────────

  Future<void> _handleVerify() async {
    if (PinService.verify(_entered, widget.storedHash)) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      await _shakeAndReset();
    }
  }

  // ── Setup (new PIN entry + confirm) ──────────────────────────

  Future<void> _handleSetup() async {
    if (_step == _PinStep.initial) {
      // First entry accepted — move to confirmation step.
      setState(() {
        _firstPin = _entered;
        _entered  = '';
        _step     = _PinStep.confirm;
      });
    } else {
      // Confirmation step.
      if (_entered == _firstPin) {
        // Pop the raw PIN; the caller (SettingsBottomSheet) hashes it.
        if (mounted) Navigator.of(context).pop(_entered);
      } else {
        await _shakeAndReset();
        _restartSetup();
      }
    }
  }

  // ── Change (verify old → enter new → confirm new) ────────────

  Future<void> _handleChange() async {
    switch (_step) {
      case _PinStep.initial:
        if (PinService.verify(_entered, widget.storedHash)) {
          setState(() {
            _entered = '';
            _step    = _PinStep.newPin;
          });
        } else {
          await _shakeAndReset();
        }

      case _PinStep.newPin:
        setState(() {
          _firstPin = _entered;
          _entered  = '';
          _step     = _PinStep.confirm;
        });

      case _PinStep.confirm:
        if (_entered == _firstPin) {
          if (mounted) Navigator.of(context).pop(_entered);
        } else {
          await _shakeAndReset();
          setState(() {
            _firstPin = null;
            _step     = _PinStep.newPin;
          });
          _showBanner('PINs did not match — please try again.');
        }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  /// Shakes the dot row, vibrates, then clears the input buffer.
  Future<void> _shakeAndReset() async {
    HapticFeedback.heavyImpact();
    await _shakeCtrl.forward();
    _shakeCtrl.reset();
    if (mounted) setState(() => _entered = '');
  }

  void _restartSetup() {
    if (!mounted) return;
    setState(() {
      _firstPin = null;
      _step     = _PinStep.initial;
    });
    _showBanner('PINs did not match — please try again.');
  }

  void _showBanner(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF2E1A1A),
          dividerColor: Colors.transparent,
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('OK', style: TextStyle(color: Color(0xFFFF6B6B))),
            ),
          ],
        ),
      );
    // Auto-dismiss after 2.5 s.
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  void _onCancel() {
    Navigator.of(context).pop(
      // Return the correct "cancelled" type per mode.
      widget.mode == PinEntryMode.verify ? false : null,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLockIcon(),
                  const SizedBox(height: 20),
                  _buildTitleBlock(),
                  const SizedBox(height: 30),
                  _buildDotRow(),
                  const SizedBox(height: 36),
                  _buildNumpad(),
                  const SizedBox(height: 22),
                  _buildCancelButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Sub-builders
  // ─────────────────────────────────────────────────────────────

  Widget _buildLockIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1C2E1C),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.lock_outline_rounded,
        color: Color(0xFF4CAF50),
        size: 28,
      ),
    );
  }

  Widget _buildTitleBlock() {
    return Column(
      children: [
        Text(
          _title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        if (_subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            _subtitle!,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Six animated dots that fill as the user types; shakes on wrong input.
  Widget _buildDotRow() {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_shakeAnim.value, 0),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_kPinLength, (i) {
          final filled = i < _entered.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width:  filled ? 15 : 13,
            height: filled ? 15 : 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? const Color(0xFF4CAF50) : Colors.transparent,
              border: Border.all(
                color: filled ? const Color(0xFF4CAF50) : Colors.white30,
                width: 1.5,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.45),
                        blurRadius: 7,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNumpad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) => _NumKey(
              label:       key,
              onTap:       key == '⌫' ? _onBackspace
                           : key.isEmpty ? null
                           : () => _onDigit(key),
              onLongPress: key == '⌫' ? _onClearAll : null,
            )).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCancelButton() {
    return TextButton(
      onPressed: _onCancel,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      ),
      child: const Text(
        'Cancel',
        style: TextStyle(color: Colors.white38, fontSize: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NumKey — a single key on the numpad grid
// ─────────────────────────────────────────────────────────────────────────────

class _NumKey extends StatelessWidget {
  final String         label;
  final VoidCallback?  onTap;
  final VoidCallback?  onLongPress;

  const _NumKey({
    required this.label,
    this.onTap,
    this.onLongPress,
  });

  bool get _isEmpty  => label.isEmpty;
  bool get _isDelete => label == '⌫';

  @override
  Widget build(BuildContext context) {
    // Empty cell preserves grid spacing without rendering anything.
    if (_isEmpty) return const SizedBox(width: 84, height: 66);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 84,
        height: 66,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: _isDelete ? Colors.transparent : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: _isDelete
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Center(
          child: _isDelete
              ? const Icon(
                  Icons.backspace_outlined,
                  color: Colors.white54,
                  size: 20,
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                  ),
                ),
        ),
      ),
    );
  }
}