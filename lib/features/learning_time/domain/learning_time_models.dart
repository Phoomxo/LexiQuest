part of '../application/learning_time_use_cases.dart';

const learningTimeCapturePolicyRevision = 'confirmed-interaction-v1';
const learningTimeMaximumInputGapUs = 60000000;
const learningTimeCheckpointUs = 60000000;
const learningTimeMaximumSegmentUs = 120000000;
const learningTimeMaximumJsonBytes = 16384;

enum TimeSourceKind {
  configuredQuiz,
  ownedSrs,
  dictation,
  cloze,
  voicePractice,
  reading,
  tutor,
}

sealed class TimeSource {
  const TimeSource({required this.callerContext});
  final LearningTimeCallerContext callerContext;
}

final class CanonicalTimeSource extends TimeSource {
  const CanonicalTimeSource(this.proof, {required super.callerContext});
  final CanonicalLearningTimeAdmission proof;
}

/// Pins come from the actual immutable displayed document, never a locator alone.
final class ReadingTimeSource extends TimeSource {
  const ReadingTimeSource({
    required this.documentId,
    required this.documentRevision,
    required this.snapshotSha256,
    required this.targetPinsSha256,
    required this.readingStage,
    this.targetWordId,
    this.targetContentRevision,
    required super.callerContext,
  });
  final String documentId;
  final int documentRevision;
  final String snapshotSha256;
  final String targetPinsSha256;
  final int readingStage;
  final String? targetWordId;
  final String? targetContentRevision;

  String get sourceBindingJson => jsonEncode({
    'schemaVersion': 1,
    'kind': 'reading',
    'documentId': documentId,
    'documentRevision': documentRevision,
    'snapshotSha256': snapshotSha256,
    'targetPinsSha256': targetPinsSha256,
  });

  String get contextBindingJson => jsonEncode({
    'schemaVersion': 1,
    'readingStage': readingStage,
    'promptMode': 'associativeReading',
    'wordId': targetWordId,
    'contentRevision': targetContentRevision,
  });
}

enum TutorTimeMode { guided, direct }

enum TutorTimeScenario {
  jobInterview,
  airportCheckIn,
  cafeOrder,
  academicMeeting,
  hotelCheckIn,
}

/// Opaque episode/display IDs are minted by the actual scoped controller.
/// Learner/reply text and hashes of that text are never admitted here.
final class TutorTimeSource extends TimeSource {
  const TutorTimeSource({
    required this.episodeId,
    required this.mode,
    required this.scenario,
    required this.responseDisplayId,
    required this.model,
    required super.callerContext,
  });
  final String episodeId;
  final TutorTimeMode mode;
  final TutorTimeScenario scenario;
  final String responseDisplayId;
  final String? model;

  String get sourceBindingJson => jsonEncode({
    'schemaVersion': 1,
    'kind': 'tutor',
    'task': 'gemini-language-tutor-v1',
    'episodeId': episodeId,
    'mode': mode.name,
    'scenario': scenario.name,
  });

  String get contextBindingJson => jsonEncode({
    'schemaVersion': 1,
    'promptMode': 'tutorInteraction',
    'responseDisplayId': responseDisplayId,
    'model': model,
  });
}

/// A repository-admitted immutable context. Closed verification deliberately
/// receives a new owner/gate predicate instead of retaining the live route.
final class TimeSourceAdmission {
  TimeSourceAdmission({
    required this.ownerId,
    required this.sourceKind,
    required this.sourceBindingJson,
    required this.contextBindingJson,
    required this._verifyClosed,
    this.linkedSessionId,
    this.sessionLinkBindingJson,
  });

  final String ownerId;
  final TimeSourceKind sourceKind;
  final String sourceBindingJson;
  final String contextBindingJson;
  final String? linkedSessionId;
  final String? sessionLinkBindingJson;
  final Future<void> Function(bool Function()) _verifyClosed;

  Future<void> verifyClosed({required bool Function() ownerStillCurrent}) =>
      _verifyClosed(ownerStillCurrent);
}

final class LearningTimePreference {
  const LearningTimePreference({
    required this.ownerId,
    required this.enabled,
    required this.revision,
    required this.updatedAtUtcMs,
  });
  const LearningTimePreference.absent(this.ownerId)
    : enabled = false,
      revision = 0,
      updatedAtUtcMs = 0;
  final String ownerId;
  final bool enabled;
  final int revision;
  final int updatedAtUtcMs;

  bool sameAs(LearningTimePreference other) =>
      ownerId == other.ownerId &&
      enabled == other.enabled &&
      revision == other.revision &&
      updatedAtUtcMs == other.updatedAtUtcMs;
}

final class LearningTimeScope {
  const LearningTimeScope({
    required this.id,
    required this.ownerId,
    required this.sourceKind,
    required this.sourceBindingJson,
    required this.createdAtUtcMs,
    this.linkedSessionId,
    this.sessionLinkBindingJson,
  });
  final String id;
  final String ownerId;
  final TimeSourceKind sourceKind;
  final String sourceBindingJson;
  final int createdAtUtcMs;
  final String? linkedSessionId;
  final String? sessionLinkBindingJson;

  LearningTimeScope _withLink(TimeSessionLinkAdmission link) =>
      LearningTimeScope(
        id: id,
        ownerId: ownerId,
        sourceKind: sourceKind,
        sourceBindingJson: sourceBindingJson,
        createdAtUtcMs: createdAtUtcMs,
        linkedSessionId: link.linkedSessionId,
        sessionLinkBindingJson: link.sessionLinkBindingJson,
      );
}

final class TimeSessionLinkAdmission {
  TimeSessionLinkAdmission({
    required this.ownerId,
    required this.scopeId,
    required this.linkedSessionId,
    required this.sessionLinkBindingJson,
    required this._verifyClosed,
  });
  final String ownerId;
  final String scopeId;
  final String linkedSessionId;
  final String sessionLinkBindingJson;
  final Future<void> Function(bool Function()) _verifyClosed;
  Future<void> verifyClosed({required bool Function() ownerStillCurrent}) =>
      _verifyClosed(ownerStillCurrent);
}

final class LiveTimeLease {
  LiveTimeLease._({
    required this._scope,
    required this._admission,
    required this._issuer,
    required this._source,
    required this._ownerEpoch,
    required this._captureEpoch,
    required this._stillCurrent,
  });
  LearningTimeScope _scope;
  TimeSourceAdmission _admission;
  final LearningTimeUseCases _issuer;
  TimeSource _source;
  LearningTimeScope get scope => _scope;
  TimeSourceAdmission get admission => _admission;
  final int _ownerEpoch;
  final int _captureEpoch;
  final bool Function() _stillCurrent;
  bool _detached = false;
  bool _dependenciesRetired = false;
  bool _ready = false;
  bool _materialized = false;
  int _readyRevision = 0;
  int _nextOrdinal = 0;
  int? _anchorUs;
  int? _anchorUtcMs;
  int _confirmedUs = 0;
  int? _startedAtUtcMs;
  int? _endedAtUtcMs;
  TimeSessionLinkAdmission? _link;
  TimeSessionLinkAdmission? _preparedLink;
  String get scopeId => scope.id;
}

final class ClosedTimeSegmentIntent {
  ClosedTimeSegmentIntent._({
    required this._repository,
    required this.scope,
    required this.id,
    required this.ordinal,
    required this.eligibilityContextJson,
    required this.startedAtUtcMs,
    required this.endedAtUtcMs,
    required this.activeDurationUs,
    required this.preferenceRevision,
    required this.admission,
    required this.sessionLinkAdmission,
    required this._isCurrent,
  });
  final LearningTimeRepository _repository;
  final LearningTimeScope scope;
  final String id;
  final int ordinal;
  final String eligibilityContextJson;
  final int startedAtUtcMs;
  final int endedAtUtcMs;
  final int activeDurationUs;
  final int preferenceRevision;
  final TimeSourceAdmission admission;
  final TimeSessionLinkAdmission? sessionLinkAdmission;
  String get capturePolicyRevision => learningTimeCapturePolicyRevision;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
  bool belongsTo(LearningTimeRepository repository) =>
      identical(_repository, repository);
}

final class TimeSessionLinkIntent {
  TimeSessionLinkIntent._({
    required this._repository,
    required this.scope,
    required this.admission,
    required this.preferenceRevision,
    required this._isCurrent,
  });
  final LearningTimeRepository _repository;
  final LearningTimeScope scope;
  final TimeSessionLinkAdmission admission;
  final int preferenceRevision;
  String get linkedSessionId => admission.linkedSessionId;
  String get sessionLinkBindingJson => admission.sessionLinkBindingJson;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
  bool belongsTo(LearningTimeRepository repository) =>
      identical(_repository, repository);
}

final class LearningTimePreferenceIntent {
  LearningTimePreferenceIntent._({
    required this._repository,
    required this.ownerId,
    required this.expectedRevision,
    required this.enabled,
    required this.updatedAtUtcMs,
    required this._isCurrent,
  });
  final LearningTimeRepository _repository;
  final String ownerId;
  final int expectedRevision;
  final bool enabled;
  final int updatedAtUtcMs;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
  bool belongsTo(LearningTimeRepository repository) =>
      identical(_repository, repository);
}

sealed class TimeReadTarget {
  const TimeReadTarget();
}

final class OwnerTimeRead extends TimeReadTarget {
  const OwnerTimeRead({this.sourceKind});
  final TimeSourceKind? sourceKind;
}

final class ScopeTimeRead extends TimeReadTarget {
  const ScopeTimeRead(this.scopeId);
  final String scopeId;
}

final class SessionTimeRead extends TimeReadTarget {
  const SessionTimeRead(this.sessionId);
  final String sessionId;
}

final class ObservedEndRangeTimeRead extends TimeReadTarget {
  const ObservedEndRangeTimeRead({
    required this.startInclusiveUtc,
    required this.endExclusiveUtc,
  });
  final DateTime startInclusiveUtc;
  final DateTime endExclusiveUtc;
}

enum RecordedTimeStatus { recorded, noneRecorded, unsupported, unavailable }

final class RecordedTimeRead {
  const RecordedTimeRead.recorded({
    required int this.activeDurationUs,
    required int this.segmentCount,
  }) : status = RecordedTimeStatus.recorded;
  const RecordedTimeRead.noneRecorded()
    : status = RecordedTimeStatus.noneRecorded,
      activeDurationUs = 0,
      segmentCount = 0;
  const RecordedTimeRead.unsupported()
    : status = RecordedTimeStatus.unsupported,
      activeDurationUs = null,
      segmentCount = null;
  const RecordedTimeRead.unavailable()
    : status = RecordedTimeStatus.unavailable,
      activeDurationUs = null,
      segmentCount = null;
  final RecordedTimeStatus status;
  final int? activeDurationUs;
  final int? segmentCount;
}

enum LearningTimePendingState { none, segment, sessionLink, preference }

/// Strict masks are shared by normalization and persisted readback. Canonical
/// proof authority is separately checked by its original issuer.
const timeSourceBindingKeys = <TimeSourceKind, Set<String>>{
  TimeSourceKind.configuredQuiz: {
    'schemaVersion',
    'kind',
    'sessionId',
    'activityType',
    'acceptedPlanId',
  },
  TimeSourceKind.ownedSrs: {
    'schemaVersion',
    'kind',
    'sessionId',
    'selection',
    'deckPinsSha256',
  },
  TimeSourceKind.dictation: {
    'schemaVersion',
    'kind',
    'sessionId',
    'wordId',
    'wordContentRevision',
    'evidenceContentRevision',
  },
  TimeSourceKind.cloze: {
    'schemaVersion',
    'kind',
    'sessionId',
    'wordId',
    'wordContentRevision',
    'evidenceContentRevision',
  },
  TimeSourceKind.voicePractice: {
    'schemaVersion',
    'kind',
    'sessionId',
    'episodeId',
    'targetPinsSha256',
  },
  TimeSourceKind.reading: {
    'schemaVersion',
    'kind',
    'documentId',
    'documentRevision',
    'snapshotSha256',
    'targetPinsSha256',
  },
  TimeSourceKind.tutor: {
    'schemaVersion',
    'kind',
    'task',
    'episodeId',
    'mode',
    'scenario',
  },
};

const timeEligibilityContextKeys = <TimeSourceKind, Set<String>>{
  TimeSourceKind.configuredQuiz: {
    'schemaVersion',
    'questionOrdinal',
    'checkpointRevision',
    'wordId',
    'contentRevision',
    'promptMode',
    'phase',
    'evidenceContext',
  },
  TimeSourceKind.ownedSrs: {
    'schemaVersion',
    'cardIndex',
    'phase',
    'wordId',
    'contentRevision',
    'promptMode',
    'evidenceContext',
  },
  TimeSourceKind.dictation: {
    'schemaVersion',
    'wordId',
    'promptMode',
    'evidenceContext',
  },
  TimeSourceKind.cloze: {
    'schemaVersion',
    'wordId',
    'promptMode',
    'evidenceContext',
  },
  TimeSourceKind.voicePractice: {
    'schemaVersion',
    'wordIndex',
    'wordId',
    'contentRevision',
    'promptMode',
    'evidenceContext',
  },
  TimeSourceKind.reading: {
    'schemaVersion',
    'readingStage',
    'promptMode',
    'wordId',
    'contentRevision',
  },
  TimeSourceKind.tutor: {
    'schemaVersion',
    'promptMode',
    'responseDisplayId',
    'model',
  },
};

Map<String, Object?> parseTimeBindingJson(
  String value, {
  required TimeSourceKind sourceKind,
  required bool isContext,
}) {
  if (utf8.encode(value).length > learningTimeMaximumJsonBytes) {
    throw const FormatException('Learning-time binding is too large');
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic> || jsonEncode(decoded) != value) {
    throw const FormatException('Learning-time binding must be an object');
  }
  final expected = (isContext
      ? timeEligibilityContextKeys
      : timeSourceBindingKeys)[sourceKind]!;
  if (decoded.length != expected.length ||
      !decoded.keys.every(expected.contains) ||
      decoded['schemaVersion'] != 1 ||
      (!isContext && decoded['kind'] != sourceKind.name)) {
    throw const FormatException('Unsupported learning-time binding');
  }
  for (final entry in decoded.entries) {
    final item = entry.value;
    if (sourceKind == TimeSourceKind.tutor &&
        isContext &&
        entry.key == 'model' &&
        item == null) {
      continue;
    }
    if (sourceKind == TimeSourceKind.reading &&
        isContext &&
        (entry.key == 'wordId' || entry.key == 'contentRevision') &&
        item == null) {
      continue;
    }
    if (entry.key == 'evidenceContext') {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Missing learning-time evidence context');
      }
      final evidence = EvidenceContext.fromJson(
        Map<String, Object?>.from(item),
      );
      if (evidence.evidenceClass == EvidenceClass.assessment ||
          evidence.evidenceClass == EvidenceClass.recreational ||
          [
            evidence.protocolId,
            evidence.protocolVersion,
            evidence.experimentId,
            evidence.experimentVersion,
            evidence.assignmentId,
            evidence.cohort,
            evidence.researchConsentVersion,
            evidence.instrumentId,
            evidence.instrumentVersion,
            evidence.formId,
            evidence.formVersion,
            evidence.assessmentItemId,
            evidence.assessmentResponseCode,
            evidence.scoringRuleVersion,
          ].any((pin) => pin != null)) {
        throw const FormatException(
          'Ordinary time excludes Research/Assessment',
        );
      }
    } else if (const {
      'schemaVersion',
      'documentRevision',
      'readingStage',
      'questionOrdinal',
      'checkpointRevision',
      'cardIndex',
      'wordIndex',
    }.contains(entry.key)) {
      if (item is! int || item < 0 || item > 9007199254740991) {
        throw const FormatException('Invalid learning-time binding revision');
      }
    } else if (item is! String || item.trim().isEmpty || item.length > 512) {
      throw const FormatException('Invalid learning-time binding pin');
    }
    if (entry.key.endsWith('Sha256') &&
        (item is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(item))) {
      throw const FormatException('Learning-time pin needs a SHA-256');
    }
  }
  if (isContext) {
    final modes = switch (sourceKind) {
      TimeSourceKind.configuredQuiz => {'meaningChoice'},
      TimeSourceKind.ownedSrs => {'srsRecall'},
      TimeSourceKind.dictation => {'dictation'},
      TimeSourceKind.cloze => {'clozeTyped', 'clozeChoice'},
      TimeSourceKind.voicePractice => {'shadowing', 'pronunciationTranscript'},
      TimeSourceKind.reading => {'associativeReading'},
      TimeSourceKind.tutor => {'tutorInteraction'},
    };
    if (!modes.contains(decoded['promptMode']) ||
        (sourceKind == TimeSourceKind.configuredQuiz &&
            decoded['phase'] != 'awaitingAnswer')) {
      throw const FormatException('Unsupported learning-time prompt mode');
    }
  }
  if (sourceKind == TimeSourceKind.reading) {
    if (isContext &&
        (decoded['readingStage'] is! int ||
            (decoded['readingStage'] as int) < 1 ||
            (decoded['readingStage'] as int) > 6 ||
            decoded['promptMode'] != 'associativeReading')) {
      throw const FormatException('Unsupported Reading time stage');
    }
    if (isContext &&
        ((decoded['wordId'] == null) != (decoded['contentRevision'] == null) ||
            (decoded['wordId'] != null && decoded['readingStage'] != 3))) {
      throw const FormatException('Unsupported Reading target context');
    }
    if (!isContext &&
        (decoded['documentRevision'] is! int ||
            (decoded['documentRevision'] as int) < 1)) {
      throw const FormatException('Invalid Reading document revision');
    }
  }
  if (sourceKind == TimeSourceKind.ownedSrs &&
      isContext &&
      !{'front', 'revealed'}.contains(decoded['phase'])) {
    throw const FormatException('Unsupported SRS time phase');
  }
  if (sourceKind == TimeSourceKind.tutor) {
    if (!isContext &&
        (decoded['task'] != 'gemini-language-tutor-v1' ||
            !TutorTimeMode.values.any((v) => v.name == decoded['mode']) ||
            !TutorTimeScenario.values.any(
              (v) => v.name == decoded['scenario'],
            ))) {
      throw const FormatException('Unsupported Tutor time task');
    }
    if (isContext && decoded['promptMode'] != 'tutorInteraction') {
      throw const FormatException('Unsupported Tutor time context');
    }
    if (isContext) {
      final display = decoded['responseDisplayId'] as String;
      final task =
          display.startsWith('tutor-task:') &&
          display.substring('tutor-task:'.length).trim().isNotEmpty &&
          decoded['model'] == null;
      final reply =
          display.startsWith('tutor-reply:') &&
          display.substring('tutor-reply:'.length).trim().isNotEmpty &&
          decoded['model'] is String;
      if (!task && !reply) {
        throw const FormatException(
          'Tutor time needs an actual task or reply display',
        );
      }
    }
  }
  return Map<String, Object?>.unmodifiable(decoded);
}

Map<String, Object?> parseTimeSessionLinkBindingJson(String value) {
  if (utf8.encode(value).length > learningTimeMaximumJsonBytes) {
    throw const FormatException('Learning-time link is too large');
  }
  final decoded = jsonDecode(value);
  const keys = {
    'schemaVersion',
    'sessionId',
    'sourceBindingSha256',
    'canonicalSourceBindingSha256',
  };
  if (decoded is! Map<String, dynamic> ||
      jsonEncode(decoded) != value ||
      decoded.length != keys.length ||
      !decoded.keys.every(keys.contains) ||
      decoded['schemaVersion'] is! int ||
      decoded['schemaVersion'] != 1 ||
      decoded['sessionId'] is! String ||
      (decoded['sessionId'] as String).trim().isEmpty ||
      (decoded['sessionId'] as String).length > 512) {
    throw const FormatException('Unsupported learning-time session link');
  }
  for (final key in ['sourceBindingSha256', 'canonicalSourceBindingSha256']) {
    final pin = decoded[key];
    if (pin is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(pin)) {
      throw const FormatException('Learning-time link needs a SHA-256 pin');
    }
  }
  return Map<String, Object?>.unmodifiable(decoded);
}
