import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import 'lesson_mode.dart';

const int sessionConfigurationSchemaVersion = 1;
const String sessionConfigurationPolicyVersion =
    'session-configuration-policy-v1';

enum SessionDirection { forward, reverse, mixed }

enum SessionDifficulty { supported, standard, challenge }

enum SessionTimingKind { timed, untimedAlternative }

enum SessionConfigurationResetReason {
  unknownVersion,
  unsupportedOption,
  invalidProtocol,
  staleProtocol,
  ownerDrift,
  packDrift,
  modeDrift,
  modeUnavailable,
  tampered,
}

final class SessionConfigurationResetRequired implements Exception {
  const SessionConfigurationResetRequired(this.reason, [this.detail]);

  final SessionConfigurationResetReason reason;
  final String? detail;

  String get promptTitle => 'Reset session configuration';

  String get promptMessage => switch (reason) {
    SessionConfigurationResetReason.unknownVersion =>
      'This session configuration uses an unsupported version.',
    SessionConfigurationResetReason.unsupportedOption =>
      'One or more options are unavailable for this lesson mode.',
    SessionConfigurationResetReason.invalidProtocol =>
      'The saved study protocol limits are unavailable.',
    SessionConfigurationResetReason.staleProtocol =>
      'The study protocol changed after this session was configured.',
    SessionConfigurationResetReason.ownerDrift =>
      'The active learner changed after this session was configured.',
    SessionConfigurationResetReason.packDrift =>
      'The selected learning-pack revision is no longer available.',
    SessionConfigurationResetReason.modeDrift =>
      'The lesson mode changed after this session was configured.',
    SessionConfigurationResetReason.modeUnavailable =>
      'This lesson mode is no longer available.',
    SessionConfigurationResetReason.tampered =>
      'The saved session configuration could not be verified.',
  };

  @override
  String toString() =>
      'SessionConfigurationResetRequired(${reason.name}${detail == null ? '' : ': $detail'})';
}

final class SessionConfigurationLimitReached implements Exception {
  const SessionConfigurationLimitReached();

  @override
  String toString() => 'SessionConfigurationLimitReached';
}

final class SessionTiming {
  const SessionTiming.timed(Duration limit)
    : kind = SessionTimingKind.timed,
      timedLimit = limit,
      maximumActiveEffort = null;

  const SessionTiming.untimedAlternative({required this.maximumActiveEffort})
    : kind = SessionTimingKind.untimedAlternative,
      timedLimit = null;

  final SessionTimingKind kind;
  final Duration? timedLimit;
  final Duration? maximumActiveEffort;

  bool get isUntimedAlternative => kind == SessionTimingKind.untimedAlternative;

  Map<String, Object?> toJson() => switch (kind) {
    SessionTimingKind.timed => <String, Object?>{
      'kind': kind.name,
      'seconds': timedLimit!.inSeconds,
    },
    SessionTimingKind.untimedAlternative => <String, Object?>{
      'kind': kind.name,
      'maximumActiveEffortSeconds': maximumActiveEffort!.inSeconds,
    },
  };

  static SessionTiming fromJson(Object? value) {
    if (value is! Map) throw _reset(SessionConfigurationResetReason.tampered);
    final json = value.cast<Object?, Object?>();
    final kind = json['kind'];
    if (kind == SessionTimingKind.timed.name) {
      _requireExactKeys(json, const <String>{'kind', 'seconds'});
      final seconds = json['seconds'];
      if (seconds is! int || seconds <= 0) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      return SessionTiming.timed(Duration(seconds: seconds));
    }
    if (kind == SessionTimingKind.untimedAlternative.name) {
      _requireExactKeys(json, const <String>{
        'kind',
        'maximumActiveEffortSeconds',
      });
      final seconds = json['maximumActiveEffortSeconds'];
      if (seconds is! int || seconds <= 0) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      return SessionTiming.untimedAlternative(
        maximumActiveEffort: Duration(seconds: seconds),
      );
    }
    throw _reset(SessionConfigurationResetReason.unsupportedOption);
  }

  @override
  bool operator ==(Object other) =>
      other is SessionTiming &&
      other.kind == kind &&
      other.timedLimit == timedLimit &&
      other.maximumActiveEffort == maximumActiveEffort;

  @override
  int get hashCode => Object.hash(kind, timedLimit, maximumActiveEffort);
}

final class SessionConfigurationDraft {
  const SessionConfigurationDraft({
    required this.itemCount,
    required this.direction,
    required this.difficulty,
    required this.hintBudget,
    required this.timing,
    this.packIdentity,
  });

  final int itemCount;
  final SessionDirection direction;
  final SessionDifficulty difficulty;
  final int hintBudget;
  final SessionTiming timing;
  final ContentIdentity? packIdentity;

  SessionConfigurationDraft copyWith({
    int? itemCount,
    SessionDirection? direction,
    SessionDifficulty? difficulty,
    int? hintBudget,
    SessionTiming? timing,
    ContentIdentity? packIdentity,
    bool clearPackIdentity = false,
  }) => SessionConfigurationDraft(
    itemCount: itemCount ?? this.itemCount,
    direction: direction ?? this.direction,
    difficulty: difficulty ?? this.difficulty,
    hintBudget: hintBudget ?? this.hintBudget,
    timing: timing ?? this.timing,
    packIdentity: clearPackIdentity ? null : packIdentity ?? this.packIdentity,
  );
}

/// Immutable snapshot of protocol-owned limits loaded from persisted policy.
/// f16 consumes this value but never edits assignment/cohort state.
final class SessionConfigurationProtocolLimits {
  const SessionConfigurationProtocolLimits({
    required this.schemaVersion,
    required this.protocolId,
    required this.protocolVersion,
    required this.minimumItemCount,
    required this.maximumItemCount,
    required this.maximumHintBudget,
    required this.minimumTimedSeconds,
    required this.maximumTimedSeconds,
    required this.allowsUntimedAlternative,
    required this.maximumUntimedActiveEffortSeconds,
    this.pinnedPackIdentities = const <ContentIdentity>[],
    this.authorityIdentity = 'authority:baseline-unspecified',
  });

  const SessionConfigurationProtocolLimits.standard()
    : schemaVersion = 1,
      protocolId = 'protocol:local-standard',
      protocolVersion = '1',
      minimumItemCount = 1,
      maximumItemCount = 20,
      maximumHintBudget = 2,
      minimumTimedSeconds = 60,
      maximumTimedSeconds = 1800,
      allowsUntimedAlternative = true,
      maximumUntimedActiveEffortSeconds = 1800,
      pinnedPackIdentities = const <ContentIdentity>[],
      authorityIdentity = 'authority:baseline-local-standard';

  final int schemaVersion;
  final String protocolId;
  final String protocolVersion;
  final int minimumItemCount;
  final int maximumItemCount;
  final int maximumHintBudget;
  final int minimumTimedSeconds;
  final int maximumTimedSeconds;
  final bool allowsUntimedAlternative;
  final int maximumUntimedActiveEffortSeconds;
  final List<ContentIdentity> pinnedPackIdentities;
  final String authorityIdentity;

  String get contentIdentity =>
      'sha256:${sha256.convert(utf8.encode(_stableJson))}';

  String get _stableJson => jsonEncode(<String, Object?>{
    'schemaVersion': schemaVersion,
    'protocolId': protocolId,
    'protocolVersion': protocolVersion,
    'minimumItemCount': minimumItemCount,
    'maximumItemCount': maximumItemCount,
    'maximumHintBudget': maximumHintBudget,
    'minimumTimedSeconds': minimumTimedSeconds,
    'maximumTimedSeconds': maximumTimedSeconds,
    'allowsUntimedAlternative': allowsUntimedAlternative,
    'maximumUntimedActiveEffortSeconds': maximumUntimedActiveEffortSeconds,
    'pinnedPackIdentities': pinnedPackIdentities.map(_contentJson).toList(),
    'authorityIdentity': authorityIdentity,
  });

  SessionConfigurationProtocolLimits copyWith({
    int? schemaVersion,
    String? protocolId,
    String? protocolVersion,
    int? minimumItemCount,
    int? maximumItemCount,
    int? maximumHintBudget,
    int? minimumTimedSeconds,
    int? maximumTimedSeconds,
    bool? allowsUntimedAlternative,
    int? maximumUntimedActiveEffortSeconds,
    List<ContentIdentity>? pinnedPackIdentities,
    String? authorityIdentity,
  }) => SessionConfigurationProtocolLimits(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    protocolId: protocolId ?? this.protocolId,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    minimumItemCount: minimumItemCount ?? this.minimumItemCount,
    maximumItemCount: maximumItemCount ?? this.maximumItemCount,
    maximumHintBudget: maximumHintBudget ?? this.maximumHintBudget,
    minimumTimedSeconds: minimumTimedSeconds ?? this.minimumTimedSeconds,
    maximumTimedSeconds: maximumTimedSeconds ?? this.maximumTimedSeconds,
    allowsUntimedAlternative:
        allowsUntimedAlternative ?? this.allowsUntimedAlternative,
    maximumUntimedActiveEffortSeconds:
        maximumUntimedActiveEffortSeconds ??
        this.maximumUntimedActiveEffortSeconds,
    pinnedPackIdentities: pinnedPackIdentities ?? this.pinnedPackIdentities,
    authorityIdentity: authorityIdentity ?? this.authorityIdentity,
  );
}

/// Exact configuration surface declared by one concrete lesson adapter.
/// The policy never guesses capabilities from a mode enum.
final class SessionConfigurationCapabilities {
  const SessionConfigurationCapabilities({
    required this.minimumItemCount,
    required this.maximumItemCount,
    required this.defaultItemCount,
    required this.directions,
    required this.difficulties,
    required this.maximumHintBudget,
    required this.supportsTimed,
    required this.supportsUntimedAlternative,
    required this.supportsPackSelection,
  });

  final int minimumItemCount;
  final int maximumItemCount;
  final int defaultItemCount;
  final Set<SessionDirection> directions;
  final Set<SessionDifficulty> difficulties;
  final int maximumHintBudget;
  final bool supportsTimed;
  final bool supportsUntimedAlternative;
  final bool supportsPackSelection;
}

abstract interface class SessionConfigurableLessonModeAdapter
    implements LessonModeAdapter {
  SessionConfigurationCapabilities get sessionConfigurationCapabilities;
}

abstract interface class SessionConfigurationStore {
  Future<SessionConfiguration?> read({
    required String ownerId,
    required LessonMode mode,
  });

  Future<void> save(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  });

  Future<void> clear({required String ownerId, required LessonMode mode});
}

final class SessionConfiguration {
  SessionConfiguration.validated({
    required this.schemaVersion,
    required this.policyVersion,
    required this.ownerId,
    required this.mode,
    required this.itemCount,
    required this.direction,
    required this.difficulty,
    required this.hintBudget,
    required this.timing,
    required this.packIdentity,
    required this.protocolId,
    required this.protocolVersion,
    required this.protocolLimitsIdentity,
  }) : contentIdentity = _identityFor(
         _payload(
           schemaVersion: schemaVersion,
           policyVersion: policyVersion,
           ownerId: ownerId,
           mode: mode,
           itemCount: itemCount,
           direction: direction,
           difficulty: difficulty,
           hintBudget: hintBudget,
           timing: timing,
           packIdentity: packIdentity,
           protocolId: protocolId,
           protocolVersion: protocolVersion,
           protocolLimitsIdentity: protocolLimitsIdentity,
         ),
       );

  SessionConfiguration._decoded({
    required this.schemaVersion,
    required this.policyVersion,
    required this.ownerId,
    required this.mode,
    required this.itemCount,
    required this.direction,
    required this.difficulty,
    required this.hintBudget,
    required this.timing,
    required this.packIdentity,
    required this.protocolId,
    required this.protocolVersion,
    required this.protocolLimitsIdentity,
    required this.contentIdentity,
  });

  final int schemaVersion;
  final String policyVersion;
  final String ownerId;
  final LessonMode mode;
  final int itemCount;
  final SessionDirection direction;
  final SessionDifficulty difficulty;
  final int hintBudget;
  final SessionTiming timing;
  final ContentIdentity? packIdentity;
  final String protocolId;
  final String protocolVersion;
  final String protocolLimitsIdentity;
  final String contentIdentity;

  SessionConfigurationDraft get draft => SessionConfigurationDraft(
    itemCount: itemCount,
    direction: direction,
    difficulty: difficulty,
    hintBudget: hintBudget,
    timing: timing,
    packIdentity: packIdentity,
  );

  Map<String, Object?> get _configurationPayload => _payload(
    schemaVersion: schemaVersion,
    policyVersion: policyVersion,
    ownerId: ownerId,
    mode: mode,
    itemCount: itemCount,
    direction: direction,
    difficulty: difficulty,
    hintBudget: hintBudget,
    timing: timing,
    packIdentity: packIdentity,
    protocolId: protocolId,
    protocolVersion: protocolVersion,
    protocolLimitsIdentity: protocolLimitsIdentity,
  );

  String get stableSerialization => jsonEncode(<String, Object?>{
    'schemaVersion': sessionConfigurationSchemaVersion,
    'contentIdentity': contentIdentity,
    'configuration': _configurationPayload,
  });

  static SessionConfiguration fromStableSerialization(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      final envelope = decoded.cast<Object?, Object?>();
      _requireExactKeys(envelope, const <String>{
        'schemaVersion',
        'contentIdentity',
        'configuration',
      });
      final envelopeVersion = envelope['schemaVersion'];
      if (envelopeVersion != sessionConfigurationSchemaVersion) {
        throw _reset(SessionConfigurationResetReason.unknownVersion);
      }
      final identity = envelope['contentIdentity'];
      final rawConfiguration = envelope['configuration'];
      if (identity is! String || rawConfiguration is! Map) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      final json = rawConfiguration.cast<Object?, Object?>();
      _requireExactKeys(json, const <String>{
        'schemaVersion',
        'policyVersion',
        'ownerId',
        'mode',
        'itemCount',
        'direction',
        'difficulty',
        'hintBudget',
        'timing',
        'packIdentity',
        'protocolId',
        'protocolVersion',
        'protocolLimitsIdentity',
      });
      final schemaVersion = json['schemaVersion'];
      if (schemaVersion != sessionConfigurationSchemaVersion) {
        throw _reset(SessionConfigurationResetReason.unknownVersion);
      }
      final policyVersion = _string(json['policyVersion']);
      if (policyVersion != sessionConfigurationPolicyVersion) {
        throw _reset(SessionConfigurationResetReason.unknownVersion);
      }
      final mode = _enumByName(LessonMode.values, json['mode']);
      final direction = _enumByName(SessionDirection.values, json['direction']);
      final difficulty = _enumByName(
        SessionDifficulty.values,
        json['difficulty'],
      );
      final itemCount = json['itemCount'];
      final hintBudget = json['hintBudget'];
      if (itemCount is! int || hintBudget is! int) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      final packIdentity = _contentFromJson(json['packIdentity']);
      final configuration = SessionConfiguration._decoded(
        schemaVersion: schemaVersion as int,
        policyVersion: policyVersion,
        ownerId: _string(json['ownerId']),
        mode: mode,
        itemCount: itemCount,
        direction: direction,
        difficulty: difficulty,
        hintBudget: hintBudget,
        timing: SessionTiming.fromJson(json['timing']),
        packIdentity: packIdentity,
        protocolId: _string(json['protocolId']),
        protocolVersion: _string(json['protocolVersion']),
        protocolLimitsIdentity: _string(json['protocolLimitsIdentity']),
        contentIdentity: identity,
      );
      if (configuration.contentIdentity !=
              _identityFor(configuration._configurationPayload) ||
          configuration.stableSerialization != source) {
        throw _reset(SessionConfigurationResetReason.tampered);
      }
      return configuration;
    } on SessionConfigurationResetRequired {
      rethrow;
    } catch (_) {
      throw _reset(SessionConfigurationResetReason.tampered);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SessionConfiguration &&
      other.contentIdentity == contentIdentity &&
      other.stableSerialization == stableSerialization;

  @override
  int get hashCode => contentIdentity.hashCode;
}

Map<String, Object?> _payload({
  required int schemaVersion,
  required String policyVersion,
  required String ownerId,
  required LessonMode mode,
  required int itemCount,
  required SessionDirection direction,
  required SessionDifficulty difficulty,
  required int hintBudget,
  required SessionTiming timing,
  required ContentIdentity? packIdentity,
  required String protocolId,
  required String protocolVersion,
  required String protocolLimitsIdentity,
}) => <String, Object?>{
  'schemaVersion': schemaVersion,
  'policyVersion': policyVersion,
  'ownerId': ownerId,
  'mode': mode.name,
  'itemCount': itemCount,
  'direction': direction.name,
  'difficulty': difficulty.name,
  'hintBudget': hintBudget,
  'timing': timing.toJson(),
  'packIdentity': packIdentity == null ? null : _contentJson(packIdentity),
  'protocolId': protocolId,
  'protocolVersion': protocolVersion,
  'protocolLimitsIdentity': protocolLimitsIdentity,
};

String _identityFor(Map<String, Object?> payload) =>
    'sha256:${sha256.convert(utf8.encode(jsonEncode(payload)))}';

Map<String, Object?> _contentJson(ContentIdentity identity) =>
    <String, Object?>{
      'type': identity.type.name,
      'id': identity.id,
      'revision': identity.revision,
    };

ContentIdentity? _contentFromJson(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw _reset(SessionConfigurationResetReason.tampered);
  final json = value.cast<Object?, Object?>();
  _requireExactKeys(json, const <String>{'type', 'id', 'revision'});
  final type = _enumByName(ContentType.values, json['type']);
  final revision = json['revision'];
  if (revision is! int) throw _reset(SessionConfigurationResetReason.tampered);
  return ContentIdentity(
    type: type,
    id: _string(json['id']),
    revision: revision,
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) throw _reset(SessionConfigurationResetReason.tampered);
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw _reset(SessionConfigurationResetReason.unsupportedOption);
}

String _string(Object? value) {
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw _reset(SessionConfigurationResetReason.tampered);
  }
  return value;
}

void _requireExactKeys(Map<Object?, Object?> json, Set<String> expected) {
  final actual = json.keys.whereType<String>().toSet();
  if (actual.length != json.length ||
      actual.length != expected.length ||
      !actual.containsAll(expected)) {
    throw _reset(SessionConfigurationResetReason.tampered);
  }
}

SessionConfigurationResetRequired _reset(
  SessionConfigurationResetReason reason,
) => SessionConfigurationResetRequired(reason);
