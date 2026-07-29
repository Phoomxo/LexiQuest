import 'dart:convert';
import 'dart:math';

abstract interface class SecureIdGenerator {
  String nextId();
}

final class CryptographicIdGenerator implements SecureIdGenerator {
  CryptographicIdGenerator() : _random = Random.secure();

  final Random _random;

  @override
  String nextId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
