import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/platform_filesystem_capacity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.lexiquest.app/storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'f44 review queries exact filesystem capacity for the install root',
    () async {
      final root = Directory.systemTemp.absolute;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 987654321;
      });

      final bytes = await const PlatformFilesystemCapacity().availableBytes(
        root,
      );

      expect(bytes, 987654321);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'availableBytes');
      expect(calls.single.arguments, <String, Object>{'path': root.path});
    },
  );

  test('f44 review invalid platform capacity fails closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => -1);

    await expectLater(
      const PlatformFilesystemCapacity().availableBytes(Directory.systemTemp),
      throwsStateError,
    );
  });
}
