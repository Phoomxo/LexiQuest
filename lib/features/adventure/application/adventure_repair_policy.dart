import '../../learning/domain/lesson_mode.dart';
import '../../learning_packs/domain/content_manifest.dart';

enum AdventureAttemptOutcome { correct, incorrect, skipped, technical, guided }

enum AdventureRepairDisposition {
  inserted,
  deferredToCanonicalReview,
  alreadyScheduled,
  notApplicable,
}

final class AdventureRepairItem {
  const AdventureRepairItem({
    required this.identity,
    required this.mode,
    this.isRepair = false,
  });

  final ContentIdentity identity;
  final LessonMode mode;
  final bool isRepair;

  AdventureRepairItem asRepair(LessonMode repairMode) =>
      AdventureRepairItem(identity: identity, mode: repairMode, isRepair: true);
}

typedef AdventureModeEligibility = bool Function(LessonMode mode);

/// Bounded, in-session queue decoration. Canonical evidence and SRS deferral
/// remain owned by Learning; this policy only chooses whether and where a
/// single retry can appear.
final class AdventureRepairPolicy {
  AdventureRepairPolicy({required this.isModeEligible});

  static const int minimumInterveningItems = 3;
  static const int maximumInterveningItems = 5;

  final AdventureModeEligibility isModeEligible;
  final Set<ContentIdentity> _scheduled = <ContentIdentity>{};

  bool schedule({
    required List<AdventureRepairItem> queue,
    required int completedIndex,
    required AdventureAttemptOutcome outcome,
  }) =>
      scheduleDecision(
        queue: queue,
        completedIndex: completedIndex,
        outcome: outcome,
      ) ==
      AdventureRepairDisposition.inserted;

  AdventureRepairDisposition scheduleDecision({
    required List<AdventureRepairItem> queue,
    required int completedIndex,
    required AdventureAttemptOutcome outcome,
  }) {
    if (completedIndex < 0 || completedIndex >= queue.length) {
      throw RangeError.index(completedIndex, queue, 'completedIndex');
    }
    final item = queue[completedIndex];
    if (outcome != AdventureAttemptOutcome.incorrect) {
      return AdventureRepairDisposition.notApplicable;
    }
    if (item.isRepair) {
      return AdventureRepairDisposition.deferredToCanonicalReview;
    }
    if (_scheduled.contains(item.identity)) {
      return AdventureRepairDisposition.alreadyScheduled;
    }
    final remainingOriginals = queue
        .skip(completedIndex + 1)
        .where((candidate) => !candidate.isRepair)
        .length;
    if (remainingOriginals < minimumInterveningItems) {
      return AdventureRepairDisposition.deferredToCanonicalReview;
    }

    final repairMode = _nextEligibleMode(item.mode);
    if (repairMode == null) {
      return AdventureRepairDisposition.deferredToCanonicalReview;
    }
    final intervening = remainingOriginals.clamp(
      minimumInterveningItems,
      maximumInterveningItems,
    );
    var insertionIndex = completedIndex + 1;
    var observedOriginals = 0;
    while (insertionIndex < queue.length && observedOriginals < intervening) {
      if (!queue[insertionIndex].isRepair) observedOriginals += 1;
      insertionIndex += 1;
    }
    queue.insert(insertionIndex, item.asRepair(repairMode));
    _scheduled.add(item.identity);
    return AdventureRepairDisposition.inserted;
  }

  LessonMode? _nextEligibleMode(LessonMode current) {
    final ladder = <LessonMode>[
      LessonMode.flashcard,
      LessonMode.meaningQuiz,
      LessonMode.matching,
      LessonMode.cloze,
      LessonMode.typedRecall,
    ];
    final currentIndex = ladder.indexOf(current);
    final start = currentIndex < 0 ? 0 : currentIndex + 1;
    for (final mode in ladder.skip(start)) {
      if (isModeEligible(mode)) return mode;
    }
    if (current == LessonMode.typedRecall &&
        isModeEligible(LessonMode.typedRecall)) {
      return LessonMode.typedRecall;
    }
    return null;
  }
}
