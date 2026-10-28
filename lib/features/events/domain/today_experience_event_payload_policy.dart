import '../../adventure/domain/adventure_entry.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../research/domain/motivation_study_protocol.dart';

/// Exact allowlist, shared by both presentations. No answer/word/free-text data.
abstract final class TodayExperienceEventPayloadPolicy {
  static void validate(String type, Map<String, dynamic> payload) {
    const common = {'assignedTreatment', 'effectivePresentation'};
    final keys = switch (type) {
      'TodayExperiencePresented' => {
        ...common,
        'entryAttemptId',
        'catalogVersion',
      },
      'TodayExperiencePresentationChanged' => {
        ...common,
        'fromPresentation',
        'switchOrdinal',
      },
      'TodayExperienceMissionStarted' => {
        ...common,
        'opportunityId',
        'planId',
        'mode',
      },
      'TodayExperienceMissionCompleted' => {
        ...common,
        'opportunityId',
        'planId',
        'terminalState',
      },
      _ => throw const FormatException('Unknown research event type'),
    };
    if (payload.length != keys.length || !payload.keys.every(keys.contains)) {
      throw const FormatException('Invalid research payload fields');
    }
    for (final key in [
      'assignedTreatment',
      'effectivePresentation',
      if (payload.containsKey('fromPresentation')) 'fromPresentation',
    ]) {
      if (TodayExperiencePresentationCodec.tryDecode(payload[key]) == null) {
        throw const FormatException('Invalid presentation code');
      }
    }
    for (final key in keys.difference({
      ...common,
      'fromPresentation',
      'switchOrdinal',
    })) {
      final value = payload[key];
      if (value is! String) {
        throw const FormatException('Expected research code');
      }
      requireResearchCode(value);
    }
    if (type == 'TodayExperiencePresented' &&
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(payload['entryAttemptId'] as String)) {
      throw const FormatException('Expected UUID v4');
    }
    if (type == 'TodayExperiencePresentationChanged') {
      final ordinal = payload['switchOrdinal'];
      if (ordinal is! int ||
          ordinal < 1 ||
          ordinal > 10 ||
          payload['fromPresentation'] == payload['effectivePresentation']) {
        throw const FormatException('Invalid presentation switch');
      }
    }
    if (type == 'TodayExperienceMissionStarted' &&
        !LessonMode.values.any((m) => m.id == payload['mode'])) {
      throw const FormatException('Invalid lesson mode');
    }
    if (type == 'TodayExperienceMissionCompleted' &&
        payload['terminalState'] != 'completed') {
      throw const FormatException('Invalid completion');
    }
  }
}
