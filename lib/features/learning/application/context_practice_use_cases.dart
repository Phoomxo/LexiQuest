import '../../identity/application/owner_generation.dart';
import '../../learning_packs/application/personal_set_activities.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../domain/context_practice.dart';
import '../domain/evidence_context.dart';
import '../domain/lesson_mode.dart';
import 'cloze_mode_adapter.dart';

final class ContextPracticeRollout {
  const ContextPracticeRollout.implementedOff() : enabled = false;
  const ContextPracticeRollout.internal() : enabled = true;
  final bool enabled;
}

/// No hints or answer-format switching before the canonical attempt. Guided
/// repair follows commitment and preserves its separate assistance history.
final class ContextPracticeModeAdapter
    implements FocusTimerSupportingLessonModeAdapter {
  const ContextPracticeModeAdapter();
  @override
  LessonMode get mode => LessonMode.cloze;
  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      const ClozeModeAdapter().classify(response, support);
  @override
  Future<LessonItem> next(LessonCursor cursor) =>
      Future.error(StateError('Context practice owns its pinned items'));
}

final class ContextPracticeUseCases {
  const ContextPracticeUseCases(this.activities);
  final PersonalSetActivities activities;
  bool get isAvailable => activities.canPracticeContext;

  Future<PersonalSetActivityLaunch> start(
    OwnerGenerationToken owner, {
    required String setId,
    required int revision,
    required String operationId,
    required ClozeInputMode inputMode,
  }) => activities.start(
    owner,
    setId: setId,
    revision: revision,
    operationId: operationId,
    contextInput: inputMode,
  );

  Future<PersonalSetActivityLaunch?> resume(OwnerGenerationToken owner) async {
    await activities.sets.ownerGeneration.requireCurrentAsync(owner);
    if (!isAvailable) throw StateError('Context practice is unavailable');
    final recovery = await activities.learning.loadActivityRecovery(
      activityType: 'contextPractice',
      ownerId: owner.ownerId,
    );
    if (recovery == null) return null;
    final state = recovery.checkpoint?.state;
    if (state == null ||
        state.length != 7 ||
        state['schemaVersion'] != 1 ||
        state['kind'] != 'contextPractice' ||
        state['inventoryRevision'] != ContextPracticeInventory.revision ||
        state['inventoryHash'] != ContextPracticeInventory.fingerprint ||
        !['selected', 'typed'].contains(state['inputMode'])) {
      throw StateError(
        'Context checkpoint is unsupported; no writes performed',
      );
    }
    final saved = PersonalSetRevision.fromJson(
      Map<String, Object?>.from(state['personalSetRevision'] as Map),
    );
    return start(
      owner,
      setId: saved.setId,
      revision: saved.revision,
      operationId: state['launchOperationId'] as String,
      inputMode: state['inputMode'] == 'typed'
          ? ClozeInputMode.typed
          : ClozeInputMode.selected,
    );
  }
}
