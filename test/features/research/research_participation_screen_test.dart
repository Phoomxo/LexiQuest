import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/research/application/adventure_research_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/presentation/research_participation_panel.dart';
import 'package:vocab_learning_app/features/research/presentation/research_participation_screen.dart';

import '../../support/motivation_research_fixture.dart';

// Real screen, panel, runtime and SQLite repositories. Only the shared fixture's
// explicitly synthetic issuer/receipt authority and platform clipboard are used.
// These tests do not assert production issuer approval or questionnaire validity.
void main() {
  _screenTest(
    'opening without a permit never enrolls or creates research data',
    (tester, h) async {
      final f = await h.fixture(enroll: false);
      await h.show(h.runtime(f));
      await h.drain();
      expect(h.panel.permit, isNull);
      expect(find.text('Consent: Not ready'), findsOneWidget);
      expect(await h.counts(f), [0, 0, 0, 0, 0]);
    },
  );

  _screenTest(
    'pasted import is validated and committed through the real runtime',
    (tester, h) async {
      final f = await h.fixture(enroll: false);
      final notifications = <String>[];
      final runtime = h.runtime(
        f,
        onMutation: (owner) async {
          expect(
            await f.database
                .select(f.database.researchParticipationPermits)
                .get(),
            hasLength(1),
          );
          notifications.add(owner);
        },
      );
      await h.show(runtime);
      await h.paste(_document(f.permit()));
      await h.tap('import');
      await h.until(() => h.panel.permit != null);
      expect(h.panel.permit!.id, 'permit:a');
      expect(find.text('Consent: Verified externally'), findsOneWidget);
      expect(notifications, ['owner:a']);
      expect(await h.counts(f), [1, 0, 0, 0, 0]);
    },
  );

  _screenTest(
    'untrusted signed import stays unverified and creates no permit',
    (tester, h) async {
      final f = await h.fixture(enroll: false);
      f.authority.validSignature = false;
      await h.show(h.runtime(f));
      final document = _document(f.permit());
      await h.paste(document);
      await h.tap('import');
      await h.until(
        () => find
            .byKey(const ValueKey('research-participation-retry'))
            .evaluate()
            .isNotEmpty,
      );
      expect(h.panel.permit, isNull);
      expect(find.textContaining('Verified externally'), findsNothing);
      expect(await h.counts(f), [0, 0, 0, 0, 0]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        document,
      );
    },
  );

  _screenTest('withdrawal commits before ordinary learning navigation', (
    tester,
    h,
  ) async {
    final f = await h.fixture();
    final runtime = h.runtime(f);
    final run = (await tester.runAsync(
      () => runtime.useCases.prepare(ownerId: 'owner:a', permitId: 'permit:a'),
    ))!;
    await tester.runAsync(
      () => f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Ordinary learning'),
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ResearchParticipationScreen(
                        runtime: runtime,
                        ownerId: 'owner:a',
                      ),
                    ),
                  ),
                  child: const Text('Open participation'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open participation'));
    await tester.pumpAndSettle();
    await h.until(
      () =>
          find.byType(ResearchParticipationPanel).evaluate().isNotEmpty &&
          h.panel.permit != null,
    );
    await h.tap('withdraw');
    await h.until(() => h.panel.permit == null);
    final consent = (await h.complete(
      f.database.select(f.database.researchConsents).get(),
    )).single;
    final storedRun = (await h.complete(
      f.database.select(f.database.motivationMeasurementRuns).get(),
    )).single;
    expect(consent.withdrawnAtUtcMs, isNotNull);
    expect(storedRun.state, 'withdrawn');
    expect(await h.counts(f), [1, 1, 1, 0, 0]);
    await h.tap('continue');
    await tester.pumpAndSettle();
    expect(find.text('Ordinary learning'), findsOneWidget);
    expect(find.byType(ResearchParticipationScreen), findsNothing);
  });

  _screenTest(
    'owner prop replacement clears the previous verified projection immediately',
    (tester, h) async {
      final f = await h.fixture();
      final runtime = h.runtime(f);
      await h.show(runtime);
      await h.until(() => h.panel.permit != null);
      await h.show(runtime, ownerId: 'owner:b');
      expect(h.panel.permit, isNull);
      expect(find.textContaining('Verified externally'), findsNothing);
    },
  );

  _screenTest('active-owner database change invalidates the open screen', (
    tester,
    h,
  ) async {
    final f = await h.fixture();
    await h.show(h.runtime(f));
    await h.until(() => h.panel.permit != null);
    await h.complete(_activateOwnerB(f));
    await h.until(() => h.panel.permit == null);
    expect(find.textContaining('Verified externally'), findsNothing);
    expect(await h.counts(f), [1, 0, 0, 0, 0]);
  });

  _screenTest('old import closure cannot import for a newly selected owner', (
    tester,
    h,
  ) async {
    final f = await h.fixture(enroll: false);
    final runtime = h.runtime(f);
    await h.show(runtime);
    final oldImport = h.panel.onImport;
    await h.complete(_activateOwnerB(f));
    await h.show(runtime, ownerId: 'owner:b');
    final document = _document(f.permit(), ownerId: 'owner:b');
    await h.expectDenied(oldImport(document));
    expect(await h.counts(f), [0, 0, 0, 0, 0]);
    await h.complete(h.panel.onImport(document));
    await h.until(() => h.panel.permit?.ownerId == 'owner:b');
    expect(await h.counts(f), [1, 0, 0, 0, 0]);
  });

  _screenTest(
    'runtime replacement hides old permit while new authority is pending',
    (tester, h) async {
      final first = await h.fixture();
      final second = await h.fixture();
      await h.show(h.runtime(first));
      await h.until(() => h.panel.permit != null);
      final gate = h.pauseAuthority(second);
      await h.show(h.runtime(second));
      expect(h.panel.permit, isNull);
      await h.until(() => gate.entered.isCompleted);
      expect(find.textContaining('Verified externally'), findsNothing);
      gate.release.complete();
      await h.until(() => h.panel.permit != null);
    },
  );

  _screenTest('old import closure cannot write through a replacement runtime', (
    tester,
    h,
  ) async {
    final first = await h.fixture(enroll: false);
    final second = await h.fixture(enroll: false);
    await h.show(h.runtime(first));
    final oldImport = h.panel.onImport;
    await h.show(h.runtime(second));
    await h.expectDenied(oldImport(_document(first.permit())));
    expect(await h.counts(first), [0, 0, 0, 0, 0]);
    expect(await h.counts(second), [0, 0, 0, 0, 0]);
  });

  _screenTest(
    'old withdrawal closure cannot withdraw the replacement runtime',
    (tester, h) async {
      final first = await h.fixture();
      final second = await h.fixture();
      await h.show(h.runtime(first));
      await h.until(() => h.panel.permit != null);
      final oldWithdraw = h.panel.onWithdraw;
      final next = h.runtime(second);
      await h.show(next);
      await h.expectDenied(oldWithdraw());
      expect(await h.complete(next.currentPermit('owner:a')), isNotNull);
      final consents = await h.complete(
        second.database.select(second.database.researchConsents).get(),
      );
      expect(consents.single.withdrawnAtUtcMs, isNull);
    },
  );

  _screenTest(
    'expiry while open removes verified status without a database event',
    (tester, h) async {
      final f = await h.fixture(enroll: false);
      await tester.runAsync(
        () => f.participation.importPermit(
          f.permit(expiresAtUtc: f.now.add(const Duration(seconds: 20))),
        ),
      );
      await h.show(h.runtime(f));
      await h.until(() => h.panel.permit != null);
      f.now = f.now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(h.panel.permit, isNull);
      await h.drain();
      expect(find.textContaining('Verified externally'), findsNothing);
    },
  );

  _screenTest(
    'resume revalidates unavailable receipt authority and hides cached approval',
    (tester, h) async {
      final f = await h.fixture();
      await h.show(h.runtime(f));
      await h.until(() => h.panel.permit != null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      f.authority.receiptsActive = false;
      final gate = h.pauseAuthority(f);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.panel.permit, isNull);
      await h.until(() => gate.entered.isCompleted);
      gate.release.complete();
      await h.drain();
      expect(find.textContaining('Verified externally'), findsNothing);
    },
  );

  _screenTest(
    'resume catches clock expiry even if no foreground timer elapsed',
    (tester, h) async {
      final f = await h.fixture();
      await h.show(h.runtime(f));
      await h.until(() => h.panel.permit != null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      f.now = f.now.add(const Duration(days: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.panel.permit, isNull);
      await h.drain();
      expect(find.textContaining('Verified externally'), findsNothing);
    },
  );

  _screenTest(
    'unavailable authority at entry cannot claim verified participation',
    (tester, h) async {
      final f = await h.fixture();
      f.authority.onRead = () async =>
          throw StateError('synthetic_private_authority_unavailable');
      await h.show(h.runtime(f));
      await h.drain();
      expect(h.panel.permit, isNull);
      expect(find.textContaining('Verified externally'), findsNothing);
      expect(find.textContaining('synthetic_private'), findsNothing);
    },
  );

  _screenTest('late import refresh cannot publish its old runtime permit', (
    tester,
    h,
  ) async {
    final first = await h.fixture(enroll: false);
    final second = await h.fixture(enroll: false);
    _ReadGate? gate;
    final runtime = h.runtime(
      first,
      onMutation: (_) async {
        gate ??= h.pauseAuthority(first);
      },
    );
    await h.show(runtime);
    final action = h.panel.onImport;
    // Catch a legitimate stale-context rejection before yielding the future.
    final operation = action(_document(first.permit())).then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    await h.until(() => gate?.entered.isCompleted ?? false);
    await h.show(h.runtime(second));
    gate!.release.complete();
    await h.complete(operation);
    await h.drain();
    expect(h.panel.permit, isNull);
    expect(find.textContaining('Verified externally'), findsNothing);
    expect(await h.counts(first), [1, 0, 0, 0, 0]);
    expect(await h.counts(second), [0, 0, 0, 0, 0]);
  });

  _screenTest('disposal during authority lookup contains late results', (
    tester,
    h,
  ) async {
    final f = await h.fixture();
    final gate = h.pauseAuthority(f);
    await h.show(h.runtime(f));
    await h.until(() => gate.entered.isCompleted);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.release.complete();
    await h.drain();
    expect(tester.takeException(), isNull);
  });
}

void _screenTest(
  String description,
  Future<void> Function(WidgetTester, _Harness) body,
) {
  testWidgets(description, (tester) async {
    final harness = _Harness(tester);
    // Runtime replacement intentionally uses separate NativeDatabase.memory()
    // executors, never two AppDatabases sharing an executor.
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() async {
      try {
        for (final fixture in harness.fixtures) {
          await fixture.database.close();
        }
      } finally {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      }
    });
    try {
      await body(tester, harness);
    } finally {
      for (final gate in harness.gates) {
        if (!gate.release.isCompleted) gate.release.complete();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      // Drain futures created in the widget's fake-async zone before closing
      // SQLite in the outer test teardown; runAsync(close) cannot pump them.
      await harness.drain();
    }
  });
}

class _ReadGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Harness {
  _Harness(this.tester);
  final WidgetTester tester;
  final fixtures = <MotivationResearchFixture>[];
  final gates = <_ReadGate>[];

  ResearchParticipationPanel get panel =>
      tester.widget(find.byType(ResearchParticipationPanel));

  Future<MotivationResearchFixture> fixture({bool enroll = true}) async {
    final fixture = MotivationResearchFixture();
    fixtures.add(fixture);
    await tester.runAsync(() => fixture.initialize(enroll: enroll));
    return fixture;
  }

  AdventureResearchRuntime runtime(
    MotivationResearchFixture f, {
    Future<void> Function(String)? onMutation,
  }) => AdventureResearchRuntime(
    participation: f.participation,
    measurements: f.measurements,
    opportunities: DriftMeasurementOpportunityRepository(
      f.database,
      measurements: f.measurements,
      nowUtc: () => f.now,
    ),
    consent: DriftResearchConsentRepository(f.database),
    onLocalMutation: onMutation,
  );

  Future<void> show(
    AdventureResearchRuntime runtime, {
    String ownerId = 'owner:a',
  }) => tester.pumpWidget(
    MaterialApp(
      home: ResearchParticipationScreen(
        key: const ValueKey('same-participation-screen'),
        runtime: runtime,
        ownerId: ownerId,
      ),
    ),
  );

  _ReadGate pauseAuthority(MotivationResearchFixture f) {
    final gate = _ReadGate();
    gates.add(gate);
    f.authority.onRead = () async {
      if (!gate.entered.isCompleted) gate.entered.complete();
      await gate.release.future;
    };
    return gate;
  }

  Future<void> until(bool Function() condition) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      if (condition()) return;
    }
    expect(
      condition(),
      isTrue,
      reason: 'Bounded screen condition was not reached',
    );
  }

  Future<void> drain() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  // Futures already created by a widget can hold a SQLite transaction in the
  // fake-async zone. Keep pumping that zone while real I/O progresses; awaiting
  // them inside runAsync alone would prevent the transaction from completing.
  Future<T> complete<T>(Future<T> future) async {
    var done = false;
    T? result;
    Object? failure;
    StackTrace? stack;
    unawaited(
      future.then<void>(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object error, StackTrace trace) {
          failure = error;
          stack = trace;
          done = true;
        },
      ),
    );
    await until(() => done);
    if (failure != null) Error.throwWithStackTrace(failure!, stack!);
    return result as T;
  }

  Future<void> expectDenied(Future<void> future) async {
    Object? failure;
    // Attach the error handler before pumping and assert after all guarded
    // widget work finishes. expectLater itself guards synchronously.
    await complete(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          failure = error;
        },
      ),
    );
    expect(failure, isA<ResearchCaptureDenied>());
  }

  Future<void> tap(String action) async {
    final finder = find.byKey(ValueKey('research-participation-$action'));
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> paste(String document) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': document} : null,
    );
    await tap('paste');
    await tester.pumpAndSettle();
  }

  Future<List<int>> counts(MotivationResearchFixture f) async => [
    (await complete(
      f.database.select(f.database.researchParticipationPermits).get(),
    )).length,
    (await complete(
      f.database.select(f.database.motivationMeasurementRuns).get(),
    )).length,
    (await complete(
      f.database.select(f.database.motivationResponses).get(),
    )).length,
    (await complete(
      f.database.select(f.database.measurementOpportunities).get(),
    )).length,
    (await complete(f.database.select(f.database.eventsV2).get())).length,
  ];
}

String _assignment(String ownerId) =>
    DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: 'motivation',
      experimentVersion: 1,
    );

Future<void> _activateOwnerB(MotivationResearchFixture f) =>
    f.database.transaction(() async {
      await f.database
          .update(f.database.localOwners)
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await f.database
          .into(f.database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner:b',
              createdAtUtcMs: f.now
                  .subtract(const Duration(days: 1))
                  .millisecondsSinceEpoch,
            ),
          );
      await f.database
          .into(f.database.researchConsents)
          .insert(
            ResearchConsentsCompanion.insert(
              id: 'consent:owner:b:1',
              ownerId: 'owner:b',
              consentVersion: 1,
              consentState: 'accepted',
              decidedAtUtcMs: f.now
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch,
            ),
          );
      await f.database
          .into(f.database.experimentAssignments)
          .insert(
            ExperimentAssignmentsCompanion.insert(
              id: _assignment('owner:b'),
              ownerId: 'owner:b',
              experimentId: 'motivation',
              experimentVersion: 1,
              cohort: 'adventure',
              protocolVersion: '1',
              assignedAtUtcMs: f.now
                  .subtract(const Duration(minutes: 90))
                  .millisecondsSinceEpoch,
            ),
          );
    });

String _document(ResearchParticipationPermit permit, {String? ownerId}) {
  final payload = jsonDecode(permit.canonicalPayload()) as Map<String, dynamic>;
  if (ownerId != null) {
    payload['ownerId'] = ownerId;
    payload['id'] = 'permit:b';
    payload['assignmentId'] = _assignment(ownerId);
    payload['consentReceiptId'] = 'receipt:b';
  }
  return jsonEncode({
    ...payload,
    'payloadSha256': sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString(),
    'signature': permit.signature,
  });
}
