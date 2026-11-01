import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/motivation/presentation/achievement_share_composer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/achievement_share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native chooser gets a token only after a second authority check',
    () async {
      final steps = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        steps.add(call.method);
        if (call.method == 'prepareAchievementShare') {
          expect(call.arguments, {'bytes': png});
          return 'synthetic-prepared-card';
        }
        expect(call.arguments, {'token': 'synthetic-prepared-card'});
        return null;
      });
      await const NativeAchievementSharer().share(png, () async {
        steps.add('validated');
      });
      expect(steps, [
        'validated',
        'prepareAchievementShare',
        'validated',
        'launchAchievementShare',
        'discardAchievementShare',
      ]);
    },
  );

  test(
    'owner invalidation after native preparation discards without launching',
    () async {
      final steps = <String>[];
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        steps.add(call.method);
        return call.method == 'prepareAchievementShare'
            ? 'synthetic-prepared-card'
            : null;
      });
      await expectLater(
        const NativeAchievementSharer().share(png, () async {
          if (++reads == 2) {
            throw const ExportException(ExportFailureCode.cancelled);
          }
        }),
        throwsA(isA<ExportException>()),
      );
      expect(steps, ['prepareAchievementShare', 'discardAchievementShare']);
    },
  );

  test(
    'missing native capability has a typed failure and never claims a share',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      await expectLater(
        const NativeAchievementSharer().share(png, () async {}),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
    },
  );
}
