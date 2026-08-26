import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  const policy = SessionConfigurationPolicy();
  const packV3 = ContentIdentity(
    type: ContentType.learningPack,
    id: 'pack:academic-core',
    revision: 3,
  );
  const limits = SessionConfigurationProtocolLimits(
    schemaVersion: 1,
    protocolId: 'protocol:pilot-a',
    protocolVersion: '3.2.0',
    minimumItemCount: 3,
    maximumItemCount: 7,
    maximumHintBudget: 1,
    minimumTimedSeconds: 120,
    maximumTimedSeconds: 600,
    allowsUntimedAlternative: true,
    maximumUntimedActiveEffortSeconds: 900,
    pinnedPackIdentities: <ContentIdentity>[packV3],
  );

  group('SessionConfigurationPolicy', () {
    test('clamps numeric choices to adapter and persisted protocol bounds', () {
      final registration = _registration(const TypedRecallModeAdapter());
      final numericLimits = limits.copyWith(pinnedPackIdentities: const []);
      final defaults = policy.defaultsFor(
        registration: registration,
        limits: numericLimits,
      );

      final high = policy.validate(
        draft: defaults.copyWith(
          itemCount: 99,
          hintBudget: 2,
          timing: const SessionTiming.timed(Duration(seconds: 999)),
        ),
        registration: registration,
        limits: numericLimits,
        ownerId: 'owner:a',
        availablePackIdentities: const <ContentIdentity>[],
      );
      final low = policy.validate(
        draft: defaults.copyWith(
          itemCount: 0,
          timing: const SessionTiming.timed(Duration(seconds: 1)),
        ),
        registration: registration,
        limits: numericLimits,
        ownerId: 'owner:a',
        availablePackIdentities: const <ContentIdentity>[],
      );

      expect(high.itemCount, 7);
      expect(high.hintBudget, 1);
      expect(high.timing.timedLimit, const Duration(seconds: 600));
      expect(low.itemCount, 3);
      expect(low.timing.timedLimit, const Duration(seconds: 120));
    });

    test('fails closed when an option is unsupported by the exact adapter', () {
      final registration = _registration(const DictationModeAdapter());
      final oneItemLimits = limits.copyWith(
        minimumItemCount: 1,
        maximumItemCount: 1,
      );
      final defaults = policy.defaultsFor(
        registration: registration,
        limits: oneItemLimits,
      );

      expect(
        () => policy.validate(
          draft: defaults.copyWith(
            direction: SessionDirection.reverse,
            packIdentity: packV3,
          ),
          registration: registration,
          limits: oneItemLimits,
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV3],
        ),
        throwsA(
          isA<SessionConfigurationResetRequired>().having(
            (error) => error.reason,
            'reason',
            SessionConfigurationResetReason.unsupportedOption,
          ),
        ),
      );
    });

    test('a pinned protocol cannot be bypassed by omitting its pack', () {
      final registration = _registration(const MeaningQuizModeAdapter());

      expect(
        () => policy.validate(
          draft: policy.defaultsFor(registration: registration, limits: limits),
          registration: registration,
          limits: limits,
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV3],
        ),
        _resetReason(SessionConfigurationResetReason.packDrift),
      );
    });

    test('untimed accessibility remains bounded active effort', () {
      final registration = _registration(const MeaningQuizModeAdapter());
      final defaults = policy.defaultsFor(
        registration: registration,
        limits: limits,
      );

      final configuration = policy.validate(
        draft: defaults.copyWith(
          timing: const SessionTiming.untimedAlternative(
            maximumActiveEffort: Duration(hours: 8),
          ),
          packIdentity: packV3,
        ),
        registration: registration,
        limits: limits,
        ownerId: 'owner:a',
        availablePackIdentities: const <ContentIdentity>[packV3],
      );

      expect(configuration.timing.isUntimedAlternative, isTrue);
      expect(
        configuration.timing.maximumActiveEffort,
        const Duration(seconds: 900),
      );
      expect(configuration.timing.maximumActiveEffort, isNot(Duration.zero));
    });

    test(
      'stable serialization round-trips with deterministic content identity',
      () {
        final registration = _registration(const MeaningQuizModeAdapter());
        final configuration = policy.validate(
          draft: policy
              .defaultsFor(registration: registration, limits: limits)
              .copyWith(packIdentity: packV3),
          registration: registration,
          limits: limits,
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV3],
        );

        final encoded = configuration.stableSerialization;
        final decoded = SessionConfiguration.fromStableSerialization(encoded);

        expect(decoded, configuration);
        expect(decoded.stableSerialization, encoded);
        expect(decoded.contentIdentity, configuration.contentIdentity);
        expect(configuration.contentIdentity, startsWith('sha256:'));
      },
    );

    test(
      'unknown and tampered serialized configurations fail with reset prompt',
      () {
        final registration = _registration(const MeaningQuizModeAdapter());
        final configuration = policy.validate(
          draft: policy
              .defaultsFor(registration: registration, limits: limits)
              .copyWith(packIdentity: packV3),
          registration: registration,
          limits: limits,
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV3],
        );

        expect(
          () => SessionConfiguration.fromStableSerialization(
            configuration.stableSerialization.replaceFirst(
              '"schemaVersion":1',
              '"schemaVersion":99',
            ),
          ),
          throwsA(
            isA<SessionConfigurationResetRequired>().having(
              (error) => error.reason,
              'reason',
              SessionConfigurationResetReason.unknownVersion,
            ),
          ),
        );
        expect(
          () => SessionConfiguration.fromStableSerialization(
            configuration.stableSerialization.replaceFirst(
              '"itemCount":7',
              '"itemCount":6',
            ),
          ),
          throwsA(
            isA<SessionConfigurationResetRequired>().having(
              (error) => error.reason,
              'reason',
              SessionConfigurationResetReason.tampered,
            ),
          ),
        );
      },
    );

    test('revalidation fails closed on protocol, owner, or pack drift', () {
      final registration = _registration(const MeaningQuizModeAdapter());
      final configuration = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(packIdentity: packV3),
        registration: registration,
        limits: limits,
        ownerId: 'owner:a',
        availablePackIdentities: const <ContentIdentity>[packV3],
      );
      const packV4 = ContentIdentity(
        type: ContentType.learningPack,
        id: 'pack:academic-core',
        revision: 4,
      );

      expect(
        () => policy.revalidate(
          configuration: configuration,
          registration: registration,
          limits: limits.copyWith(protocolVersion: '3.2.1'),
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV3],
        ),
        _resetReason(SessionConfigurationResetReason.staleProtocol),
      );
      expect(
        () => policy.revalidate(
          configuration: configuration,
          registration: registration,
          limits: limits,
          ownerId: 'owner:b',
          availablePackIdentities: const <ContentIdentity>[packV3],
        ),
        _resetReason(SessionConfigurationResetReason.ownerDrift),
      );
      expect(
        () => policy.revalidate(
          configuration: configuration,
          registration: registration,
          limits: limits,
          ownerId: 'owner:a',
          availablePackIdentities: const <ContentIdentity>[packV4],
        ),
        _resetReason(SessionConfigurationResetReason.packDrift),
      );
    });

    test('implemented-off modes cannot be configured', () {
      final registration = _registration(
        const MeaningQuizModeAdapter(),
        deliveryState: LessonModeDeliveryState.implementedOff,
      );

      expect(
        () => policy.defaultsFor(registration: registration, limits: limits),
        _resetReason(SessionConfigurationResetReason.modeUnavailable),
      );
    });

    test('capabilities come from the exact adapter contract', () {
      final registration = _registration(_UnconfiguredAdapter());

      expect(
        () => policy.defaultsFor(registration: registration, limits: limits),
        _resetReason(SessionConfigurationResetReason.unsupportedOption),
      );
    });

    test('defaults use the exact untimed-only adapter timing capability', () {
      final registration = _registration(const _UntimedOnlyAdapter());
      final defaults = policy.defaultsFor(
        registration: registration,
        limits: limits.copyWith(pinnedPackIdentities: const []),
      );

      expect(defaults.timing.kind, SessionTimingKind.untimedAlternative);
      expect(defaults.timing.maximumActiveEffort, const Duration(seconds: 900));
    });

    test(
      'persisted assignment resolves exact protocol clamps and identity',
      () {
        final catalog = SessionConfigurationProtocolCatalog(
          baseline: const SessionConfigurationProtocolLimits.standard(),
          bindings: <SessionConfigurationProtocolBinding>[
            SessionConfigurationProtocolBinding(
              experimentId: 'experiment:f16',
              experimentVersion: 3,
              cohort: 'accessible-timing',
              protocolVersion: '5',
              consentVersion: 4,
              limits: limits.copyWith(
                protocolId: 'protocol:experiment-f16',
                protocolVersion: '5',
                maximumItemCount: 4,
              ),
            ),
          ],
        );
        final snapshot = CurrentActivityResearchSnapshot(
          engagementAllowed: true,
          consentContext: const ConsentContext(
            researchConsentVersion: 4,
            aiConsentGranted: false,
            voiceConsentGranted: false,
            socialConsentGranted: false,
          ),
          experimentContext: ExperimentContext(
            experimentId: 'experiment:f16',
            variantId: 'accessible-timing',
            assignedAtUtc: DateTime.utc(2026, 8, 26),
          ),
          protocolId: 'protocol:experiment-f16',
          protocolVersion: '5',
          experimentVersion: 3,
          assignmentId: 'assignment:f16',
        );

        final resolved = catalog.resolveCurrentResearch(snapshot);

        expect(resolved.maximumItemCount, 4);
        expect(resolved.protocolVersion, '5');
        expect(resolved.authorityIdentity, contains('assignment:f16'));
        expect(resolved.contentIdentity, isNot(limits.contentIdentity));
      },
    );

    test(
      'stale persisted assignment fails closed instead of using baseline',
      () {
        final catalog = SessionConfigurationProtocolCatalog(
          baseline: const SessionConfigurationProtocolLimits.standard(),
          bindings: <SessionConfigurationProtocolBinding>[
            SessionConfigurationProtocolBinding(
              experimentId: 'experiment:f16',
              experimentVersion: 3,
              cohort: 'control',
              protocolVersion: '5',
              consentVersion: 4,
              limits: limits.copyWith(
                protocolId: 'protocol:experiment-f16',
                protocolVersion: '5',
              ),
            ),
          ],
        );

        expect(
          () => catalog.resolveCurrentResearch(
            CurrentActivityResearchSnapshot(
              engagementAllowed: true,
              consentContext: const ConsentContext(
                researchConsentVersion: 4,
                aiConsentGranted: false,
                voiceConsentGranted: false,
                socialConsentGranted: false,
              ),
              experimentContext: ExperimentContext(
                experimentId: 'experiment:f16',
                variantId: 'control',
                assignedAtUtc: DateTime.utc(2026, 8, 26),
              ),
              protocolId: 'protocol:experiment-f16',
              protocolVersion: '4',
              experimentVersion: 2,
              assignmentId: 'assignment:f16',
            ),
          ),
          _resetReason(SessionConfigurationResetReason.staleProtocol),
        );
      },
    );
  });
}

final class _UnconfiguredAdapter implements LessonModeAdapter {
  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      const LessonItem(id: 'unconfigured');
}

final class _UntimedOnlyAdapter
    implements SessionConfigurableLessonModeAdapter {
  const _UntimedOnlyAdapter();

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 1,
        maximumItemCount: 10,
        defaultItemCount: 5,
        directions: <SessionDirection>{SessionDirection.forward},
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 0,
        supportsTimed: false,
        supportsUntimedAlternative: true,
        supportsPackSelection: false,
      );

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      const LessonItem(id: 'untimed-only');
}

LessonModeRegistration _registration(
  dynamic adapter, {
  LessonModeDeliveryState deliveryState = LessonModeDeliveryState.enabled,
}) => LessonModeRegistration(
  adapter: adapter,
  feature: Feature.quiz,
  productionEntryId: 'home/learn/quiz',
  routeName: 'learning/test',
  deliveryState: deliveryState,
);

Matcher _resetReason(SessionConfigurationResetReason reason) => throwsA(
  isA<SessionConfigurationResetRequired>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);
