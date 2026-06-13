/// Extracts a numeric value from a task title, if one is present.
///
/// Supported formats (case-insensitive):
///   "Kenneth: 1.3m"  → 1_300_000
///   "Anchor 2.2m"    → 2_200_000
///   "Debt: 500k"     → 500_000
///   "Fee: 1,300,000" → 1_300_000
///   "Misc: 2500"     → 2_500
///
/// Returns null when no number is found.
double? parseTaskValue(String title) {
  // Strip commas used as thousand-separators before matching.
  final cleaned = title.replaceAll(',', '');

  // Match an optional decimal number followed by an optional suffix (k/m/b/t).
  final pattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*([kmbt])?',
    caseSensitive: false,
  );

  final match = pattern.firstMatch(cleaned);
  if (match == null) return null;

  final raw = double.tryParse(match.group(1)!);
  if (raw == null) return null;

  final suffix = (match.group(2) ?? '').toLowerCase();
  return switch (suffix) {
    'k' => raw * 1_000,
    'm' => raw * 1_000_000,
    'b' => raw * 1_000_000_000,
    't' => raw * 1_000_000_000_000,
    _ => raw,
  };
}

/// Compact display: 1_300_000 → "₦1.3M", 500_000 → "₦500K", 2_500 → "₦2,500".
String formatTaskValue(double value, {String symbol = '₦'}) {
  if (value >= 1_000_000_000) {
    final b = value / 1_000_000_000;
    return '$symbol${_trimZero(b)}B';
  }
  if (value >= 1_000_000) {
    final m = value / 1_000_000;
    return '$symbol${_trimZero(m)}M';
  }
  if (value >= 1_000) {
    final k = value / 1_000;
    return '$symbol${_trimZero(k)}K';
  }
  return '$symbol${_commaFormat(value)}';
}

/// Full expanded display with thousand separators: 1_300_000 → "₦1,300,000".
String formatTaskValueFull(double value, {String symbol = '₦'}) {
  final isWhole = value.truncateToDouble() == value;
  final formatted = isWhole
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  final withCommas = formatted.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$symbol$withCommas';
}

String _commaFormat(double value) {
  final isWhole = value.truncateToDouble() == value;
  final str = isWhole ? value.toInt().toString() : value.toStringAsFixed(2);
  return str.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

String _trimZero(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);