// reminders_tz_picker.dart
// Full-screen timezone city picker sheet.

part of 'reminders_screen.dart';

class _TzPickerSheet extends StatefulWidget {
  final String selectedTz;
  final bool useDeviceTz;
  final String deviceTz;
  final String Function(String) gmtOffset;
  final void Function(TzCity) onPick;
  final VoidCallback onUseDevice;

  const _TzPickerSheet({
    required this.selectedTz,
    required this.useDeviceTz,
    required this.deviceTz,
    required this.gmtOffset,
    required this.onPick,
    required this.onUseDevice,
  });

  @override
  State<_TzPickerSheet> createState() =>
      _TzPickerSheetState();
}

class _TzPickerSheetState extends State<_TzPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<TzCity> _filtered = List.from(kAllCities);
  String _activeLetter = '';
  bool _isDragging = false;
  String _dragLetter = '';
  bool _isSearching = false;

  late Map<String, int> _letterIndex;
  late List<String> _letters;

  static const double _itemH = 62.0;
  static const double _headerH = 32.0;

  @override
  void initState() {
    super.initState();
    _buildIndex(kAllCities);
    _scrollCtrl.addListener(_onScroll);
    if (_letters.isNotEmpty) _activeLetter = _letters.first;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _buildIndex(List<TzCity> cities) {
    _letterIndex = {};
    for (int i = 0; i < cities.length; i++) {
      final l = cities[i].city[0].toUpperCase();
      _letterIndex.putIfAbsent(l, () => i);
    }
    _letters = _letterIndex.keys.toList()..sort();
  }

  void _onScroll() {
    if (_isSearching || _letters.isEmpty) return;
    final offset = _scrollCtrl.offset;
    String current = _letters.first;
    for (final letter in _letters) {
      if (_estimatedOffset(_letterIndex[letter]!) <=
          offset + 80) {
        current = letter;
      }
    }
    if (current != _activeLetter) {
      setState(() => _activeLetter = current);
    }
  }

  double _estimatedOffset(int idx) {
    int headers = 0;
    String? last;
    for (int i = 0;
        i < idx && i < kAllCities.length;
        i++) {
      final l = kAllCities[i].city[0].toUpperCase();
      if (l != last) {
        headers++;
        last = l;
      }
    }
    return idx * _itemH + headers * _headerH;
  }

  void _jumpToLetter(String letter) {
    final idx = _letterIndex[letter];
    if (idx == null) return;
    final target = _estimatedOffset(idx)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic);
    setState(() {
      _activeLetter = letter;
      _dragLetter = letter;
    });
  }

  String? _letterFromY(double y, double totalH) {
    if (_letters.isEmpty) return null;
    final i = (y / totalH * _letters.length)
        .floor()
        .clamp(0, _letters.length - 1);
    return _letters[i];
  }

  void _onSearch(String q) {
    setState(() {
      _isSearching = q.isNotEmpty;
      _filtered = q.isEmpty
          ? List.from(kAllCities)
          : kAllCities
              .where((c) =>
                  c.city
                      .toLowerCase()
                      .contains(q.toLowerCase()) ||
                  c.country
                      .toLowerCase()
                      .contains(q.toLowerCase()))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      margin:
          const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: fb.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: fb.border),
      ),
      child: Column(children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: fb.onSurfaceFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20),
          child: Row(children: [
            Text('Select City',
                style: TextStyle(
                  color: fb.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                )),
            const Spacer(),
            GestureDetector(
              onTap: () {
                widget.onUseDevice();
                Navigator.of(context).pop();
              },
              child: AnimatedContainer(
                duration:
                    const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.useDeviceTz
                      ? const Color(0xFF0A84FF)
                          .withOpacity(0.18)
                      : fb.surfaceVar,
                  borderRadius:
                      BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.useDeviceTz
                        ? const Color(0xFF0A84FF)
                        : fb.onSurface.withValues(alpha: 0.12),
                  ),
                ),
                child: Text('Use device',
                    style: TextStyle(
                      color: widget.useDeviceTz
                          ? const Color(0xFF0A84FF)
                          : fb.onSurface.withValues(alpha: 0.38),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: fb.surfaceVar,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: fb.border),
            ),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Icon(CupertinoIcons.search,
                    color: fb.onSurface.withValues(alpha: 0.38), size: 18),
              ),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  style: TextStyle(
                      color: fb.onSurface,
                      fontSize: 15),
                  decoration: InputDecoration(
                    hintText:
                        'Search cities or countries...',
                    hintStyle: TextStyle(
                        color: fb.onSurfaceFaint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              if (_isSearching)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    _onSearch('');
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.only(right: 12),
                    child: Icon(
                        CupertinoIcons
                            .xmark_circle_fill,
                        color: fb.onSurfaceFaint,
                        size: 18),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // City list + A–Z scrubber
        Expanded(
          child: Stack(children: [
            ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(
                  left: 12, right: 44, bottom: 20),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final item = _filtered[i];
                final isSelected =
                    item.tzName == widget.selectedTz &&
                        !widget.useDeviceTz;
                final offset =
                    widget.gmtOffset(item.tzName);
                final showHeader = !_isSearching &&
                    (i == 0 ||
                        _filtered[i]
                                .city[0]
                                .toUpperCase() !=
                            _filtered[i - 1]
                                .city[0]
                                .toUpperCase());
                final letter =
                    item.city[0].toUpperCase();
                final isActive = letter ==
                        _activeLetter &&
                    !_isSearching;

                return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    if (showHeader)
                      AnimatedContainer(
                        duration: const Duration(
                            milliseconds: 250),
                        curve: Curves.easeOut,
                        padding:
                            const EdgeInsets.fromLTRB(
                                4, 12, 0, 4),
                        child: Row(children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(
                                milliseconds: 250),
                            style: TextStyle(
                              color: isActive
                                  ? const Color(
                                      0xFF0A84FF)
                                  : fb.onSurfaceFaint,
                              fontSize:
                                  isActive ? 14 : 12,
                              fontWeight:
                                  FontWeight.w700,
                              letterSpacing: 1,
                            ),
                            child: Text(letter),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            AnimatedContainer(
                              duration: const Duration(
                                  milliseconds: 250),
                              width: 24,
                              height: 1.5,
                              color: const Color(
                                      0xFF0A84FF)
                                  .withOpacity(0.4),
                            ),
                          ],
                        ]),
                      ),
                    GestureDetector(
                      onTap: () {
                        widget.onPick(item);
                        Navigator.of(context).pop();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(
                            milliseconds: 200),
                        margin: const EdgeInsets
                            .symmetric(vertical: 1),
                        padding: const EdgeInsets
                            .symmetric(
                            horizontal: 14,
                            vertical: 11),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0A84FF)
                                  .withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0A84FF)
                                    .withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(item.city,
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(
                                              0xFF0A84FF)
                                          : fb.onSurface,
                                      fontSize: 15,
                                      fontWeight:
                                          isSelected
                                              ? FontWeight
                                                  .w600
                                              : FontWeight
                                                  .w400,
                                    )),
                                Text(
                                    '${item.country}, $offset',
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(
                                                  0xFF0A84FF)
                                              .withOpacity(
                                                  0.7)
                                          : fb.onSurface.withValues(alpha: 0.38),
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: isSelected ? 1 : 0,
                            duration: const Duration(
                                milliseconds: 200),
                            child: const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF0A84FF),
                                size: 18),
                          ),
                        ]),
                      ),
                    ),
                  ],
                );
              },
            ),
            // A–Z scrubber
            if (!_isSearching)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 28,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final totalH =
                        constraints.maxHeight;
                    return GestureDetector(
                      onTapDown: (d) {
                        final l = _letterFromY(
                            d.localPosition.dy,
                            totalH);
                        if (l != null)
                          _jumpToLetter(l);
                      },
                      onVerticalDragStart: (d) {
                        setState(
                            () => _isDragging = true);
                        final l = _letterFromY(
                            d.localPosition.dy,
                            totalH);
                        if (l != null) {
                          _dragLetter = l;
                          _jumpToLetter(l);
                        }
                      },
                      onVerticalDragUpdate: (d) {
                        final l = _letterFromY(
                            d.localPosition.dy,
                            totalH);
                        if (l != null &&
                            l != _dragLetter) {
                          setState(
                              () => _dragLetter = l);
                          _jumpToLetter(l);
                        }
                      },
                      onVerticalDragEnd: (_) {
                        Future.delayed(
                            const Duration(
                                milliseconds: 600),
                            () {
                          if (mounted)
                            setState(() =>
                                _isDragging = false);
                        });
                      },
                      child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Column(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,
                              children: _letters
                                  .map((letter) {
                                final isActive =
                                    letter ==
                                        _activeLetter;
                                final isDragTarget =
                                    _isDragging &&
                                        letter ==
                                            _dragLetter;
                                return GestureDetector(
                                  onTap: () =>
                                      _jumpToLetter(
                                          letter),
                                  child:
                                      AnimatedContainer(
                                    duration:
                                        const Duration(
                                            milliseconds:
                                                180),
                                    width: isDragTarget
                                        ? 24
                                        : 18,
                                    height: isDragTarget
                                        ? 24
                                        : 16,
                                    margin: const EdgeInsets
                                        .symmetric(
                                        vertical: 0.5),
                                    decoration:
                                        isDragTarget
                                            ? const BoxDecoration(
                                                color: Color(
                                                    0xFF0A84FF),
                                                shape: BoxShape
                                                    .circle,
                                              )
                                            : null,
                                    child: Center(
                                      child:
                                          AnimatedDefaultTextStyle(
                                        duration:
                                            const Duration(
                                                milliseconds:
                                                    180),
                                        style: TextStyle(
                                          color: isDragTarget
                                              ? Colors
                                                  .white
                                              : isActive
                                                  ? const Color(
                                                      0xFF0A84FF)
                                                  : fb.onSurface
                                                      .withValues(alpha: 0.38),
                                          fontSize:
                                              isDragTarget ||
                                                      isActive
                                                  ? 12
                                                  : 10,
                                          fontWeight: isActive ||
                                                  isDragTarget
                                              ? FontWeight
                                                  .w800
                                              : FontWeight
                                                  .w500,
                                        ),
                                        child:
                                            Text(letter),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            if (_isDragging &&
                                _dragLetter.isNotEmpty &&
                                _letters.length > 1)
                              Positioned(
                                right: 32,
                                top: (_letters.indexOf(
                                                _dragLetter) /
                                            (_letters
                                                    .length -
                                                1) *
                                            (totalH - 48))
                                        .clamp(
                                            0.0,
                                            totalH - 48),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration:
                                      BoxDecoration(
                                    color: const Color(
                                        0xFF0A84FF),
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                                0xFF0A84FF)
                                            .withOpacity(
                                                0.4),
                                        blurRadius: 12,
                                        offset:
                                            const Offset(
                                                0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                        _dragLetter,
                                        style:
                                            const TextStyle(
                                          color: Colors
                                              .white,
                                          fontSize: 22,
                                          fontWeight:
                                              FontWeight
                                                  .w800,
                                        )),
                                  ),
                                ),
                              ),
                          ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}