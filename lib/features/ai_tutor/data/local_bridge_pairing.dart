import 'dart:convert';
import 'dart:io';

/// Reads the capability in the isolated debug application's private directory.
Future<String?> loadLocalBridgePairing(
  File config, {
  DateTime Function()? nowUtc,
}) async {
  if (!await config.exists()) return null;
  if (await config.length() > 1024) throw StateError('Invalid pairing');
  final data = jsonDecode(await config.readAsString()) as Map<String, dynamic>;
  final token = data['token'];
  if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
    throw StateError('Invalid pairing');
  }
  final expiryText = data['expiresAtUtc'];
  final expiry = expiryText is String ? DateTime.tryParse(expiryText) : null;
  final now = (nowUtc ?? () => DateTime.now().toUtc())();
  if (expiry == null || !expiry.isUtc || expiry.difference(now) > const Duration(minutes: 15)) {
    throw StateError('Invalid pairing');
  }
  if (!expiry.isAfter(now)) return null;
  return token;
}
