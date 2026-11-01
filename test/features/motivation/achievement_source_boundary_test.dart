import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/motivation/presentation/achievement_share_composer.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../quest/support/quest_repository_harness.dart';
import '../../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  for (final kind in ['orphan', 'research', 'malformed', 'ordinary']) {
    testWidgets(
      'actual $kind achievement source is ${kind == 'ordinary' ? 'allowed' : 'rejected'} before card preview',
      (tester) async {
        final f = (await motivationPresentationDeadline(
          tester,
          'source-$kind/open',
          () => tester.runAsync(() => _Fixture.open(kind)),
        ))!;
        Future<void>? closing;
        Future<void> finish() =>
            closing ??= closeMotivationPresentation(tester, () async {
              await f.runtime.dispose();
              await f.h.close();
            });
        try {
          await motivationPresentationDeadline(
            tester,
            'source-$kind/mount',
            () => tester.pumpWidget(
              AppDependenciesScope(
                dependencies: f.dependencies,
                child: MaterialApp(
                  home: AchievementsScreen(ownerChanges: f.ownerChanges),
                ),
              ),
            ),
          );
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('achievement-preview-first_answer'))
                .evaluate()
                .isNotEmpty,
          );
          final before = await motivationPresentationIo(
            tester,
            f.h.storage.snapshot,
          );
          await tester.tap(
            find.byKey(const ValueKey('achievement-preview-first_answer')),
          );
          await _wait(
            tester,
            () => kind == 'ordinary'
                ? find.byType(AchievementShareComposer).evaluate().isNotEmpty
                : find
                      .byKey(const ValueKey('achievement-preview-status'))
                      .evaluate()
                      .isNotEmpty,
          );
          if (kind == 'ordinary') {
            expect(find.byType(AchievementShareComposer), findsOneWidget);
          } else {
            expect(find.byType(AchievementShareComposer), findsNothing);
          }
          expect(
            await motivationPresentationIo(tester, f.h.storage.snapshot),
            before,
          );
        } finally {
          await finish();
        }
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.h, this.runtime, this.dependencies, this.ownerChanges);
  final QuestHarness h;
  final MotivationRuntime runtime;
  final AppDependencies dependencies;
  final Stream<String?> ownerChanges;
  static Future<_Fixture> open(String kind) async {
    final h = await QuestHarness.open();
    var ids = 0;
    final runtime = MotivationRuntime(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
      owners: h.storage.owners,
      nowUtc: () => h.now,
      generateId: () => 'synthetic-card-boundary-${++ids}',
    );
    runtime.setForeground(true);
    await runtime.activate(
      ownerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    await h.answer(id: 'synthetic-card-source');
    if (kind == 'orphan') {
      await h.sql(
        "UPDATE achievement_unlocks SET source_event_id='synthetic-orphan' WHERE achievement_id='first_answer'",
      );
    } else if (kind == 'malformed') {
      await h.sql(
        "UPDATE answer_attempts SET evidence_context_json='{' WHERE id='synthetic-card-source'",
      );
    } else if (kind == 'research') {
      final context = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'synthetic-research-skill',
        hintLevel: 0,
        contentRevision: 'synthetic-v1',
        rolloutMode: EvidencePolicyRolloutMode.shadow,
        protocolId: 'synthetic-protocol',
        protocolVersion: 'synthetic-v1',
        experimentId: 'synthetic-experiment',
        experimentVersion: 1,
        assignmentId: 'synthetic-assignment',
        cohort: 'synthetic-cohort',
        researchConsentVersion: 1,
        engagementAllowed: false,
      );
      await h.sql(
        'UPDATE answer_attempts SET evidence_class=?, evidence_context_json=? WHERE id=?',
        [
          context.evidenceClass.name,
          jsonEncode(context.toJson()),
          'synthetic-card-source',
        ],
      );
    }
    final progress = ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _NoGuest(),
      database: h.database,
      localOwners: h.storage.owners,
      progress: progress,
      motivation: runtime,
    );
    final io = Zone.current;
    final owners = Stream<String?>.multi((events) {
      final source = io.run(
        () => progress.watchActiveOwnerId().listen(
          events.add,
          onError: events.addError,
          onDone: events.close,
        ),
      );
      events.onCancel = () => io.run(source.cancel);
    }, isBroadcast: true);
    return _Fixture(h, runtime, dependencies, owners);
  }
}

class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic local fixture must not authenticate');
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150; i++) {
    await motivationPresentationDeadline(
      tester,
      'source-wait/io-$i',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      ),
    );
    await motivationPresentationDeadline(
      tester,
      'source-wait/pump-$i',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    if (done()) return;
  }
  fail('Actual stored achievement view did not become ready');
}
