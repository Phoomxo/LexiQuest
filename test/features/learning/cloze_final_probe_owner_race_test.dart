import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';

import '../../support/cloze_session_harness.dart';

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  LearningUseCases learning(_ProbeBoundaryRepository repository) =>
      LearningUseCases(
        owners: h.storage.owners,
        repository: repository,
        generateId: h.learning.generateId,
        nowUtc: () => h.now,
        buildInfo: h.learning.buildInfo,
        contentProvider: h.provider,
      );

  for (final variant in ClozeVariant.values) {
    test(
      '$variant active-owner change during final real ambient probe sends zero generation requests despite lagging UI watch',
      () async {
        final repository = _ProbeBoundaryRepository(
          h.repository,
          afterSecondProbe: () => h.storage.switchOwner(configuredOtherOwnerId),
        );
        await expectLater(
          learning(repository).prepareCloze(
            categoryId: configuredCategoryId,
            variant: variant,
            stillCurrent: () => h.current,
          ),
          throwsStateError,
        );
        expect(repository.observations, [false, false]);
        expect(
          (await h.storage.owners.getOrCreateActiveOwner()).id,
          configuredOtherOwnerId,
        );
        expect(
          h.current,
          isTrue,
          reason:
              'the owner authority must not rely on the lagging UI current callback',
        );
        expect(
          h.provider.requests,
          isEmpty,
          reason:
              'post-generation owner rejection cannot retract an already sent target',
        );
        expect(h.provider.transactionStates, isEmpty);
        expect(await h.storage.count('learning_sessions'), 0);
        expect(await h.storage.count('answer_attempts'), 0);
        expect(await h.storage.count('outbox_operations'), 0);
      },
    );

    test(
      '$variant unchanged real owner through the same probe wrapper generates once outside SQL transactions',
      () async {
        final repository = _ProbeBoundaryRepository(h.repository);
        final result = await learning(repository).prepareCloze(
          categoryId: configuredCategoryId,
          variant: variant,
          stillCurrent: () => h.current,
        );
        expect(result, isNotNull);
        expect(result!.ownerId, configuredOwnerId);
        expect(repository.observations, [false, false]);
        expect(h.provider.requests, hasLength(1));
        expect(h.provider.requests.single.text, result.word.spelling);
        expect(h.provider.transactionStates, [false]);
        expect(await h.storage.count('learning_sessions'), 0);
      },
    );
  }
}

final class _ProbeBoundaryRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  _ProbeBoundaryRepository(this.delegate, {this.afterSecondProbe});

  final DriftLearningRepository delegate;
  final Future<void> Function()? afterSecondProbe;
  final List<bool> observations = [];

  @override
  Future<bool> hasAmbientTransaction() async {
    final actual = await delegate.hasAmbientTransaction();
    observations.add(actual);
    if (observations.length == 2) {
      await afterSecondProbe?.call();
    }
    return actual;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
}
