import 'dart:convert';
import '../../domain/learning_models.dart';
import '../../domain/learning_repository.dart';
import '../../domain/session_configuration.dart';
import '../../domain/lesson_mode.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_plan.dart';
import '../data/pair_matching_checkpoint_codec.dart';
import 'pair_matching_source_composer.dart';

/// No production call site. The owner of internal delivery supplies a live
/// gate and a pinned curator manifest; default capability is unavailable.
final class InternalPairMatchingCapability
    implements PairMatchingStartCapability {
  InternalPairMatchingCapability({
    required this.allowlist,
    bool Function()? isEnabled,
  }) : _isEnabled = isEnabled ?? _disabled;
  final PairCuratedAllowlist allowlist;
  final bool Function() _isEnabled;
  static bool _disabled() => false;
  @override
  void requireAllowed(PairMatchingPlanV1 plan) {
    if (!_isEnabled() ||
        plan.allowlistVersion != allowlist.version ||
        plan.orderedLexicalItems.any(
          (i) =>
              !allowlist.accepts(i) ||
              i.sourceReasons.contains(PairSourceReason.reported),
        )) {
      throw StateError('Pair delivery/content is unavailable');
    }
    final en = <String>{}, th = <String>{};
    for (final item in plan.orderedLexicalItems) {
      final a = pairVisibleKey(item.spelling, 'en'),
          b = pairVisibleKey(item.meaning, 'th');
      if (a == null || b == null || !en.add(a) || !th.add(b)) {
        throw StateError('Unsafe Pair visible labels');
      }
    }
  }
}

/// Durable operation envelope. Persist/recover these exact bytes for a retry;
/// the canonical checkpoint also carries them for post-commit reconciliation.
final class PairMatchingStartOperation {
  PairMatchingStartOperation({
    required this.plan,
    required this.launchOperationId,
    required this.appVersion,
    required this.buildId,
    this.configuration,
  }) {
    for (final text in [launchOperationId, appVersion, buildId]) {
      if (text.isEmpty || text != text.trim() || text.length > 256) {
        throw ArgumentError('Invalid Pair start identity');
      }
    }
    if (plan.learningSessionId !=
        pairSessionId(plan.ownerId, launchOperationId)) {
      throw ArgumentError('Pair operation/session mismatch');
    }
    final config = configuration;
    if (config != null &&
        (config.ownerId != plan.ownerId ||
            config.mode != LessonMode.matching ||
            config.itemCount != plan.orderedLexicalItems.length ||
            config.packIdentity != null ||
            config.direction !=
                (plan.direction == PairDirection.enToTh
                    ? SessionDirection.forward
                    : SessionDirection.reverse))) {
      throw ArgumentError('Pair configuration does not match exact plan');
    }
  }
  final PairMatchingPlanV1 plan;
  final String launchOperationId;
  final String appVersion;
  final String buildId;
  final SessionConfiguration? configuration;
  String get stableSerialization => jsonEncode({
    'schemaVersion': configuration == null ? 1 : 2,
    'plan': plan.toJson(),
    'launchOperationId': launchOperationId,
    'appVersion': appVersion,
    'buildId': buildId,
    if (configuration != null)
      'sessionConfiguration': configuration!.stableSerialization,
  });
  static PairMatchingStartOperation fromStableSerialization(String source) {
    if (source.length > 40000) {
      throw const FormatException('Pair operation too large');
    }
    try {
      final decoded = jsonDecode(source) as Map;
      final j = pairJson(decoded, {
        'schemaVersion',
        'plan',
        'launchOperationId',
        'appVersion',
        'buildId',
        if (decoded['schemaVersion'] == 2) 'sessionConfiguration',
      });
      if (j['schemaVersion'] != 1 && j['schemaVersion'] != 2) {
        throw const FormatException('Unknown Pair operation');
      }
      final o = PairMatchingStartOperation(
        plan: PairMatchingPlanV1.fromStableSerialization(jsonEncode(j['plan'])),
        launchOperationId: j['launchOperationId'] as String,
        appVersion: j['appVersion'] as String,
        buildId: j['buildId'] as String,
        configuration: j['schemaVersion'] == 2
            ? SessionConfiguration.fromStableSerialization(
                j['sessionConfiguration'] as String,
              )
            : null,
      );
      if (o.stableSerialization != source) {
        throw const FormatException('Noncanonical operation');
      }
      return o;
    } catch (_) {
      throw const FormatException('Invalid Pair operation');
    }
  }

  LearningSessionDraft get session => LearningSessionDraft(
    id: plan.learningSessionId,
    ownerId: plan.ownerId,
    activityType: 'matching',
    startedAtUtc: plan.createdAtUtc,
    appVersion: appVersion,
    buildId: buildId,
    sessionConfiguration: configuration,
  );
  LearningActivityCheckpoint get initialCheckpoint =>
      LearningActivityCheckpoint(
        sessionId: plan.learningSessionId,
        activityType: 'matching',
        revision: 1,
        occurredAtUtc: plan.createdAtUtc,
        state: PairMatchingCheckpointCodec.initialState(
          plan,
          stableSerialization,
        ),
      );
}

final class PairMatchingAtomicStartAdapter {
  const PairMatchingAtomicStartAdapter({
    required this.repository,
    required this.capability,
  });
  final PairPinnedLearningActivityRepository repository;
  final PairMatchingStartCapability capability;

  /// Establishes full elapsed coverage atomically only for a newly inserted
  /// session. An idempotent historical initial-only session remains unmeasured.
  Future<void> startMeasured(PairMatchingStartOperation operation) =>
      repository.startMeasuredPinnedPairSession(
        session: operation.session,
        plan: operation.plan,
        launchOperationId: operation.launchOperationId,
        checkpoint: operation.initialCheckpoint,
        capability: capability,
      );
  Future<void> start(PairMatchingStartOperation operation) =>
      repository.startPinnedPairSession(
        session: operation.session,
        plan: operation.plan,
        launchOperationId: operation.launchOperationId,
        checkpoint: operation.initialCheckpoint,
        capability: capability,
      );
}
