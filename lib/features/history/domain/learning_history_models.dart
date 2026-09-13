import '../../assessment/domain/assessment_models.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/first_answer_accuracy.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/pair_matching/domain/pair_matching_history_projection.dart';
import '../../learning/domain/lesson_session_state.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';

enum LearningHistoryTerminalState { completed, abandoned }

enum LearningHistoryContentAvailability { available, unavailable }

/// Describes the recorded activity, not a content revision or replay permit.
/// Historic local CEFR configurations did not pin a passage title or level.
final class LearningHistoryLocalCefrPresentation {
  const LearningHistoryLocalCefrPresentation._();

  String get titleThai => 'กิจกรรมอ่านตามระดับ CEFR';
  String get detailThai =>
      'รอบนี้บันทึกการฝึกอ่านไว้ แต่ไม่ได้บันทึกชื่อบทอ่านหรือระดับที่เลือก';
}

final class HistoryFilter {
  const HistoryFilter({
    required this.ownerId,
    this.limit = 20,
    this.includePracticeReplay = true,
  });

  final String ownerId;
  final int limit;
  final bool includePracticeReplay;
}

final class LearningHistoryEventSnapshot {
  factory LearningHistoryEventSnapshot.fromValidatedEnvelope(
    EventEnvelopeV2 envelope,
  ) {
    final snapshot = _deepFreezeCanonicalMap(envelope.toJson(), 'event');
    final eventId = snapshot['eventId'];
    final eventType = snapshot['eventType'];
    final eventVersion = snapshot['eventVersion'];
    final occurredAtUtc = snapshot['occurredAtUtc'];
    final recordedAtUtc = snapshot['recordedAtUtc'];
    final ownerIdentity = snapshot['ownerIdentity'];
    final aggregateType = snapshot['aggregateType'];
    final aggregateId = snapshot['aggregateId'];
    final payload = snapshot['payload'];
    if (eventId is! String ||
        eventType is! String ||
        eventVersion is! int ||
        eventVersion < 1 ||
        occurredAtUtc is! String ||
        recordedAtUtc is! String ||
        ownerIdentity is! String ||
        aggregateType is! String ||
        aggregateId is! String ||
        payload is! Map<String, Object?>) {
      throw ArgumentError('invalid learning-history event snapshot');
    }
    _requireCanonicalText(eventId, 'event.eventId');
    _requireCanonicalText(eventType, 'event.eventType');
    _requireCanonicalText(ownerIdentity, 'event.ownerIdentity');
    _requireCanonicalText(aggregateType, 'event.aggregateType');
    _requireCanonicalText(aggregateId, 'event.aggregateId');
    _requireUtc(DateTime.parse(occurredAtUtc), 'event.occurredAtUtc');
    _requireUtc(DateTime.parse(recordedAtUtc), 'event.recordedAtUtc');
    return LearningHistoryEventSnapshot._(snapshot);
  }

  const LearningHistoryEventSnapshot._(this._snapshot);

  final Map<String, Object?> _snapshot;

  String get eventId => _snapshot['eventId']! as String;
  String get eventType => _snapshot['eventType']! as String;
  int get eventVersion => _snapshot['eventVersion']! as int;
  DateTime get occurredAtUtc =>
      DateTime.parse(_snapshot['occurredAtUtc']! as String);
  DateTime get recordedAtUtc =>
      DateTime.parse(_snapshot['recordedAtUtc']! as String);
  String get ownerIdentity => _snapshot['ownerIdentity']! as String;
  String get aggregateType => _snapshot['aggregateType']! as String;
  String get aggregateId => _snapshot['aggregateId']! as String;
  Map<String, Object?> get payload =>
      _snapshot['payload']! as Map<String, Object?>;

  Map<String, Object?> toJson() => _snapshot;
}

final class LearningHistoryAssessmentSummary {
  LearningHistoryAssessmentSummary({
    required this.phase,
    required this.state,
    required this.terminalAtUtc,
    required this.instrumentVersion,
    required this.formVersion,
    required this.sampleSize,
    required this.correctCount,
    required this.incorrectCount,
    required this.accuracy,
  }) {
    if (state == AssessmentRunState.active) {
      throw ArgumentError.value(state, 'state', 'must be terminal');
    }
    _requireUtc(terminalAtUtc, 'terminalAtUtc');
    _requireCanonicalText(instrumentVersion, 'instrumentVersion');
    _requireCanonicalText(formVersion, 'formVersion');
    if (sampleSize < 0 ||
        correctCount < 0 ||
        incorrectCount < 0 ||
        correctCount + incorrectCount != sampleSize ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 1 ||
        accuracy != (sampleSize == 0 ? 0 : correctCount / sampleSize)) {
      throw ArgumentError('invalid assessment outcome summary');
    }
  }

  final AssessmentPhase phase;
  final AssessmentRunState state;
  final DateTime terminalAtUtc;
  final String instrumentVersion;
  final String formVersion;
  final int sampleSize;
  final int correctCount;
  final int incorrectCount;
  final double accuracy;
}

final class LearningHistoryEvidence {
  const LearningHistoryEvidence({
    required this.attemptId,
    required this.eventId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.occurredAtUtc,
    required this.evidenceContext,
    required this.event,
  });

  final String attemptId;
  final String eventId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final DateTime occurredAtUtc;
  final EvidenceContext evidenceContext;
  final LearningHistoryEventSnapshot event;
}

final class LearningHistoryEntry {
  LearningHistoryEntry({
    required this.sessionId,
    required this.ownerId,
    required this.mode,
    required this.packIdentity,
    required this.packTitle,
    required this.contentAvailability,
    required this.activeLearningDuration,
    required this.terminalState,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.correctCount,
    required this.wrongCount,
    required this.score,
    required this.sessionConfiguration,
    required Iterable<LearningHistoryEvidence> evidence,
    this.assessmentSummary,
    this.pairSummary,
    this.pairPurposeUnavailable = false,
  }) : evidence = List<LearningHistoryEvidence>.unmodifiable(evidence) {
    _requireCanonicalText(sessionId, 'sessionId');
    _requireCanonicalText(ownerId, 'ownerId');
    _requireUtc(startedAtUtc, 'startedAtUtc');
    _requireUtc(endedAtUtc, 'endedAtUtc');
    if (endedAtUtc.isBefore(startedAtUtc)) {
      throw ArgumentError.value(
        endedAtUtc,
        'endedAtUtc',
        'must not be before startedAtUtc',
      );
    }
    if (packTitle != null) {
      _requireCanonicalText(packTitle!, 'packTitle');
    }
    if ((contentAvailability == LearningHistoryContentAvailability.available) !=
        (packTitle != null)) {
      throw ArgumentError(
        'available content requires one canonical pack title',
      );
    }
    final configuration = sessionConfiguration;
    if (activeLearningDuration.isNegative ||
        correctCount < 0 ||
        wrongCount < 0 ||
        (score != null && score! < 0)) {
      throw ArgumentError('invalid immutable learning-history entry');
    }
    if (configuration == null) {
      if (packIdentity != null) {
        throw ArgumentError(
          'history cannot infer pack identity without canonical configuration',
        );
      }
    } else if (configuration.ownerId != ownerId ||
        configuration.mode != mode ||
        configuration.packIdentity != packIdentity) {
      throw ArgumentError('invalid immutable learning-history configuration');
    }
    if (packTitle != null && packIdentity == null) {
      throw ArgumentError('history cannot present a title without pack pins');
    }
    final assessment = assessmentSummary;
    final assessmentTerminalState = assessment == null
        ? null
        : switch (assessment.state) {
            AssessmentRunState.completed =>
              LearningHistoryTerminalState.completed,
            AssessmentRunState.abandoned =>
              LearningHistoryTerminalState.abandoned,
            AssessmentRunState.active => throw ArgumentError(
              'assessment summary must be terminal',
            ),
          };
    if (assessment != null &&
        (mode != null ||
            packIdentity != null ||
            packTitle != null ||
            contentAvailability !=
                LearningHistoryContentAvailability.unavailable ||
            configuration != null ||
            this.evidence.isNotEmpty ||
            score != null ||
            endedAtUtc != assessment.terminalAtUtc ||
            terminalState != assessmentTerminalState ||
            correctCount != assessment.correctCount ||
            wrongCount != assessment.incorrectCount)) {
      throw ArgumentError('assessment history must remain outcome-only');
    }
    for (final item in this.evidence) {
      if (item.event.aggregateId != sessionId ||
          item.event.ownerIdentity != ownerId) {
        throw ArgumentError('evidence does not belong to history session');
      }
    }
  }

  final String sessionId;
  final String ownerId;
  final LessonMode? mode;
  final ContentIdentity? packIdentity;
  final String? packTitle;
  final LearningHistoryContentAvailability contentAvailability;
  final Duration activeLearningDuration;
  final LearningHistoryTerminalState terminalState;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final int correctCount;
  final int wrongCount;
  final int? score;
  final SessionConfiguration? sessionConfiguration;
  final List<LearningHistoryEvidence> evidence;
  final LearningHistoryAssessmentSummary? assessmentSummary;
  final PairMatchingHistoryProjection? pairSummary;
  final bool pairPurposeUnavailable;

  /// Display-only first/repair axes; legacy aggregate fields above stay intact.
  ({int correct, int total}) get firstAnswers {
    final first = _firstEvidence;
    return (
      correct: first.where((row) => row.isCorrect).length,
      total: first.length,
    );
  }

  ({int correct, int total}) get repairAnswers {
    final firstIds = _firstEvidence.map((row) => row.attemptId).toSet();
    final repair = evidence.where(
      (row) =>
          FirstAnswerAccuracy.includes(row.evidenceContext) &&
          !firstIds.contains(row.attemptId),
    );
    return (
      correct: repair.where((row) => row.isCorrect).length,
      total: repair.length,
    );
  }

  List<LearningHistoryEvidence> get _firstEvidence {
    final ordered = evidence.toList()
      ..sort((a, b) {
        final time = a.occurredAtUtc.compareTo(b.occurredAtUtc);
        if (time != 0) return time;
        final ordinal = ((a.event.payload['attemptNumber'] as int?) ?? 0)
            .compareTo((b.event.payload['attemptNumber'] as int?) ?? 0);
        return ordinal != 0 ? ordinal : a.attemptId.compareTo(b.attemptId);
      });
    return FirstAnswerAccuracy.select(
      ordered,
      contextOf: (row) => row.evidenceContext,
      identityOf: (row, context) => (
        ownerId,
        sessionId,
        row.wordId,
        row.promptMode,
        context.contentRevision,
        context.skillId,
      ),
    );
  }

  /// Only the validated configuration identifies this local activity. Do not
  /// infer historical content from today's catalog or mutable vocabulary.
  LearningHistoryLocalCefrPresentation? get localCefrPresentation {
    final configuration = sessionConfiguration;
    if (assessmentSummary != null ||
        configuration == null ||
        configuration.mode != LessonMode.cefrReading ||
        configuration.packIdentity != null) {
      return null;
    }
    return const LearningHistoryLocalCefrPresentation._();
  }
}

abstract interface class LearningHistoryReader {
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter);

  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  });
}

void _requireCanonicalText(String value, String name) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
}

void _requireUtc(DateTime value, String name) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, name, 'must be nonnegative UTC');
  }
}

Map<String, Object?> _deepFreezeCanonicalMap(Map source, String name) {
  final keys = <String>[];
  for (final key in source.keys) {
    if (key is! String) {
      throw ArgumentError.value(key, name, 'JSON object keys must be strings');
    }
    keys.add(key);
  }
  keys.sort();
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final key in keys)
      key: _deepFreezeCanonicalValue(source[key], '$name.$key'),
  });
}

Object? _deepFreezeCanonicalValue(Object? value, String name) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be finite JSON data');
    }
    return value;
  }
  if (value is Map) return _deepFreezeCanonicalMap(value, name);
  if (value is List) {
    return List<Object?>.unmodifiable(<Object?>[
      for (var index = 0; index < value.length; index += 1)
        _deepFreezeCanonicalValue(value[index], '$name[$index]'),
    ]);
  }
  throw ArgumentError.value(value, name, 'must contain canonical JSON data');
}
