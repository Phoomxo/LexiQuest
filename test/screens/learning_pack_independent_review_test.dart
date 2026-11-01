import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';

import 'learning_pack_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final leaveCard in [false, true]) {
    testWidgets(
      leaveCard
          ? 'leaving a lexical card cancels speech awaiting its real word read'
          : 'remaining on a lexical card plays its acknowledged real word read',
      (tester) async {
        final h = (await tester.runAsync(LearningPackUiHarness.open))!;
        final repository = _DelayedLexicalRead(h.repository);
        final packs = LearningPackUseCases(
          repository: repository,
          nowUtc: () => DateTime.utc(2026, 11, 1),
          generateId: () => throw StateError('Speech must not prepare writes'),
        );
        try {
          await tester.runAsync(() => h.seed(syntheticPackUiContent()));
          final normal = h.app() as AppDependenciesScope;
          final dependencies = normal.dependencies;
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: AppDependencies(
                runtimeStatus: dependencies.runtimeStatus,
                config: null,
                guestSessionService: dependencies.guestSessionService,
                database: h.database,
                learningPacks: packs,
                voice: VoiceUseCases(h.voice),
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
          repository.pause = true;
          await tapPackUi(tester, 'pack-word-speak');
          await untilPackUi(tester, () => repository.held);
          expect(h.voice.requests, isEmpty);
          if (leaveCard) {
            await tester.tap(find.byTooltip('กลับไปยังรายการแพ็ก'));
            await tester.pump(const Duration(milliseconds: 16));
            expect(find.text('คำศัพท์ในแพ็ก'), findsOneWidget);
            expect(find.text('A small pet that meows.'), findsNothing);
          }
          repository.release.complete();
          await idlePackUi(tester);
          expect(h.voice.requests, hasLength(leaveCard ? 0 : 1));
          if (!leaveCard) expect(h.voice.requests.single.text, 'cat');
          expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
          expect(await tester.runAsync(() => h.count('answer_attempts')), 0);
          expect(await tester.runAsync(() => h.count('research_consents')), 0);
          expect(tester.takeException(), isNull);
        } catch (error, stack) {
          h.recordFailure(error, stack, tester);
          rethrow;
        } finally {
          if (!repository.release.isCompleted) repository.release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          var closed = false;
          final closing = packs.dispose().whenComplete(() => closed = true);
          await untilPackUi(tester, () => closed);
          await closing;
          await closePackUi(tester, h);
        }
      },
    );
  }
}

final class _DelayedLexicalRead implements LearningPackRepository {
  _DelayedLexicalRead(this.delegate);
  final LearningPackRepository delegate;
  final release = Completer<void>();
  bool pause = false;
  bool held = false;

  @override
  Future<CurrentLexicalContent?> currentLexical({
    required String expectedOwnerId,
    required String wordId,
    String? packVersionId,
    required bool Function() stillCurrent,
  }) async {
    final result = await delegate.currentLexical(
      expectedOwnerId: expectedOwnerId,
      wordId: wordId,
      packVersionId: packVersionId,
      stillCurrent: stillCurrent,
    );
    if (pause) {
      held = true;
      await release.future;
    }
    return result;
  }

  @override
  Future<StoredLearningPack> importPack(PackImportIntent intent) =>
      delegate.importPack(intent);
  @override
  Future<StoredLearningPack> changeCache(PackCacheIntent intent) =>
      delegate.changeCache(intent);
  @override
  Future<String?> readActiveOwnerId() => delegate.readActiveOwnerId();
  @override
  Stream<String?> watchActiveOwnerId() => delegate.watchActiveOwnerId();
  @override
  Future<List<StoredLearningPack>> list({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => delegate.list(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );
  @override
  Future<PackDetail> detail({
    required String expectedOwnerId,
    required String packVersionId,
    required bool Function() stillCurrent,
  }) => delegate.detail(
    expectedOwnerId: expectedOwnerId,
    packVersionId: packVersionId,
    stillCurrent: stillCurrent,
  );
}
