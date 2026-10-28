import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_bridge_pairing.dart';

void main() {
  final now = DateTime.utc(2026, 9, 21, 7);
  final token = List.filled(43, 'a').join();
  late Directory directory;
  late File config;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ari-pairing-test-');
    config = File('${directory.path}/ari-bridge.json');
  });
  tearDown(() => directory.delete(recursive: true));
  Future<void> write({Object? expires, String? capability}) => config.writeAsString(
    jsonEncode({'token': capability ?? token, 'expiresAtUtc': expires}),
  );

  test('private pairing survives app recreation during its bounded lifetime', () async {
    await write(expires: now.add(const Duration(minutes: 15)).toIso8601String());
    expect(await loadLocalBridgePairing(config, nowUtc: () => now), token);
    expect(await config.exists(), isTrue);
    expect(await loadLocalBridgePairing(config, nowUtc: () => now.add(const Duration(minutes: 2))), token);
  });

  test('expired pairing cannot reconnect', () async {
    await write(expires: now.toIso8601String());
    expect(await loadLocalBridgePairing(config, nowUtc: () => now), isNull);
  });

  test('missing or unbounded lifetime and invalid token fail closed', () async {
    for (final expiry in [null, 'bad-date', now.add(const Duration(hours: 1)).toIso8601String()]) {
      await write(expires: expiry);
      await expectLater(loadLocalBridgePairing(config, nowUtc: () => now), throwsStateError);
    }
    await write(expires: now.add(const Duration(minutes: 2)).toIso8601String(), capability: 'bad');
    await expectLater(loadLocalBridgePairing(config, nowUtc: () => now), throwsStateError);
  });

  test('missing configuration leaves baseline available', () async {
    expect(await loadLocalBridgePairing(config, nowUtc: () => now), isNull);
  });
}
