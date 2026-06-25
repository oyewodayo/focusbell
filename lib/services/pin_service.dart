import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Handles all PIN hashing and verification logic.
///
/// The raw 6-digit PIN is **never** persisted anywhere. Only its SHA-256
/// hash (hex string) is stored via [AppSettings.pinHash].
///
/// Usage:
/// ```dart
/// // Set a new PIN (call after confirming the PIN in the UI)
/// final hash = PinService.hash('123456');
/// await AppController.instance.updateSettings(
///   settings.copyWith(pinEnabled: true, pinHash: hash),
/// );
///
/// // Verify what the user typed
/// if (PinService.verify(typed, settings.pinHash)) { … }
/// ```
class PinService {
  PinService._();

  /// Returns the SHA-256 hex digest of [pin].
  static String hash(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// Returns true when [pin] matches [storedHash].
  /// Always returns false when [storedHash] is null or empty.
  static bool verify(String pin, String? storedHash) {
    if (storedHash == null || storedHash.isEmpty) return false;
    return hash(pin) == storedHash;
  }

  /// Returns true when [storedHash] is non-null and non-empty —
  /// i.e. a PIN has been set.
  static bool isSet(String? storedHash) =>
      storedHash != null && storedHash.isNotEmpty;
}