import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/screens/pre_post_assessment_screen.dart';

import '../features/assessment/support/assessment_application_harness.dart';

void main() {
  test('screen consumes only score-free use-case results', () {
    final source = File(
      'lib/screens/pre_post_assessment_screen.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'AssessmentInstrumentCatalog',
      'AssessmentControlledResponse',
      'AssessmentResponseResult',
      'isCorrect',
      'responseCode',
      'LearningUseCases',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  testWidgets(
    'canonical questions and controls remain score-free through completion',
    (tester) async {
      final fixture = _ScreenFixture();
      await _mount(tester, fixture);
      expect(find.text('แบบประเมินก่อนเรียน'), findsOneWidget);
      expect(find.text('Synthetic prompt b'), findsOneWidget);
      expect(find.byType(RadioGroup<String>), findsOneWidget);
      expect(find.text('A choice'), findsOneWidget);
      expect(find.text('Z choice'), findsOneWidget);
      await _answer(tester);
      expect(find.text('Synthetic prompt a'), findsOneWidget);
      await _answer(tester);
      await tester.tap(find.byKey(const ValueKey('assessment-finish')));
      await tester.pumpAndSettle();
      expect(fixture.repository.completed, 1);
      expect(fixture.finished, 1);
      expect(fixture.exited, 0);
      for (final feedback in ['Correct', 'Incorrect', 'เฉลย', 'คะแนน']) {
        expect(find.textContaining(feedback), findsNothing);
      }
    },
  );

  testWidgets('English copy, narrow width and 200 percent text remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      final fixture = _ScreenFixture();
      await _mount(tester, fixture, languageCode: 'en', scale: 2);
      expect(find.text('Pre-assessment'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('A choice')), findsOneWidget);
      await tester.ensureVisible(find.text('A choice'));
      await tester.tap(find.text('A choice'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('assessment-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('assessment-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Synthetic prompt a'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('lost response ACK retries the exact frozen choice and latency', (
    tester,
  ) async {
    final fixture = _ScreenFixture();
    fixture.repository.loseResponseAck = true;
    await _mount(tester, fixture);
    await _answer(tester);
    expect(find.text('Synthetic prompt b'), findsOneWidget);
    expect(fixture.repository.responses, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('assessment-retry')));
    await tester.pumpAndSettle();
    expect(fixture.repository.responses, hasLength(2));
    expect(fixture.repository.responses[0], fixture.repository.responses[1]);
    expect(
      fixture.repository.responses.first['latency'],
      inInclusiveRange(0, 0x7fffffff),
    );
    expect(find.text('Synthetic prompt a'), findsOneWidget);
  });

  testWidgets('completion delivery retry never recaptures terminal state', (
    tester,
  ) async {
    final fixture = _ScreenFixture();
    var deliveries = 0;
    await _mount(
      tester,
      fixture,
      onFinished: () async {
        deliveries++;
        if (deliveries == 1) throw StateError('synthetic delivery failure');
      },
    );
    await _answer(tester);
    await _answer(tester);
    await tester.tap(find.byKey(const ValueKey('assessment-finish')));
    await tester.pumpAndSettle();
    expect(fixture.repository.completed, 1);
    expect(deliveries, 1);
    await tester.tap(find.byKey(const ValueKey('assessment-retry')));
    await tester.pumpAndSettle();
    expect(deliveries, 2);
    expect(fixture.repository.completed, 1);
    expect(fixture.repository.responses, hasLength(2));
  });

  testWidgets('lost complete and abandon ACKs retain their terminal intent', (
    tester,
  ) async {
    final complete = _ScreenFixture();
    complete.repository.loseCompleteAck = true;
    await _mount(tester, complete);
    await _answer(tester);
    await _answer(tester);
    await tester.tap(find.byKey(const ValueKey('assessment-finish')));
    await tester.pumpAndSettle();
    expect(complete.repository.completed, 1);
    expect(complete.finished, 0);
    await tester.tap(find.byKey(const ValueKey('assessment-retry')));
    await tester.pumpAndSettle();
    expect(complete.repository.completed, 2);
    expect(complete.finished, 1);

    final abandon = _ScreenFixture();
    abandon.repository.loseAbandonAck = true;
    await _mount(tester, abandon, key: const ValueKey('second-screen'));
    await tester.ensureVisible(find.byKey(const ValueKey('assessment-leave')));
    await tester.tap(find.byKey(const ValueKey('assessment-leave')));
    await tester.pumpAndSettle();
    expect(abandon.repository.abandoned, 1);
    expect(abandon.finished, 0);
    expect(find.text('Synthetic prompt b'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assessment-retry')));
    await tester.pumpAndSettle();
    expect(abandon.repository.abandoned, 2);
    expect(abandon.finished, 1);
    expect(abandon.repository.responses, isEmpty);
  });

  testWidgets(
    'expired lease clears questions and exits without terminal capture',
    (tester) async {
      final fixture = _ScreenFixture();
      await _mount(tester, fixture);
      expect(find.text('Synthetic prompt b'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Synthetic prompt b'), findsNothing);
      expect(find.byType(RadioGroup<String>), findsNothing);
      await tester.tap(find.byKey(const ValueKey('assessment-exit')));
      await tester.pump();
      expect(fixture.exited, 1);
      expect(fixture.finished, 0);
      expect(fixture.repository.completed, 0);
      expect(fixture.repository.abandoned, 0);
      expect(fixture.repository.responses, isEmpty);
    },
  );

  testWidgets(
    'owner binding false burns pending load and cannot resume stale questions',
    (tester) async {
      final fixture = _ScreenFixture();
      fixture.repository.startGate = Completer<void>();
      await _mount(tester, fixture, settle: false);
      await fixture.repository.startEntered.future;
      fixture.current.value = false;
      await tester.pump();
      fixture.repository.startGate!.complete();
      await tester.pumpAndSettle();
      fixture.current.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Synthetic prompt b'), findsNothing);
      expect(fixture.repository.base.calls, isEmpty);
      expect(fixture.finished, 0);
    },
  );

  testWidgets(
    'real lifecycle pause hides question and rejects delayed answer ACK',
    (tester) async {
      final fixture = _ScreenFixture();
      await _mount(tester, fixture);
      fixture.repository.responseGate = Completer<void>();
      expect(find.text('Synthetic prompt b'), findsOneWidget);
      await tester.tap(find.text('A choice'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assessment-submit')));
      await tester.pump();
      expect(fixture.repository.responses, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Synthetic prompt b'), findsNothing);
      fixture.repository.responseGate!.complete();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic prompt a'), findsNothing);
      expect(find.text('Synthetic prompt b'), findsNothing);
      expect(
        fixture.repository.base.calls.where(
          (call) => call['method'] == 'response',
        ),
        isEmpty,
      );
      expect(fixture.finished, 0);
    },
  );

  testWidgets(
    'covered and null routes cannot display or create private questions',
    (tester) async {
      final fixture = _ScreenFixture();
      final navigator = GlobalKey<NavigatorState>();
      await _mount(tester, fixture, navigator: navigator);
      expect(find.text('Synthetic prompt b'), findsOneWidget);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Synthetic prompt b'), findsNothing);
      final noRoute = _ScreenFixture();
      await tester.pumpWidget(MaterialApp(builder: (_, _) => noRoute.screen()));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic prompt b'), findsNothing);
      expect(noRoute.repository.base.calls, isEmpty);
    },
  );

  for (final change in [
    'owner',
    'command',
    'useCases',
    'current',
    'language',
  ]) {
    testWidgets('$change replacement invalidates a delayed old response', (
      tester,
    ) async {
      final fixture = _ScreenFixture();
      await _mount(tester, fixture);
      fixture.repository.responseGate = Completer<void>();
      expect(find.text('Synthetic prompt b'), findsOneWidget);
      await tester.tap(find.text('A choice'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assessment-submit')));
      await tester.pump();
      expect(fixture.repository.responses, hasLength(1));
      final next = _ScreenFixture();
      final changedCurrent = ValueNotifier<bool>(true);
      addTearDown(changedCurrent.dispose);
      final post = syntheticRun(phase: AssessmentPhase.post);
      fixture.repository.base.runs.add(post);
      await _mount(
        tester,
        fixture,
        ownerId: change == 'owner' ? 'other-owner' : null,
        command: change == 'command' ? syntheticStart(post) : null,
        useCases: change == 'useCases' ? next.useCases : null,
        current: change == 'current' ? changedCurrent : null,
        languageCode: change == 'language' ? 'en' : 'th',
      );
      fixture.repository.responseGate!.complete();
      await tester.pumpAndSettle();
      expect(
        fixture.repository.base.calls.where(
          (call) => call['method'] == 'response',
        ),
        isEmpty,
      );
      expect(fixture.finished, 0);
      expect(find.text('Synthetic prompt a'), findsNothing);
    });
  }
}

Future<void> _mount(
  WidgetTester tester,
  _ScreenFixture fixture, {
  bool settle = true,
  String languageCode = 'th',
  double scale = 1,
  Key? key,
  GlobalKey<NavigatorState>? navigator,
  Future<void> Function()? onFinished,
  String? ownerId,
  AssessmentStartCommand? command,
  AssessmentUseCases? useCases,
  ValueListenable<bool>? current,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: fixture.screen(
        key: key,
        languageCode: languageCode,
        onFinished: onFinished,
        ownerId: ownerId,
        command: command,
        useCases: useCases,
        current: current,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _answer(WidgetTester tester) async {
  await tester.ensureVisible(find.text('A choice'));
  await tester.tap(find.text('A choice'));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('assessment-submit')));
  expect(
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('assessment-submit')))
        .onPressed,
    isNotNull,
  );
  await tester.tap(find.byKey(const ValueKey('assessment-submit')));
  await tester.pumpAndSettle();
}

final class _ScreenFixture {
  _ScreenFixture() {
    final definition = syntheticDefinition();
    repository = _ScreenRepository(SyntheticAssessmentRepository([run]));
    useCases = AssessmentUseCases(
      repository: repository,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [definition]),
      contentAuthority: SyntheticContentAuthority(definition),
    );
  }
  final run = syntheticRun();
  final current = ValueNotifier<bool>(true);
  late final _ScreenRepository repository;
  late final AssessmentUseCases useCases;
  var finished = 0;
  var exited = 0;

  Widget screen({
    Key? key,
    String languageCode = 'th',
    Future<void> Function()? onFinished,
    String? ownerId,
    AssessmentStartCommand? command,
    AssessmentUseCases? useCases,
    ValueListenable<bool>? current,
  }) => PrePostAssessmentScreen(
    key: key,
    useCases: useCases ?? this.useCases,
    command: command ?? syntheticStart(run),
    ownerId: ownerId ?? run.ownerId,
    current: current ?? this.current,
    languageCode: languageCode,
    onFinished:
        onFinished ??
        () async {
          finished++;
        },
    onExit: () {
      exited++;
    },
  );
}

final class _ScreenRepository implements AssessmentRepository {
  _ScreenRepository(this.base);
  final SyntheticAssessmentRepository base;
  Completer<void>? startGate;
  final startEntered = Completer<void>();
  Completer<void>? responseGate;
  bool loseResponseAck = false;
  bool loseCompleteAck = false;
  bool loseAbandonAck = false;
  int completed = 0;
  int abandoned = 0;
  final responses = <Map<String, Object>>[];

  @override
  Future<AssessmentRun> start(
    AssessmentStartCommand command, {
    required String ownerId,
    required bool Function() stillVisible,
  }) async {
    if (!startEntered.isCompleted) startEntered.complete();
    await startGate?.future;
    if (!stillVisible()) throw StateError('synthetic stale start');
    return base.start(command, ownerId: ownerId, stillVisible: stillVisible);
  }

  @override
  Future<AssessmentRun> getRun({
    required String ownerId,
    required String runId,
  }) => base.getRun(ownerId: ownerId, runId: runId);
  @override
  Future<AssessmentPresentationRead> requireActivePresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) => base.requireActivePresentation(
    ownerId: ownerId,
    runId: runId,
    stillVisible: stillVisible,
  );
  @override
  Future<AssessmentResponseResult> recordResponse({
    required String ownerId,
    required String runId,
    required String itemId,
    required String option,
    required int responseTimeMs,
    required bool Function() stillVisible,
  }) async {
    responses.add({
      'item': itemId,
      'option': option,
      'latency': responseTimeMs,
    });
    await responseGate?.future;
    if (!stillVisible()) throw StateError('synthetic stale response');
    final result = await base.recordResponse(
      ownerId: ownerId,
      runId: runId,
      itemId: itemId,
      option: option,
      responseTimeMs: responseTimeMs,
      stillVisible: stillVisible,
    );
    if (loseResponseAck) {
      loseResponseAck = false;
      throw StateError('synthetic response ACK lost');
    }
    return result;
  }

  @override
  Future<AssessmentRun> complete({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    completed++;
    final run = await base.complete(
      ownerId: ownerId,
      runId: runId,
      stillVisible: stillVisible,
    );
    if (loseCompleteAck) {
      loseCompleteAck = false;
      throw StateError('synthetic complete ACK lost');
    }
    return run;
  }

  @override
  Future<AssessmentRun> abandon({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    abandoned++;
    final run = await base.abandon(
      ownerId: ownerId,
      runId: runId,
      stillVisible: stillVisible,
    );
    if (loseAbandonAck) {
      loseAbandonAck = false;
      throw StateError('synthetic abandon ACK lost');
    }
    return run;
  }

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) =>
      base.listRunsForStudyCycle(ownerId: ownerId, studyCycleId: studyCycleId);
  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) => base.listOutcomeEvidence(
    ownerId: ownerId,
    learningSessionId: learningSessionId,
  );
}
