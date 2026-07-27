import 'dart:math';

class VocabularyMixer {
  final String policyVersion;

  VocabularyMixer({this.policyVersion = 'v1.0.0'});

  List<String> selectTargetWords({
    required List<String> dueWords,
    required List<String> weakWords,
    required List<String> newWords,
    int targetCount = 6,
    int maxNew = 2,
    int? seed,
  }) {
    final rng = Random(seed);

    final dueCopy = List<String>.from(dueWords)..shuffle(rng);
    final weakCopy = List<String>.from(weakWords)..shuffle(rng);
    final newCopy = List<String>.from(newWords)..shuffle(rng);

    final selected = <String>{};

    // Allocate 50% due, 30% weak, 20% new
    final desiredNewCount = min(
      maxNew,
      (targetCount * 0.2).round().clamp(1, targetCount),
    );
    for (int i = 0; i < desiredNewCount && newCopy.isNotEmpty; i++) {
      selected.add(newCopy.removeLast());
    }

    final desiredDueCount = (targetCount * 0.5).round();
    for (int i = 0; i < desiredDueCount && dueCopy.isNotEmpty; i++) {
      selected.add(dueCopy.removeLast());
    }

    final desiredWeakCount = (targetCount * 0.3).round();
    for (int i = 0; i < desiredWeakCount && weakCopy.isNotEmpty; i++) {
      selected.add(weakCopy.removeLast());
    }

    // Fill remaining budget deterministically from due -> weak -> new
    final remainingPool = [...dueCopy, ...weakCopy, ...newCopy];
    while (selected.length < targetCount && remainingPool.isNotEmpty) {
      selected.add(remainingPool.removeLast());
    }

    return selected.toList();
  }
}
