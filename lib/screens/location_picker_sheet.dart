// screens/location_picker_sheet.dart — NEW FILE
//
// Full-screen bottom sheet for picking a location for a geofence reminder.
// Features:
//   • "Use my current location" — one tap to grab GPS coords
//   • Quick presets: Home, Work, Gym, School, Airport
//   • Manual lat/lng entry for power users
//   • Arrive vs Leave trigger selector
//   • Radius slider (50m → 500m)
//   • Live distance preview once location is set

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/reminder_model.dart';
import '../services/geofence_service.dart';

class LocationPickerSheet extends StatefulWidget {
  final ReminderGeofence? initial;
  final ValueChanged<ReminderGeofence?> onConfirm;

  const LocationPickerSheet({
    super.key,
    this.initial,
    required this.onConfirm,
  });

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _nameCtrl = TextEditingController();
  final _latCtrl  = TextEditingController();
  final _lngCtrl  = TextEditingController();

  double           _radius  = 150;
  GeofenceTrigger  _trigger = GeofenceTrigger.onArrive;
  bool             _loading = false;
  String?          _error;

  // Resolved coords
  double? _lat;
  double? _lng;

  static const _presets = [
    ('🏠', 'Home'),
    ('💼', 'Work'),
    ('🏋️', 'Gym'),
    ('🏫', 'School'),
    ('✈️', 'Airport'),
    ('🏥', 'Hospital'),
    ('🛒', 'Supermarket'),
    ('⛪', 'Church'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final g = widget.initial!;
      _nameCtrl.text = g.placeName;
      _latCtrl.text  = g.latitude.toStringAsFixed(6);
      _lngCtrl.text  = g.longitude.toStringAsFixed(6);
      _lat     = g.latitude;
      _lng     = g.longitude;
      _radius  = g.radiusMeters;
      _trigger = g.trigger;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() { _loading = true; _error = null; });

    final granted = await GeofenceService.instance.requestPermission();
    if (!granted) {
      setState(() {
        _loading = false;
        _error   = 'Location permission is required. Please enable it in Settings.';
      });
      return;
    }

    final pos = await GeofenceService.instance.getCurrentPosition();
    if (pos == null) {
      setState(() {
        _loading = false;
        _error   = 'Could not get your location. Try again.';
      });
      return;
    }

    setState(() {
      _lat  = pos.latitude;
      _lng  = pos.longitude;
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      if (_nameCtrl.text.isEmpty) _nameCtrl.text = 'Current location';
      _loading = false;
    });
  }

  void _applyPreset(String emoji, String name) {
    setState(() {
      _nameCtrl.text = name;
      // Clear coords so user knows to set them
      _lat = null;
      _lng = null;
      _latCtrl.clear();
      _lngCtrl.clear();
      _error = 'Tap "Use my location" while at $name to capture its coordinates.';
    });
  }

  void _confirm() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a place name.');
      return;
    }

    final lat = double.tryParse(_latCtrl.text.trim()) ?? _lat;
    final lng = double.tryParse(_lngCtrl.text.trim()) ?? _lng;

    if (lat == null || lng == null) {
      setState(() => _error = 'Please set a location using GPS or enter coordinates.');
      return;
    }

    widget.onConfirm(ReminderGeofence(
      placeName:    name,
      latitude:     lat,
      longitude:    lng,
      radiusMeters: _radius,
      trigger:      _trigger,
    ));
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onConfirm(null);
    Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasCoords = _lat != null && _lng != null;

    return Container(
      height:  MediaQuery.of(context).size.height * 0.92,
      margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 18),

            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A84FF).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.location_fill,
                    color: Color(0xFF0A84FF), size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Set Location', style: TextStyle(
                color: Colors.white, fontSize: 20,
                fontWeight: FontWeight.w700, letterSpacing: -0.4,
              )),
              const Spacer(),
              if (widget.initial != null)
                GestureDetector(
                  onTap: _clear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFFF3B30).withOpacity(0.3)),
                    ),
                    child: const Text('Remove', style: TextStyle(
                      color: Color(0xFFFF3B30), fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
                  ),
                ),
            ]),
            const SizedBox(height: 22),

            // ── Use current location ─────────────────────────
            GestureDetector(
              onTap: _loading ? null : _useCurrentLocation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: hasCoords
                      ? const Color(0xFF0A84FF).withOpacity(0.12)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasCoords
                        ? const Color(0xFF0A84FF).withOpacity(0.4)
                        : Colors.white10,
                  ),
                ),
                child: Row(children: [
                  if (_loading)
                    const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0A84FF),
                      ),
                    )
                  else
                    Icon(
                      hasCoords
                          ? CupertinoIcons.location_fill
                          : CupertinoIcons.location,
                      color: hasCoords
                          ? const Color(0xFF0A84FF)
                          : Colors.white54,
                      size: 22,
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loading
                              ? 'Getting location...'
                              : hasCoords
                                  ? 'Location captured ✓'
                                  : 'Use my current location',
                          style: TextStyle(
                            color: hasCoords
                                ? const Color(0xFF0A84FF)
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasCoords)
                          Text(
                            '${_lat!.toStringAsFixed(4)}, '
                            '${_lng!.toStringAsFixed(4)}',
                            style: const TextStyle(
                              color: Colors.white38, fontSize: 12,
                            ),
                          )
                        else
                          const Text('Tap to pin your current GPS position',
                              style: TextStyle(
                                color: Colors.white38, fontSize: 12,
                              )),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),

            // ── Quick presets ────────────────────────────────
            const _Label('QUICK PRESETS'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _presets.map((p) {
                final (emoji, name) = p;
                final isSelected = _nameCtrl.text == name;
                return GestureDetector(
                  onTap: () => _applyPreset(emoji, name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0A84FF).withOpacity(0.15)
                          : const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0A84FF)
                            : Colors.white12,
                      ),
                    ),
                    child: Text('$emoji $name', style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF0A84FF)
                          : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // ── Place name ───────────────────────────────────
            const _Label('PLACE NAME'),
            const SizedBox(height: 8),
            _Field(
              controller: _nameCtrl,
              hint: 'e.g. Home, Office, Gym',
              icon: CupertinoIcons.map_pin,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),

            // ── Trigger selector ─────────────────────────────
            const _Label('TRIGGER'),
            const SizedBox(height: 8),
            Row(children: [
              _TriggerPill(
                label: '📍 When I arrive',
                selected: _trigger == GeofenceTrigger.onArrive,
                onTap: () => setState(
                    () => _trigger = GeofenceTrigger.onArrive),
              ),
              const SizedBox(width: 8),
              _TriggerPill(
                label: '🚶 When I leave',
                selected: _trigger == GeofenceTrigger.onLeave,
                onTap: () => setState(
                    () => _trigger = GeofenceTrigger.onLeave),
              ),
            ]),
            const SizedBox(height: 18),

            // ── Radius slider ────────────────────────────────
            Row(children: [
              const _Label('DETECTION RADIUS'),
              const Spacer(),
              Text(
                _radius >= 1000
                    ? '${(_radius / 1000).toStringAsFixed(1)} km'
                    : '${_radius.round()} m',
                style: const TextStyle(
                  color: Color(0xFF0A84FF), fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   const Color(0xFF0A84FF),
                inactiveTrackColor: Colors.white12,
                thumbColor:         const Color(0xFF0A84FF),
                overlayColor:
                    const Color(0xFF0A84FF).withOpacity(0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value:   _radius,
                min:     50,
                max:     500,
                divisions: 9,
                onChanged: (v) => setState(() => _radius = v),
              ),
            ),
            Row(children: const [
              Text('50 m', style: TextStyle(
                  color: Colors.white24, fontSize: 11)),
              Spacer(),
              Text('500 m', style: TextStyle(
                  color: Colors.white24, fontSize: 11)),
            ]),
            const SizedBox(height: 18),

            // ── Error ────────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFF453A).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(CupertinoIcons.exclamationmark_circle,
                      color: Color(0xFFFF453A), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(
                    color: Color(0xFFFF453A), fontSize: 13,
                  ))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // ── Confirm button ───────────────────────────────
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _confirm,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: hasCoords
                        ? const Color(0xFF0A84FF)
                        : const Color(0xFF0A84FF).withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('Set Location Reminder',
                        style: TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    color: Colors.white38, fontSize: 11,
    fontWeight: FontWeight.w700, letterSpacing: 1.0,
  ));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Icon(icon, color: Colors.white38, size: 18),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TriggerPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TriggerPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0A84FF).withOpacity(0.15)
                : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF0A84FF) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(label, style: TextStyle(
              color:      selected ? const Color(0xFF0A84FF) : Colors.white54,
              fontSize:   13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        ),
      ),
    );
  }
}