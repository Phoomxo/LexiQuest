import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

LearningUseCases buildFailOnceLearningUseCases({
  required FailOnceLearningRepository repository,
  required String idPrefix,
}) {
  var nextId = 0;
  var clockTick = 0;
  return LearningUseCases(
    owners: const FixedLearningOwnerRepository(),
    repository: repository,
    generateId: () => '$idPrefix-${++nextId}',
    nowUtc: () => DateTime.utc(2026, 8, 30, 9, 0, 0, clockTick++),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
}

final class FixedLearningOwnerRepository implements LocalOwnerRepository {
  const FixedLearningOwnerRepository();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'owner-1', createdAtUtc: DateTime.utc(2026, 8, 30));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class FailOnceLearningRepository implements LearningRepository {
  FailOnceLearningRepository({this.failFirst = true});

  final bool failFirst;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  var _failed = false;

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (failFirst && !_failed) {
      _failed = true;
      throw StateError('simulated local evidence failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
