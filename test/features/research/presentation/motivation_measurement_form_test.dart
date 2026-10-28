import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';

const _finish = ValueKey('measurement-finish');
const _retry = ValueKey('measurement-retry');
const _skip = ValueKey('measurement-skip');
const _withdraw = ValueKey('measurement-withdraw');
final _at = DateTime.utc(2026, 10, 29, 12);

void main() {
  late _Repository repository;
  late ValueNotifier<bool> current;
  late List<MotivationMeasurementRun> finished;
  setUp(() {
    repository = _Repository(_initial());
    current = ValueNotifier(true);
    finished = [];
  });
  tearDown(() => current.dispose());

  Future<void> mount(
    WidgetTester tester, {
    MotivationTimepoint point = MotivationTimepoint.baseline,
    String language = 'en',
    Future<void> Function(MotivationMeasurementRun)? onFinished,
    bool dark = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: MotivationMeasurementForm(
              repository: repository,
              ownerId: repository.run.ownerId,
              runId: repository.run.id,
              timepoint: point,
              current: current,
              languageCode: language,
              onFinished:
                  onFinished ??
                  (run) async {
                    finished.add(run);
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> choose(
    WidgetTester tester,
    String item, {
    String code = 'high',
  }) async {
    final choice = find.byKey(ValueKey('measurement-$item-$code'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, Key key) async {
    final button = find.byKey(key);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('an inactive token shows no private items and does not load', (
    tester,
  ) async {
    current.value = false;
    await mount(tester);
    expect(repository.loads, 0);
    expect(find.text('Before item one'), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });

  testWidgets(
    'fresh load binds the supplied owner and run and shows only baseline items',
    (tester) async {
      await mount(tester);
      expect(repository.loaded, [(repository.run.ownerId, repository.run.id)]);
      expect(repository.starts, 0);
      expect(find.text('Before item one'), findsOneWidget);
      expect(find.text('After item one'), findsNothing);
      expect(find.text('High'), findsOneWidget);
      expect(find.byKey(_finish), findsNothing);
    },
  );

  testWidgets('a load failure retries the read without starting a run', (
    tester,
  ) async {
    repository.failLoad = true;
    await mount(tester);
    expect(find.byKey(_retry), findsOneWidget);
    expect(find.text('Before item one'), findsNothing);
    repository.failLoad = false;
    await press(tester, _retry);
    expect(repository.loads, 2);
    expect(repository.starts, 0);
    expect(find.text('Before item one'), findsOneWidget);
  });

  testWidgets(
    'saving keeps the same item until its repository acknowledgement',
    (tester) async {
      final save = Completer<MotivationMeasurementRun>();
      repository.onRecord = (_) => save.future;
      await mount(tester);
      await choose(tester, 'baseline-a');
      expect(find.text('Before item one'), findsOneWidget);
      expect(find.text('Before item two'), findsNothing);
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.byKey(const ValueKey('measurement-baseline-a-low')),
            )
            .enabled,
        isFalse,
      );
      save.complete(repository.commit(repository.records.single));
      await tester.pump();
      expect(find.text('Before item two'), findsOneWidget);
      expect(repository.records, hasLength(1));
    },
  );

  testWidgets(
    'a failed save retries the identical command and cannot change its selected code',
    (tester) async {
      repository.failNextRecord = true;
      await mount(tester);
      await choose(tester, 'baseline-a');
      final original = repository.records.single;
      expect(find.text('Before item one'), findsOneWidget);
      expect(find.textContaining('Save not confirmed'), findsOneWidget);
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.byKey(const ValueKey('measurement-baseline-a-low')),
            )
            .enabled,
        isFalse,
      );
      await press(tester, _retry);
      expect(repository.records, hasLength(2));
      expect(identical(repository.records.last, original), isTrue);
      expect(repository.run.responses.single.responseCode, 'high');
      expect(find.text('Before item two'), findsOneWidget);
    },
  );

  testWidgets(
    'lost acknowledgement retries one fact without changing its time',
    (tester) async {
      repository.loseNextAcknowledgement = true;
      await mount(tester);
      await choose(tester, 'baseline-a');
      final stored = repository.run.responses.single;
      expect(find.text('Before item one'), findsOneWidget);
      await press(tester, _retry);
      expect(repository.records, hasLength(2));
      expect(
        identical(repository.records.first, repository.records.last),
        isTrue,
      );
      expect(repository.run.responses, hasLength(1));
      expect(repository.run.responses.single.id, stored.id);
      expect(
        repository.run.responses.single.answeredAtUtc,
        stored.answeredAtUtc,
      );
    },
  );

  testWidgets(
    'partial baseline stays incomplete and supplies no score classification',
    (tester) async {
      await mount(tester);
      await choose(tester, 'baseline-a');
      expect(repository.run.score(MotivationTimepoint.baseline), isNull);
      expect(find.text('Before item two'), findsOneWidget);
      expect(find.byKey(_finish), findsNothing);
      expect(finished, isEmpty);
    },
  );

  testWidgets(
    'recorded baseline items remain immutable and finish performs no close',
    (tester) async {
      repository.commit(_command(repository.run, 'baseline-a'));
      repository.commit(_command(repository.run, 'baseline-b', code: 'low'));
      await mount(tester);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byKey(_finish), findsOneWidget);
      await press(tester, _finish);
      expect(finished.single.state, MotivationMeasurementRunState.started);
      expect(repository.records, isEmpty);
      expect(repository.closes, isEmpty);
    },
  );

  testWidgets('post renders only supplied post items', (tester) async {
    repository.commit(_command(repository.run, 'baseline-a'));
    repository.commit(_command(repository.run, 'baseline-b'));
    await mount(tester, point: MotivationTimepoint.post);
    expect(find.text('After item one'), findsOneWidget);
    expect(find.text('Before item one'), findsNothing);
    expect(find.text('How do you feel after learning?'), findsOneWidget);
  });

  testWidgets(
    'post acknowledgement and callback delivery have separate retries',
    (tester) async {
      repository.commit(_command(repository.run, 'baseline-a'));
      repository.commit(_command(repository.run, 'baseline-b'));
      var deliveries = 0;
      await mount(
        tester,
        point: MotivationTimepoint.post,
        onFinished: (run) async {
          deliveries++;
          if (deliveries == 1) {
            throw StateError('synthetic navigation failure');
          }
          finished.add(run);
        },
      );
      await choose(tester, 'post-a');
      expect(repository.run.state, MotivationMeasurementRunState.completed);
      await press(tester, _finish);
      expect(find.textContaining('Saved. Could not continue.'), findsOneWidget);
      expect(find.textContaining('Save not confirmed'), findsNothing);
      expect(repository.records, hasLength(1));
      expect(repository.closes, isEmpty);
      await press(tester, _retry);
      expect(deliveries, 2);
      expect(repository.records, hasLength(1));
      expect(repository.closes, isEmpty);
      expect(finished.single.state, MotivationMeasurementRunState.completed);
    },
  );

  testWidgets('skip delegates a real close and forwards the returned fact', (
    tester,
  ) async {
    await mount(tester);
    await press(tester, _skip);
    expect(
      repository.closes.single.state,
      MotivationMeasurementRunState.skipped,
    );
    expect(finished.single.state, MotivationMeasurementRunState.skipped);
    expect(repository.records, isEmpty);
    expect(find.byType(RadioListTile<String>), findsNothing);
  });

  testWidgets('successful answer moves focus to the next supplied item', (
    tester,
  ) async {
    await mount(tester);
    await choose(tester, 'baseline-a');
    await tester.pump();
    final question = tester.element(find.text('Before item two'));
    expect(Focus.of(question).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('withdrawal uses the injected version four repository', (
    tester,
  ) async {
    await mount(tester);
    await press(tester, _withdraw);
    expect(repository.closes.single.ownerId, repository.run.ownerId);
    expect(repository.closes.single.runId, repository.run.id);
    expect(
      repository.closes.single.state,
      MotivationMeasurementRunState.withdrawn,
    );
    expect(repository.withdrawnVersion, 4);
    expect(finished.single.state, MotivationMeasurementRunState.withdrawn);
    expect(repository.records, isEmpty);
  });

  testWidgets(
    'withdrawal failure hides questions and retries the same close without a success claim',
    (tester) async {
      repository.failNextClose = true;
      await mount(tester);
      await press(tester, _withdraw);
      expect(find.text('Before item one'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.textContaining('Withdrawal not confirmed'), findsOneWidget);
      expect(finished, isEmpty);
      final close = repository.closes.single;
      await press(tester, _retry);
      expect(identical(repository.closes.last, close), isTrue);
      expect(finished.single.state, MotivationMeasurementRunState.withdrawn);
      expect(repository.records, isEmpty);
    },
  );

  testWidgets(
    'failed withdrawal keeps the same pending close when visibility returns for the same binding',
    (tester) async {
      repository.failNextWithdrawalAfterConsent = true;
      await mount(tester);
      await press(tester, _withdraw);
      final command = repository.closes.single;
      expect(repository.withdrawnVersion, 4);
      expect(repository.run.state, MotivationMeasurementRunState.started);
      expect(finished, isEmpty);
      expect(find.byType(RadioListTile<String>), findsNothing);

      current.value = false;
      await tester.pump();
      current.value = true;
      await tester.pump();
      await tester.pump();

      expect(repository.loads, 2);
      expect(find.text('Before item one'), findsNothing);
      expect(find.text('Before item two'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byKey(_retry), findsOneWidget);
      expect(repository.records, isEmpty);
      expect(repository.closes, hasLength(1));
      expect(finished, isEmpty);
      await press(tester, _retry);
      expect(repository.closes, hasLength(2));
      expect(identical(repository.closes.last, command), isTrue);
      expect(repository.records, isEmpty);
      expect(finished, hasLength(1));
      expect(finished.single.state, MotivationMeasurementRunState.withdrawn);
    },
  );

  testWidgets(
    'completed post acknowledgement still allows real withdrawal before leaving',
    (tester) async {
      repository.commit(_command(repository.run, 'baseline-a'));
      repository.commit(_command(repository.run, 'baseline-b'));
      repository.commit(_command(repository.run, 'post-a'));
      await mount(tester, point: MotivationTimepoint.post);
      expect(find.byKey(_withdraw), findsOneWidget);
      await press(tester, _withdraw);
      expect(
        repository.closes.single.state,
        MotivationMeasurementRunState.withdrawn,
      );
      expect(finished.single.state, MotivationMeasurementRunState.withdrawn);
    },
  );

  testWidgets(
    'a failed withdrawal can leave the dedicated route without a fake success or another write',
    (tester) async {
      repository.failNextClose = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: MotivationMeasurementForm(
                        repository: repository,
                        ownerId: repository.run.ownerId,
                        runId: repository.run.id,
                        timepoint: MotivationTimepoint.baseline,
                        current: current,
                        languageCode: 'en',
                        onFinished: (run) async {
                          finished.add(run);
                        },
                      ),
                    ),
                  ),
                ),
                child: const Text('Ordinary learning'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ordinary learning'));
      await tester.pumpAndSettle();
      await press(tester, _withdraw);
      await press(tester, const ValueKey('measurement-back-to-learning'));
      await tester.pumpAndSettle();
      expect(find.text('Ordinary learning'), findsOneWidget);
      expect(repository.closes, hasLength(1));
      expect(repository.records, isEmpty);
      expect(finished, isEmpty);
    },
  );

  testWidgets(
    'a callback failure after skip retries delivery without closing twice',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        onFinished: (run) async {
          calls++;
          if (calls == 1) {
            throw StateError('synthetic navigation failure');
          }
          finished.add(run);
        },
      );
      await press(tester, _skip);
      expect(repository.closes, hasLength(1));
      expect(find.textContaining('Saved. Could not continue.'), findsOneWidget);
      await press(tester, _retry);
      expect(repository.closes, hasLength(1));
      expect(calls, 2);
      expect(finished.single.state, MotivationMeasurementRunState.skipped);
    },
  );

  testWidgets(
    'visibility becomes false immediately and a late save cannot reveal its acknowledgement',
    (tester) async {
      final save = Completer<MotivationMeasurementRun>();
      repository.onRecord = (_) => save.future;
      await mount(tester);
      await choose(tester, 'baseline-a');
      current.value = false;
      await tester.pump();
      expect(find.text('Before item one'), findsNothing);
      expect(find.text('Before item two'), findsNothing);
      save.complete(repository.commit(repository.records.single));
      await tester.pump();
      expect(find.text('Before item two'), findsNothing);
      expect(finished, isEmpty);
      current.value = true;
      await tester.pump();
      await tester.pump();
      expect(repository.loads, 2);
      expect(find.text('Before item two'), findsOneWidget);
    },
  );

  testWidgets('an old owner load cannot enter a newly bound form', (
    tester,
  ) async {
    final oldLoad = Completer<MotivationMeasurementRun?>();
    final old = repository;
    old.onLoad = () => oldLoad.future;
    await mount(tester);
    repository = _Repository(_initial(ownerId: 'owner-b'));
    await mount(tester);
    oldLoad.complete(old.run);
    await tester.pump();
    await tester.pump();
    await choose(tester, 'baseline-a');
    expect(old.records, isEmpty);
    expect(repository.records.single.ownerId, 'owner-b');
    expect(finished, isEmpty);
  });

  testWidgets('an acknowledgement for another owner never advances the form', (
    tester,
  ) async {
    repository.onRecord = (_) async => _initial(ownerId: 'owner-b');
    await mount(tester);
    await choose(tester, 'baseline-a');
    expect(find.text('Before item one'), findsOneWidget);
    expect(find.text('Before item two'), findsNothing);
    expect(find.textContaining('Save not confirmed'), findsOneWidget);
  });

  testWidgets(
    'disposing with a pending acknowledgement performs no callback or framework error',
    (tester) async {
      final save = Completer<MotivationMeasurementRun>();
      repository.onRecord = (_) => save.future;
      await mount(tester);
      await choose(tester, 'baseline-a');
      await tester.pumpWidget(
        const MaterialApp(home: Text('Ordinary learning')),
      );
      save.complete(repository.commit(repository.records.single));
      await tester.pump();
      expect(finished, isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text('Ordinary learning'), findsOneWidget);
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language narrow dark large-text form keeps accessible controls and inherited reduced motion',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, language: language, dark: true, scale: 2);
          expect(
            find.text(
              language == 'th' ? 'ก่อนเรียนข้อหนึ่ง' : 'Before item one',
            ),
            findsOneWidget,
          );
          expect(find.text(language == 'th' ? 'สูง' : 'High'), findsOneWidget);
          expect(
            MediaQuery.of(
              tester.element(find.byType(MotivationMeasurementForm)),
            ).disableAnimations,
            isTrue,
          );
          final status = tester.getSemantics(
            find.byKey(const ValueKey('measurement-status')),
          );
          expect(
            status.getSemanticsData().flagsCollection.isLiveRegion,
            isTrue,
          );
          await tester.ensureVisible(find.byKey(_skip));
          expect(
            tester.getSize(find.byKey(_skip)).height,
            greaterThanOrEqualTo(48),
          );
          await tester.ensureVisible(find.byKey(_withdraw));
          expect(
            tester.getSize(find.byKey(_withdraw)).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

MotivationResponse _command(
  MotivationMeasurementRun run,
  String item, {
  String code = 'high',
}) => MotivationResponse(
  ownerId: run.ownerId,
  runId: run.id,
  itemId: item,
  responseCode: code,
);

MotivationMeasurementRun _initial({String ownerId = 'owner-a'}) {
  final instrument = MotivationInstrument(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: 'v1',
    formId: 'synthetic-form',
    formVersion: 'v1',
    itemCatalogVersion: 'v1',
    items: [
      for (final item in [
        (
          id: 'baseline-a',
          point: MotivationTimepoint.baseline,
          th: 'ก่อนเรียนข้อหนึ่ง',
          en: 'Before item one',
        ),
        (
          id: 'baseline-b',
          point: MotivationTimepoint.baseline,
          th: 'ก่อนเรียนข้อสอง',
          en: 'Before item two',
        ),
        (
          id: 'post-a',
          point: MotivationTimepoint.post,
          th: 'หลังเรียนข้อหนึ่ง',
          en: 'After item one',
        ),
      ])
        MotivationItem(
          id: item.id,
          timepoint: item.point,
          prompts: {'th': item.th, 'en': item.en},
          options: [
            MotivationResponseOption(
              code: 'low',
              ordinalValue: 0,
              labels: const {'th': 'ต่ำ', 'en': 'Low'},
            ),
            MotivationResponseOption(
              code: 'high',
              ordinalValue: 4,
              labels: const {'th': 'สูง', 'en': 'High'},
            ),
          ],
        ),
    ],
  );
  final study = MotivationStudyProtocol(
    protocolId: 'synthetic-protocol',
    protocolVersion: 'v1',
    consentVersion: 4,
    experimentId: 'synthetic-experiment',
    experimentVersion: 1,
    instrument: instrument,
    approvedInstrumentChecksum: instrument.checksumSha256,
    appVersion: 'synthetic-app',
    buildId: 'synthetic-build',
    contentRevision: 'content-v1',
    evidencePolicyVersion: 'evidence-v1',
    catalogVersion: 'v1',
  );
  return MotivationMeasurementRun(
    id: motivationMeasurementRunId(
      ownerId: ownerId,
      permitId: 'synthetic-permit',
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      instrumentChecksumSha256: instrument.checksumSha256,
    ),
    ownerId: ownerId,
    permitId: 'synthetic-permit',
    permitPayloadSha256: 'a' * 64,
    assignmentId: 'synthetic-assignment',
    assignmentRevision: 1,
    protocolRevision: 1,
    instrumentRevision: 1,
    consentVersion: 4,
    treatment: 'standard',
    consentDecidedAtUtc: _at.subtract(const Duration(hours: 1)),
    study: study,
    databaseSchemaVersion: 15,
    state: MotivationMeasurementRunState.started,
    startedAtUtc: _at,
    localRevision: 1,
    responses: const [],
  );
}

MotivationMeasurementRun _copy(
  MotivationMeasurementRun run, {
  List<RecordedMotivationResponse>? responses,
  MotivationMeasurementRunState? state,
  DateTime? closedAtUtc,
}) => MotivationMeasurementRun(
  id: run.id,
  ownerId: run.ownerId,
  permitId: run.permitId,
  permitPayloadSha256: run.permitPayloadSha256,
  assignmentId: run.assignmentId,
  assignmentRevision: run.assignmentRevision,
  protocolRevision: run.protocolRevision,
  instrumentRevision: run.instrumentRevision,
  consentVersion: run.consentVersion,
  treatment: run.treatment,
  consentDecidedAtUtc: run.consentDecidedAtUtc,
  study: run.study,
  databaseSchemaVersion: run.databaseSchemaVersion,
  state: state ?? run.state,
  startedAtUtc: run.startedAtUtc,
  localRevision: run.localRevision + 1,
  responses: responses ?? run.responses,
  closedAtUtc: closedAtUtc ?? run.closedAtUtc,
  timing: run.timing,
);

final class _Repository implements MotivationMeasurementRepository {
  _Repository(this.run);
  MotivationMeasurementRun run;
  int starts = 0;
  int loads = 0;
  int? withdrawnVersion;
  bool failLoad = false;
  bool failNextRecord = false;
  bool loseNextAcknowledgement = false;
  bool failNextClose = false;
  bool failNextWithdrawalAfterConsent = false;
  final loaded = <(String, String)>[];
  final records = <MotivationResponse>[];
  final closes = <MotivationMeasurementClose>[];
  Future<MotivationMeasurementRun?> Function()? onLoad;
  Future<MotivationMeasurementRun> Function(MotivationResponse)? onRecord;
  @override
  Future<MotivationMeasurementRun> start(
    MotivationMeasurementStart command,
  ) async {
    starts++;
    throw StateError('Form cannot start a run');
  }

  @override
  Future<MotivationMeasurementRun?> load(String ownerId, String runId) async {
    loads++;
    loaded.add((ownerId, runId));
    if (failLoad) {
      throw StateError('synthetic read failure');
    }
    if (onLoad != null) {
      return onLoad!();
    }
    return ownerId == run.ownerId && runId == run.id ? run : null;
  }

  @override
  Future<MotivationMeasurementRun> record(MotivationResponse command) async {
    records.add(command);
    if (onRecord != null) {
      return onRecord!(command);
    }
    if (failNextRecord) {
      failNextRecord = false;
      throw StateError('synthetic save failure');
    }
    final result = commit(command);
    if (loseNextAcknowledgement) {
      loseNextAcknowledgement = false;
      throw StateError('synthetic lost acknowledgement');
    }
    return result;
  }

  MotivationMeasurementRun commit(MotivationResponse command) {
    final existing = run.responses
        .where((answer) => answer.itemId == command.itemId)
        .firstOrNull;
    if (existing != null) {
      if (existing.responseCode != command.responseCode) {
        throw StateError('Immutable response');
      }
      return run;
    }
    final responses = [
      ...run.responses,
      RecordedMotivationResponse(
        id: motivationResponseId(runId: run.id, itemId: command.itemId),
        itemId: command.itemId,
        responseCode: command.responseCode,
        ordinalValue: run.instrument
            .response(command.itemId, command.responseCode)
            .ordinalValue,
        answeredAtUtc: _at.add(Duration(seconds: run.responses.length + 1)),
        localRevision: 1,
      ),
    ];
    run = _copy(run, responses: responses);
    if (run.score(MotivationTimepoint.baseline) != null &&
        run.score(MotivationTimepoint.post) != null) {
      run = _copy(
        run,
        state: MotivationMeasurementRunState.completed,
        closedAtUtc: responses.last.answeredAtUtc,
      );
    }
    return run;
  }

  @override
  Future<MotivationMeasurementRun> close(
    MotivationMeasurementClose command,
  ) async {
    closes.add(command);
    if (command.state == MotivationMeasurementRunState.withdrawn &&
        failNextWithdrawalAfterConsent) {
      failNextWithdrawalAfterConsent = false;
      withdrawnVersion = run.study.consentVersion;
      throw StateError('synthetic run close failure after canonical denial');
    }
    if (failNextClose) {
      failNextClose = false;
      throw StateError('synthetic close failure');
    }
    if (command.state == MotivationMeasurementRunState.withdrawn) {
      withdrawnVersion = run.study.consentVersion;
    }
    run = _copy(
      run,
      state: command.state,
      closedAtUtc: _at.add(const Duration(minutes: 1)),
    );
    return run;
  }
}
