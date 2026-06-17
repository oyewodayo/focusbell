// screens/location_picker_sheet.dart — FULL REPLACEMENT
//
// Features:
//   • Saved places list — pick any saved place in one tap
//   • Add/edit/delete saved places inline
//   • "Use my current location" to capture GPS coords for any place
//   • Arrive vs Leave trigger selector
//   • Radius slider (50 m → 500 m)
//   • When a place is selected it passes back a ReminderGeofence

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/reminder_model.dart';
import '../models/saved_place.dart';
import '../services/geofence_service.dart';
import '../services/saved_places_service.dart';

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
  SavedPlace?      _selected;
  GeofenceTrigger  _trigger = GeofenceTrigger.onArrive;
  double           _radius  = 150;
  bool             _loading = false;
  String?          _error;

  @override
  void initState() {
    super.initState();
    // Pre-select the saved place that matches the initial geofence
    if (widget.initial != null) {
      _trigger = widget.initial!.trigger;
      _radius  = widget.initial!.radiusMeters;
      final match = SavedPlacesService.instance.places.value.firstWhere(
        (p) => p.name == widget.initial!.placeName,
        orElse: () => SavedPlace(
          id: '__custom__',
          name: widget.initial!.placeName,
          emoji: '📍',
          latitude: widget.initial!.latitude,
          longitude: widget.initial!.longitude,
          createdAt: DateTime.now(),
        ),
      );
      _selected = match;
    }
  }

  // ── Confirm ───────────────────────────────────────────────────

  void _confirm() {
    if (_selected == null) {
      setState(() => _error = 'Please select or add a place first.');
      return;
    }
    widget.onConfirm(ReminderGeofence(
      placeName:    _selected!.name,
      latitude:     _selected!.latitude,
      longitude:    _selected!.longitude,
      radiusMeters: _radius,
      trigger:      _trigger,
    ));
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onConfirm(null);
    Navigator.of(context).pop();
  }

  // ── Add / edit place ──────────────────────────────────────────

  Future<void> _showAddPlaceSheet({SavedPlace? editing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddPlaceSheet(
        editing: editing,
        onSaved: (place) {
          setState(() => _selected = place);
          _radius = place.radiusMeters;
        },
      ),
    );
    setState(() {}); // Rebuild to show updated places list
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height:  MediaQuery.of(context).size.height * 0.92,
      margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: [
        // Handle
        const SizedBox(height: 12),
        Center(child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 16),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                  ),
                  child: const Text('Remove', style: TextStyle(
                    color: Color(0xFFFF3B30), fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── My Places ───────────────────────────────
                Row(children: [
                  const _Label('MY PLACES'),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showAddPlaceSheet(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A84FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF0A84FF).withOpacity(0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.plus,
                            color: Color(0xFF0A84FF), size: 12),
                        SizedBox(width: 5),
                        Text('Add place', style: TextStyle(
                          color: Color(0xFF0A84FF), fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                ValueListenableBuilder<List<SavedPlace>>(
                  valueListenable: SavedPlacesService.instance.places,
                  builder: (_, places, __) {
                    if (places.isEmpty) {
                      return GestureDetector(
                        onTap: () => _showAddPlaceSheet(),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Column(children: [
                            Icon(CupertinoIcons.location_slash,
                                color: Colors.white24, size: 32),
                            SizedBox(height: 10),
                            Text('No places saved yet',
                                style: TextStyle(color: Colors.white38,
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            SizedBox(height: 4),
                            Text('Tap + Add place to save Home, Work and more',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                          ]),
                        ),
                      );
                    }
                    return Column(
                      children: places.map((place) {
                        final isSelected = _selected?.id == place.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _selected = place;
                              _radius   = place.radiusMeters;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 13),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0A84FF).withOpacity(0.12)
                                    : const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF0A84FF)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(children: [
                                // Emoji avatar
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF0A84FF).withOpacity(0.2)
                                        : Colors.white.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text(place.emoji,
                                      style: const TextStyle(fontSize: 20))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(place.name, style: TextStyle(
                                        color: isSelected
                                            ? const Color(0xFF0A84FF)
                                            : Colors.white,
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      )),
                                      Text(
                                        '${place.latitude.toStringAsFixed(4)}, '
                                        '${place.longitude.toStringAsFixed(4)}  ·  '
                                        '${place.radiusMeters.round()} m radius',
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                // Edit button
                                GestureDetector(
                                  onTap: () => _showAddPlaceSheet(editing: place),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(CupertinoIcons.pencil,
                                        color: isSelected
                                            ? const Color(0xFF0A84FF)
                                            : Colors.white24,
                                        size: 16),
                                  ),
                                ),
                                // Selection check
                                AnimatedOpacity(
                                  opacity: isSelected ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: const Icon(Icons.check_rounded,
                                      color: Color(0xFF0A84FF), size: 18),
                                ),
                              ]),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // ── Trigger ──────────────────────────────────
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
                const SizedBox(height: 20),

                // ── Radius ────────────────────────────────────
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
                    value: _radius, min: 50, max: 500, divisions: 9,
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                ),
                Row(children: const [
                  Text('50 m', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  Spacer(),
                  Text('500 m', style: TextStyle(color: Colors.white24, fontSize: 11)),
                ]),
                const SizedBox(height: 20),

                // ── Error ─────────────────────────────────────
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

                // ── Confirm ───────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _confirm,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selected != null
                            ? const Color(0xFF0A84FF)
                            : const Color(0xFF0A84FF).withOpacity(0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(child: Text('Set Location Reminder',
                          style: TextStyle(
                            color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Add / Edit place bottom sheet
// ════════════════════════════════════════════════════════════════

class _AddPlaceSheet extends StatefulWidget {
  final SavedPlace? editing;
  final ValueChanged<SavedPlace> onSaved;
  const _AddPlaceSheet({this.editing, required this.onSaved});

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _nameCtrl = TextEditingController();
  String  _emoji        = '📍';
  double? _lat;
  double? _lng;
  double  _radius       = 150;
  bool    _loading      = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      final e = widget.editing!;
      _nameCtrl.text = e.name;
      _emoji         = e.emoji;
      _lat           = e.latitude;
      _lng           = e.longitude;
      _radius        = e.radiusMeters;
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _useCurrentLocation() async {
    setState(() { _loading = true; _error = null; });
    final granted = await GeofenceService.instance.requestPermission();
    if (!granted) {
      setState(() { _loading = false; _error = 'Location permission denied.'; });
      return;
    }
    final pos = await GeofenceService.instance.getCurrentPosition();
    if (pos == null) {
      setState(() { _loading = false; _error = 'Could not get location. Try again.'; });
      return;
    }
    setState(() {
      _lat = pos.latitude; _lng = pos.longitude; _loading = false;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter a place name.'); return; }
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Tap "Use my location" while at this place.'); return;
    }
    SavedPlace place;
    if (widget.editing != null) {
      place = widget.editing!.copyWith(
        name: name, emoji: _emoji,
        latitude: _lat!, longitude: _lng!, radiusMeters: _radius,
      );
      await SavedPlacesService.instance.update(place);
    } else {
      place = await SavedPlacesService.instance.add(
        name: name, emoji: _emoji,
        latitude: _lat!, longitude: _lng!, radiusMeters: _radius,
      );
    }
    widget.onSaved(place);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (widget.editing == null) return;
    await SavedPlacesService.instance.remove(widget.editing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = _lat != null && _lng != null;
    final isEditing = widget.editing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 18),
              Row(children: [
                Text(isEditing ? 'Edit Place' : 'Add Place',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                const Spacer(),
                if (isEditing)
                  GestureDetector(
                    onTap: _delete,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                      ),
                      child: const Text('Delete', style: TextStyle(
                        color: Color(0xFFFF3B30), fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                    ),
                  ),
              ]),
              const SizedBox(height: 20),

              // Emoji picker row
              const _Label('ICON'),
              const SizedBox(height: 8),
              _EmojiPicker(
                selected: _emoji,
                onSelect: (e) => setState(() => _emoji = e),
              ),
              const SizedBox(height: 16),

              // Name
              const _Label('PLACE NAME'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 14),
                    child: Icon(CupertinoIcons.map_pin,
                        color: Colors.white38, size: 18),
                  ),
                  Expanded(child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Home, Office, Gym',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  )),
                ]),
              ),
              const SizedBox(height: 16),

              // GPS capture
              GestureDetector(
                onTap: _loading ? null : _useCurrentLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasCoords
                        ? const Color(0xFF30D158).withOpacity(0.10)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasCoords
                          ? const Color(0xFF30D158).withOpacity(0.4)
                          : Colors.white10,
                    ),
                  ),
                  child: Row(children: [
                    if (_loading)
                      const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: Color(0xFF30D158)))
                    else
                      Icon(
                        hasCoords
                            ? CupertinoIcons.location_fill
                            : CupertinoIcons.location,
                        color: hasCoords
                            ? const Color(0xFF30D158)
                            : Colors.white54,
                        size: 22,
                      ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loading
                              ? 'Getting location...'
                              : hasCoords
                                  ? 'Location captured ✓'
                                  : 'Tap while at this place',
                          style: TextStyle(
                            color: hasCoords
                                ? const Color(0xFF30D158)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasCoords)
                          Text(
                            '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          )
                        else
                          const Text('Use my current location',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                      ],
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // Radius
              Row(children: [
                const _Label('DEFAULT RADIUS'),
                const Spacer(),
                Text('${_radius.round()} m', style: const TextStyle(
                    color: Color(0xFF0A84FF), fontSize: 13,
                    fontWeight: FontWeight.w600)),
              ]),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor:   const Color(0xFF0A84FF),
                  inactiveTrackColor: Colors.white12,
                  thumbColor:         const Color(0xFF0A84FF),
                  overlayColor: const Color(0xFF0A84FF).withOpacity(0.15),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _radius, min: 50, max: 500, divisions: 9,
                  onChanged: (v) => setState(() => _radius = v),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
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
                        color: Color(0xFFFF453A), fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: Text(
                      isEditing ? 'Save Changes' : 'Save Place',
                      style: const TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w600),
                    )),
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

// ════════════════════════════════════════════════════════════════
// Emoji picker — compact grid for place icons
// ════════════════════════════════════════════════════════════════

class _EmojiPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _EmojiPicker({required this.selected, required this.onSelect});

  static const _emojis = [
    '🏠','💼','🏋️','🏫','✈️','🏥','🛒','⛪',
    '🍽️','👨‍👩‍👧','🏖️','🏔️','🎓','🏪','⚽','🎭',
    '📍','🏦','💊','🧘','📚','🎯','🏗️','🌳',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _emojis.map((e) {
        final isSel = e == selected;
        return GestureDetector(
          onTap: () => onSelect(e),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFF0A84FF).withOpacity(0.2)
                  : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSel ? const Color(0xFF0A84FF) : Colors.white10,
                width: isSel ? 1.5 : 1,
              ),
            ),
            child: Center(child: Text(e,
                style: const TextStyle(fontSize: 22))),
          ),
        );
      }).toList(),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    color: Colors.white38, fontSize: 11,
    fontWeight: FontWeight.w700, letterSpacing: 1.0,
  ));
}

class _TriggerPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TriggerPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
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
        child: Center(child: Text(label, style: TextStyle(
          color:      selected ? const Color(0xFF0A84FF) : Colors.white54,
          fontSize:   13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ))),
      ),
    ),
  );
}