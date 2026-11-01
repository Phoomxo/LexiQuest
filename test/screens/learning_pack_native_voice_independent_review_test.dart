import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';

import 'learning_pack_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final exit in ['back', 'background']) {
    testWidgets('native start acknowledgement still stops on $exit', (
      tester,
    ) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      final adapter = _StartAcknowledgedNativeTts();
      try {
        await tester.runAsync(() => h.seed(syntheticPackUiContent()));
        final original = (h.app() as AppDependenciesScope).dependencies;
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: original.runtimeStatus,
              config: null,
              guestSessionService: original.guestSessionService,
              database: h.database,
              learningPacks: h.packs,
              voice: VoiceUseCases(NativeTtsProvider(adapter)),
            ),
            child: const MaterialApp(home: LearningPackCatalogScreen()),
          ),
        );
        await openPackUiDetail(tester);
        await tapPackUi(tester, 'pack-word-cat');
        await untilPackUi(
          tester,
          () => find.text('A small pet that meows.').evaluate().isNotEmpty,
        );
        await tapPackUi(tester, 'pack-word-speak');
        await idlePackUi(tester);
        expect(adapter.spoken, ['cat']);
        expect(adapter.playing, isTrue);
        expect(adapter.stops, 0);
        if (exit == 'back') {
          await tester.tap(find.byTooltip('กลับไปยังรายการแพ็ก'));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(adapter.stops, 1);
        expect(adapter.playing, isFalse);
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        expect(await tester.runAsync(() => h.count('answer_attempts')), 0);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    });
  }
}

final class _StartAcknowledgedNativeTts implements NativeTtsAdapter {
  final spoken = <String>[];
  bool playing = false;
  int stops = 0;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    playing = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }

  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPitch(double pitch) async {}
}
