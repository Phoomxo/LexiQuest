import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';

/// Injects a pre-commit terminal failure while every successful operation uses
/// the actual repository. Unexpected calls fail rather than inventing results.
final class FailOnceSessionCloseRepository implements LearningRepository {
  FailOnceSessionCloseRepository(this.delegate);
  final LearningRepository delegate;
  final List<(String, String, DateTime)> closes = [];
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );
  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    closes.add((ownerId, sessionId, endedAtUtc));
    if (closes.length == 1) {
      throw StateError('injected pre-commit close failure');
    }
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
