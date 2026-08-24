import 'dart:collection';

import 'content_manifest.dart';

/// Read-only catalog criteria. Values within each dimension are alternatives;
/// non-empty dimensions are combined together.
final class LearningPackFilter {
  LearningPackFilter({
    Iterable<String> cefrLevels = const [],
    Iterable<String> topics = const [],
    Iterable<String> skills = const [],
    Iterable<String> goals = const [],
  }) : cefrLevels = _canonicalValues(cefrLevels, 'cefrLevels'),
       topics = _canonicalValues(topics, 'topics'),
       skills = _canonicalValues(skills, 'skills'),
       goals = _canonicalValues(goals, 'goals');

  final Set<String> cefrLevels;
  final Set<String> topics;
  final Set<String> skills;
  final Set<String> goals;

  bool matches(LearningPackSummary pack) {
    return _matches(cefrLevels, pack.cefrLevel) &&
        _matches(topics, pack.topic) &&
        _matches(skills, pack.skill) &&
        _matches(goals, pack.goal);
  }

  static Set<String> _canonicalValues(Iterable<String> values, String name) {
    final result = <String>{};
    for (final value in values) {
      if (value.trim().isEmpty || value != value.trim()) {
        throw ArgumentError.value(
          value,
          name,
          'must be canonical and nonblank',
        );
      }
      result.add(value);
    }
    return UnmodifiableSetView(result);
  }

  static bool _matches(Set<String> alternatives, String value) =>
      alternatives.isEmpty || alternatives.contains(value);
}

/// A catalog item pinned to the verified pack revision it represents.
final class LearningPackSummary {
  LearningPackSummary({
    required this.packId,
    required this.revision,
    required this.title,
    required this.cefrLevel,
    required this.topic,
    required this.skill,
    required this.goal,
    required this.contentIdentity,
  }) : assert(packId != ''),
       assert(revision > 0),
       assert(title != ''),
       assert(cefrLevel != ''),
       assert(topic != ''),
       assert(skill != ''),
       assert(goal != ''),
       assert(contentIdentity.type == ContentType.learningPack),
       assert(contentIdentity.id == packId),
       assert(contentIdentity.revision == revision);

  final String packId;
  final int revision;
  final String title;
  final String cefrLevel;
  final String topic;
  final String skill;
  final String goal;
  final ContentIdentity contentIdentity;
}
