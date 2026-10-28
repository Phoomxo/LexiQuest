import 'package:flutter/material.dart';

import '../features/learning/domain/learning_repository.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import '../features/learning/pair_matching/application/pair_matching_source_composer.dart';
import '../features/learning/pair_matching/domain/pair_matching_launch.dart';
import '../features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import '../features/learning/pair_matching/domain/pair_matching_plan.dart';
import '../features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import '../features/review/application/pair_review_deferral.dart';
import '../features/vocabulary/data/packaged_starter_catalog.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';

/// Learn entry uses the shipped, reviewed starter pins. The canonical start
/// transaction rechecks their durable content and the active owner.
final class PairMatchingLearnScreen extends StatefulWidget {
  const PairMatchingLearnScreen({super.key, required this.dependencies})
    : replaySource = null,
      replayOperationId = null,
      expectedOwnerId = null;
  const PairMatchingLearnScreen.practiceReplay({
    super.key,
    required this.dependencies,
    required PairMatchingHistoryProjection source,
    required String replayOperationId,
    required String expectedOwnerId,
  }) : replaySource = source,
       replayOperationId = replayOperationId,
       expectedOwnerId = expectedOwnerId;
  final AppDependencies dependencies;
  final PairMatchingHistoryProjection? replaySource;
  final String? replayOperationId;
  final String? expectedOwnerId;

  @override
  State<PairMatchingLearnScreen> createState() =>
      _PairMatchingLearnScreenState();
}

final class _PairMatchingLearnScreenState
    extends State<PairMatchingLearnScreen> {
  final _clock = Stopwatch()..start();
  late final Future<Widget> _content = _prepare();

  Future<Widget> _prepare() async {
    final d = widget.dependencies;
    final database = d.database!;
    final learning = d.learning!;
    final owner = await d.activeOwnerIdentities!.requireSingleActiveOwnerId();
    if (widget.expectedOwnerId != null && widget.expectedOwnerId != owner) {
      throw StateError('Pair replay owner changed');
    }
    final allowlist = PairCuratedAllowlist(
      version: 'packaged-starter-r1',
      items: [
        for (final word in PackagedStarterCatalog.words)
          PairLexicalItem(
            wordId: word.id,
            contentRevision: 1,
            checksum: word.coreHash,
            spelling: word.key,
            meaning: word.meaning,
            sourceLocale: 'en',
            targetLocale: 'th',
            sourceReasons: const {PairSourceReason.newContent},
          ),
      ],
    );
    final runtime = PairMatchingExperienceRuntime(
      database: database,
      learning: learning,
      currentActivityEvidence: d.currentActivityEvidence!,
      registry: d.lessonModes!,
      createController: d.createLessonController!,
      composer: PairMatchingSourceComposer(allowlist: allowlist),
      start: PairMatchingAtomicStartAdapter(
        repository: learning.repository as PairPinnedLearningActivityRepository,
        capability: InternalPairMatchingCapability(
          allowlist: allowlist,
          isEnabled: () => d.features.isEnabled(Feature.quiz),
        ),
      ),
      protocols: d.sessionConfigurationProtocols,
      configurations:
          d.sessionConfigurations as ActiveOwnerSessionConfigurationStore,
      reviewDeferral: PairReviewDeferral(database),
      voice: d.voice,
      features: d.features,
      monotonicMicros: () => _clock.elapsedMicroseconds,
      canStart: () => d.features.isEnabled(Feature.quiz),
    );
    if (await runtime.requireOwner() != owner) {
      throw StateError('Pair owner changed');
    }
    void exit() {
      if (mounted) Navigator.of(context).pop();
    }

    final replaySource = widget.replaySource;
    if (replaySource != null) {
      // The host rereads the authenticated source. History is never an
      // authority for lexical pins or reward eligibility.
      return PairMatchingExperienceHost.practiceReplay(
        runtime: runtime,
        source: replaySource,
        launchOperationId: widget.replayOperationId!,
        onExit: exit,
      );
    }
    final recovery = await learning.loadActivityRecovery(
      activityType: 'matching',
      ownerId: owner,
    );
    if (await runtime.requireOwner() != owner) {
      throw StateError('Pair owner changed');
    }

    if (recovery != null) {
      final purpose = await runtime.reader.read(
        ownerId: owner,
        sessionId: recovery.session.id,
      );
      final snapshot = purpose.snapshot;
      if (snapshot == null) {
        throw StateError('Legacy matching requires its original route');
      }
      if (recovery.session.state != 'completed' ||
          recovery.checkpoint?.terminalAcknowledged != true ||
          snapshot.terminal?.presented != true) {
        return PairMatchingExperienceHost.recover(
          runtime: runtime,
          operation: PairMatchingStartOperation.fromStableSerialization(
            snapshot.startOperation,
          ),
          onExit: exit,
        );
      }
    }
    final source = PairSourceSnapshot.learn(
      ownerId: owner,
      reference: 'learn:packaged-starter-r1',
      items: allowlist.items,
    );
    return PairMatchingExperienceHost(
      runtime: runtime,
      launch: PairMatchingLaunchIntent(
        ownerId: owner,
        sourceSurface: PairSourceSurface.learn,
        sourceSnapshotRef: source.reference,
        operationId: learning.generateId(),
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          learning.nowUtc().millisecondsSinceEpoch,
          isUtc: true,
        ),
      ),
      source: source,
      preferences: PairDensityPreferences(ownerId: owner),
      onExit: exit,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _content,
    builder: (context, snapshot) {
      if (snapshot.hasData) return snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: const Text('จับคู่คำศัพท์')),
        body: Center(
          child: snapshot.hasError
              ? const Text('ยังเปิดรอบจับคู่ไม่ได้ กรุณากลับแล้วลองอีกครั้ง')
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
