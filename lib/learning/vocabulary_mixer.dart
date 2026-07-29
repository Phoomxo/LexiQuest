import 'dart:math';

final class VocabularyMixRequest {
  const VocabularyMixRequest({
    required this.dueWords,
    required this.weakWords,
    required this.newWords,
    this.targetCount = 6,
    this.maxNewWords = 2,
    required this.seed,
  }) : assert(targetCount >= 1 && targetCount <= 8),
       assert(maxNewWords >= 0 && maxNewWords <= targetCount);

  final List<String> dueWords;
  final List<String> weakWords;
  final List<String> newWords;
  final int targetCount;
  final int maxNewWords;
  final int seed;
}

final class VocabularyMixResult {
  VocabularyMixResult({
    required List<String> words,
    required this.algorithmVersion,
  }) : words = List<String>.unmodifiable(words);

  final List<String> words;
  final String algorithmVersion;
}

final class VersionedVocabularyMixer {
  const VersionedVocabularyMixer();

  static const algorithmVersion = 'mixer-v1';

  VocabularyMixResult mix(VocabularyMixRequest request) {
    final due = _rank(request.dueWords, request.seed, 'due');
    final weak = _rank(request.weakWords, request.seed, 'weak');
    final fresh = _rank(request.newWords, request.seed, 'new');
    final selected = <String>{};

    final desiredNew = min(
      request.maxNewWords,
      max(1, (request.targetCount * 0.2).round()),
    );
    final desiredDue = (request.targetCount * 0.5).round();
    final desiredWeak = (request.targetCount * 0.3).round();

    _take(selected, fresh, desiredNew, request.targetCount);
    _take(selected, due, desiredDue, request.targetCount);
    _take(selected, weak, desiredWeak, request.targetCount);
    _take(
      selected,
      [...due, ...weak, ...fresh],
      request.targetCount,
      request.targetCount,
    );

    return VocabularyMixResult(
      words: selected.toList(growable: false),
      algorithmVersion: algorithmVersion,
    );
  }
}

List<String> _rank(List<String> words, int seed, String source) {
  final unique = words.where((word) => word.trim().isNotEmpty).toSet().toList();
  unique.sort((left, right) {
    final byHash = _stableHash(
      '$seed|$source|$left',
    ).compareTo(_stableHash('$seed|$source|$right'));
    return byHash != 0 ? byHash : left.compareTo(right);
  });
  return unique;
}

void _take(
  Set<String> selected,
  List<String> candidates,
  int count,
  int targetCount,
) {
  var added = 0;
  for (final candidate in candidates) {
    if (selected.length >= targetCount || added >= count) {
      return;
    }
    if (selected.add(candidate)) {
      added++;
    }
  }
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
