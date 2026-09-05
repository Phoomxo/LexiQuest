import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';

// Synthetic presentation fixtures only: no database, receipt authority or
// questionnaire validation is implied by these deliberately neutral prompts.
void main() {
  testWidgets('defaults to Thai and presents only the first baseline item', (
    tester,
  ) async {
    final run = _run();
    await _pumpForm(tester, run: run);

    expect(find.text('ช่วยบอกความรู้สึกก่อนเรียน'), findsOneWidget);
    expect(find.text('คำถามก่อนเรียน 1'), findsOneWidget);
    expect(find.text('คำถามก่อนเรียน 2'), findsNothing);
    expect(find.text('คำถามหลังเรียน 1'), findsNothing);
    expect(find.byType(RadioGroup<String>), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    expect(find.text('ตัวเลือก ก'), findsOneWidget);
    expect(find.text('ข้าม'), findsOneWidget);
    expect(find.text('ถอนตัวจากการวิจัย'), findsOneWidget);
    expect(find.textContaining('ไม่กระทบการเรียน'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    _expectNoPrivateText();
  });

  testWidgets(
    'English post form uses the run instrument and selected timepoint',
    (tester) async {
      await _pumpForm(
        tester,
        run: _run(),
        timepoint: MotivationTimepoint.post,
        languageCode: 'en',
      );
      expect(find.text('How do you feel after learning?'), findsOneWidget);
      expect(find.text('Post item 1'), findsOneWidget);
      expect(find.text('Baseline item 1'), findsNothing);
      expect(find.text('Option A'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Withdraw from research'), findsOneWidget);
      expect(find.textContaining('does not affect learning'), findsWidgets);
    },
  );

  testWidgets(
    'one radio selection persists its code immediately then advances',
    (tester) async {
      var current = _run();
      final calls = <(String, String)>[];
      await _pumpForm(
        tester,
        run: current,
        onAnswer: (itemId, code) async {
          calls.add((itemId, code));
          return current = _record(current, itemId, code);
        },
      );

      await _tap(tester, _choice('choice_a'));
      expect(calls, [('baseline_1', 'choice_a')]);
      expect(find.text('คำถามก่อนเรียน 2'), findsOneWidget);
      expect(find.text('คำถามก่อนเรียน 1'), findsNothing);
      await _tap(tester, _choice('choice_b'));
      expect(calls, [('baseline_1', 'choice_a'), ('baseline_2', 'choice_b')]);
      expect(current.responses, hasLength(2));
    },
  );

  testWidgets('resumed recorded answers cannot be edited or submitted again', (
    tester,
  ) async {
    final initial = _run();
    final resumed = _record(initial, 'baseline_1', 'choice_b');
    final calls = <String>[];
    await _pumpForm(
      tester,
      run: resumed,
      onAnswer: (itemId, code) async {
        calls.add(itemId);
        return _record(resumed, itemId, code);
      },
    );
    expect(find.text('คำถามก่อนเรียน 2'), findsOneWidget);
    expect(find.text('คำถามก่อนเรียน 1'), findsNothing);
    await _tap(tester, _choice('choice_a'));
    expect(calls, ['baseline_2']);
    expect(resumed.responses.single.responseCode, 'choice_b');
    expect(initial.responses, isEmpty);
  });

  testWidgets(
    'pending answer serializes same-frame taps and all write actions',
    (tester) async {
      final run = _run();
      final pending = Completer<MotivationMeasurementRun>();
      var answerCalls = 0;
      var otherCalls = 0;
      await _pumpForm(
        tester,
        run: run,
        onAnswer: (_, _) {
          answerCalls++;
          return pending.future;
        },
        onComplete: () async => otherCalls++,
        onSkip: () async => otherCalls++,
        onWithdraw: () async => otherCalls++,
      );

      final choice = _choice('choice_a');
      expect(choice, findsOneWidget);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.tap(choice);
      await tester.pump();
      expect(answerCalls, 1);
      expect(find.text('คำถามก่อนเรียน 1'), findsOneWidget);
      expect(find.text('คำถามก่อนเรียน 2'), findsNothing);
      for (final action in ['skip', 'withdraw']) {
        final finder = _action(action);
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        expect(tester.widget<ButtonStyleButton>(finder).onPressed, isNull);
        await tester.tap(finder);
      }
      expect(otherCalls, 0);
      pending.complete(_record(run, 'baseline_1', 'choice_a'));
      await tester.pumpAndSettle();
      expect(find.text('คำถามก่อนเรียน 2'), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(_action('skip')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('failed save stays on the item and retries only the same code', (
    tester,
  ) async {
    final run = _run();
    final calls = <(String, String)>[];
    await _pumpForm(
      tester,
      run: run,
      onAnswer: (itemId, code) async {
        calls.add((itemId, code));
        if (calls.length == 1) {
          throw StateError('synthetic_private_answer synthetic_private_owner');
        }
        return _record(run, itemId, code);
      },
    );
    await _tap(tester, _choice('choice_b'));
    expect(find.text('คำถามก่อนเรียน 1'), findsOneWidget);
    expect(find.text('คำถามก่อนเรียน 2'), findsNothing);
    final status = tester.getSemantics(_status);
    expect(status.flagsCollection.isLiveRegion, isTrue);
    expect(status.label, isNotEmpty);
    expect(status.label.length, lessThanOrEqualTo(240));
    _expectNoPrivateText();
    expect(find.bySemanticsLabel(RegExp('synthetic_private')), findsNothing);
    expect(
      tester.widget<ButtonStyleButton>(_action('skip')).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<ButtonStyleButton>(_action('withdraw')).onPressed,
      isNotNull,
    );
    await _tap(tester, _action('retry'));
    expect(calls, [('baseline_1', 'choice_b'), ('baseline_1', 'choice_b')]);
    expect(find.text('คำถามก่อนเรียน 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['skip', 'withdraw']) {
    testWidgets('$action is available before answering and cannot run twice', (
      tester,
    ) async {
      final pending = Completer<void>();
      var calls = 0;
      var otherCalls = 0;
      Future<void> callback() {
        calls++;
        return pending.future;
      }

      await _pumpForm(
        tester,
        run: _run(),
        onAnswer: (_, _) async {
          otherCalls++;
          return _run();
        },
        onSkip: action == 'skip' ? callback : () async => otherCalls++,
        onWithdraw: action == 'withdraw' ? callback : () async => otherCalls++,
      );
      final finder = _action(action);
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.tap(finder);
      await tester.pump();
      expect(calls, 1);
      expect(otherCalls, 0);
      expect(
        tester.widget<ButtonStyleButton>(_action('skip')).onPressed,
        isNull,
      );
      expect(
        tester.widget<ButtonStyleButton>(_action('withdraw')).onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$action failure has a bounded retry without answering', (
      tester,
    ) async {
      var calls = 0;
      var answerCalls = 0;
      Future<void> callback() async {
        if (++calls == 1) throw StateError('synthetic_private_error');
      }

      await _pumpForm(
        tester,
        run: _run(),
        onAnswer: (_, _) async {
          answerCalls++;
          return _run();
        },
        onSkip: action == 'skip' ? callback : null,
        onWithdraw: action == 'withdraw' ? callback : null,
      );
      await _tap(tester, _action(action));
      expect(_status, findsOneWidget);
      _expectNoPrivateText();
      await _tap(tester, _action('retry'));
      expect(calls, 2);
      expect(answerCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Finish delegates completed baseline without closing the study run',
    (tester) async {
      var current = _run(itemsPerPoint: 1);
      final original = current;
      final pending = Completer<void>();
      var completeCalls = 0;
      await _pumpForm(
        tester,
        run: current,
        onAnswer: (itemId, code) async =>
            current = _record(current, itemId, code),
        onComplete: () {
          completeCalls++;
          return pending.future;
        },
      );
      expect(_enabledAction('complete'), findsNothing);
      await _tap(tester, _choice('choice_a'));
      expect(completeCalls, 0);
      expect(find.text('คำถามหลังเรียน 1'), findsNothing);
      await tester.ensureVisible(_action('complete'));
      await tester.tap(_action('complete'));
      await tester.tap(_action('complete'));
      await tester.pump();
      expect(completeCalls, 1);
      expect(current.state, MotivationMeasurementRunState.started);
      expect(current.closedAtUtc, isNull);
      expect(original.responses, isEmpty);
      expect(current.score(MotivationTimepoint.post), isNull);
      pending.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'completion failure can retry without resubmitting recorded items',
    (tester) async {
      final complete = _record(
        _run(itemsPerPoint: 1),
        'baseline_1',
        'choice_b',
      );
      var completeCalls = 0;
      var answerCalls = 0;
      await _pumpForm(
        tester,
        run: complete,
        onAnswer: (_, _) async {
          answerCalls++;
          return complete;
        },
        onComplete: () async {
          if (++completeCalls == 1) throw StateError('synthetic_private_error');
        },
      );
      await _tap(tester, _action('complete'));
      expect(_status, findsOneWidget);
      _expectNoPrivateText();
      await _tap(tester, _action('retry'));
      expect(completeCalls, 2);
      expect(answerCalls, 0);
    },
  );

  testWidgets('incomplete form has no score or efficacy and cannot finish', (
    tester,
  ) async {
    final run = _run();
    await _pumpForm(tester, run: run, languageCode: 'en');
    expect(find.text('Baseline item 1'), findsOneWidget);
    expect(_enabledAction('complete'), findsNothing);
    expect(run.score(MotivationTimepoint.baseline), isNull);
    expect(
      find.textContaining(
        RegExp(
          r'0\s*%|score\s*[:=]\s*0|\breward\b|\bearn\b|\bbonus\b|improve your score',
          caseSensitive: false,
        ),
      ),
      findsNothing,
    );
  });

  for (final fail in [false, true]) {
    testWidgets(
      'late answer ${fail ? 'failure' : 'success'} after disposal is safe',
      (tester) async {
        final run = _run();
        final pending = Completer<MotivationMeasurementRun>();
        await _pumpForm(tester, run: run, onAnswer: (_, _) => pending.future);
        await _tap(tester, _choice('choice_a'), settle: false);
        await tester.pumpWidget(const SizedBox.shrink());
        if (fail) {
          pending.completeError(StateError('synthetic_private_error'));
        } else {
          pending.complete(_record(run, 'baseline_1', 'choice_a'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('late result cannot replace a newly supplied run', (
    tester,
  ) async {
    final oldRun = _run();
    final pending = Completer<MotivationMeasurementRun>();
    await _pumpForm(tester, run: oldRun, onAnswer: (_, _) => pending.future);
    await _tap(tester, _choice('choice_a'), settle: false);
    final replacement = _run(id: 'synthetic_new_run');
    await _pumpForm(tester, run: replacement);
    pending.complete(_record(oldRun, 'baseline_1', 'choice_a'));
    await tester.pumpAndSettle();
    expect(find.text('คำถามก่อนเรียน 1'), findsOneWidget);
    expect(find.text('คำถามก่อนเรียน 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-run parent rebuild preserves an unconfirmed answer retry', (
    tester,
  ) async {
    final calls = <(String, String)>[];
    Future<MotivationMeasurementRun> save(String itemId, String code) async {
      calls.add((itemId, code));
      if (calls.length == 1) throw StateError('synthetic_private_error');
      return _record(_run(), itemId, code);
    }

    await _pumpForm(tester, run: _run(), onAnswer: save);
    await _tap(tester, _choice('choice_a'));
    await _pumpForm(tester, run: _run(), onAnswer: save);
    expect(_action('retry'), findsOneWidget);
    expect(
      tester.widget<RadioListTile<String>>(_choice('choice_b')).enabled,
      isFalse,
    );
    await _tap(tester, _action('retry'));
    expect(calls, [('baseline_1', 'choice_a'), ('baseline_1', 'choice_a')]);
  });

  testWidgets(
    'failed Skip cannot unlock an unconfirmed answer for replacement',
    (tester) async {
      var answers = 0;
      await _pumpForm(
        tester,
        run: _run(),
        onAnswer: (_, _) async {
          answers++;
          throw StateError('synthetic_private_error');
        },
        onSkip: () async => throw StateError('synthetic_private_error'),
      );
      await _tap(tester, _choice('choice_a'));
      await _tap(tester, _action('skip'));
      expect(
        tester.widget<RadioListTile<String>>(_choice('choice_b')).enabled,
        isFalse,
      );
      expect(answers, 1);
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language 32-item form scrolls at 320px and 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var current = _run(itemsPerPoint: 32, longLabels: true);
        await _pumpForm(
          tester,
          run: current,
          languageCode: language,
          textScale: 2,
          onAnswer: (itemId, code) async =>
              current = _record(current, itemId, code),
        );
        expect(find.byType(Scrollable), findsWidgets);
        for (var index = 1; index <= 32; index++) {
          expect(
            find.text(
              language == 'th'
                  ? 'คำถามก่อนเรียน $index'
                  : 'Baseline item $index',
            ),
            findsOneWidget,
          );
          for (final action in ['skip', 'withdraw']) {
            await tester.ensureVisible(_action(action));
            expect(_action(action).hitTestable(), findsOneWidget);
            expect(
              tester.getSize(_action(action)).height,
              greaterThanOrEqualTo(48),
            );
          }
          await _tap(tester, _choice('choice_b'));
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(_action('complete'));
        expect(_action('complete').hitTestable(), findsOneWidget);
        expect(current.responses, hasLength(32));
      },
    );
  }

  testWidgets('heading and radio semantics support keyboard traversal', (
    tester,
  ) async {
    await _pumpForm(tester, run: _run(), languageCode: 'en');
    final heading = tester.getSemantics(
      find.text('How do you feel before learning?'),
    );
    expect(heading.flagsCollection.isHeader, isTrue);
    // RadioListTile merges descendants; assert the data exported to assistive
    // technology, including the child radio's checked/group flags.
    final option = tester.getSemantics(_choice('choice_a')).getSemanticsData();
    expect(option.label, contains('Option A'));
    expect(
      option.flagsCollection.isChecked,
      CheckedState.isFalse,
      reason: option.toString(),
    );
    expect(option.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(option.flagsCollection.isFocused, isNot(Tristate.none));

    final visited = <String>{};
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final action in ['skip', 'withdraw']) {
        final node = tester.getSemantics(_action(action));
        if (node.flagsCollection.isFocused == Tristate.isTrue) {
          visited.add(action);
        }
      }
    }
    expect(visited, containsAll(['skip', 'withdraw']));
  });
}

Finder _action(String action) =>
    find.byKey(ValueKey('research-measurement-$action'));
Finder get _status => find.byKey(const ValueKey('research-measurement-status'));
Finder _enabledAction(String action) => find.byWidgetPredicate(
  (widget) =>
      widget is ButtonStyleButton &&
      widget.key == ValueKey('research-measurement-$action') &&
      widget.onPressed != null,
);
Finder _choice(String code) => find.byWidgetPredicate(
  (widget) => widget is RadioListTile<String> && widget.value == code,
);

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required MotivationMeasurementRun run,
  MotivationTimepoint timepoint = MotivationTimepoint.baseline,
  String languageCode = 'th',
  double textScale = 1,
  Future<MotivationMeasurementRun> Function(String, String)? onAnswer,
  Future<void> Function()? onComplete,
  Future<void> Function()? onSkip,
  Future<void> Function()? onWithdraw,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MotivationMeasurementForm(
          run: run,
          timepoint: timepoint,
          onAnswer:
              onAnswer ?? (itemId, code) async => _record(run, itemId, code),
          onComplete: onComplete ?? () async {},
          onSkip: onSkip ?? () async {},
          onWithdraw: onWithdraw ?? () async {},
          languageCode: languageCode,
        ),
      ),
    ),
  ),
);

void _expectNoPrivateText() => expect(
  find.textContaining(RegExp('synthetic_private|StateError|Bad state:')),
  findsNothing,
);

MotivationMeasurementRun _run({
  int itemsPerPoint = 2,
  bool longLabels = false,
  String id = 'synthetic_private_run',
}) => MotivationMeasurementRun(
  id: id,
  ownerId: 'synthetic_private_owner',
  permitId: 'synthetic_private_permit',
  assignmentId: 'synthetic_private_assignment',
  instrument: MotivationInstrument(
    instrumentId: 'synthetic_ui',
    instrumentVersion: '1',
    formId: 'synthetic_paired',
    formVersion: '1',
    itemCatalogVersion: '1',
    items: [
      for (final point in MotivationTimepoint.values)
        for (var index = 1; index <= itemsPerPoint; index++)
          MotivationItem(
            id: '${point.name}_$index',
            timepoint: point,
            prompts: {
              'th':
                  'คำถาม${point == MotivationTimepoint.baseline ? 'ก่อน' : 'หลัง'}เรียน $index',
              'en':
                  '${point == MotivationTimepoint.baseline ? 'Baseline' : 'Post'} item $index',
            },
            options: [
              for (final (code, ordinal, th, en) in [
                ('choice_a', 0, 'ตัวเลือก ก', 'Option A'),
                ('choice_b', 1, 'ตัวเลือก ข', 'Option B'),
              ])
                MotivationResponseOption(
                  code: code,
                  ordinalValue: ordinal,
                  labels: {
                    'th': longLabels
                        ? '$th รายละเอียดตัวเลือกสำหรับทดสอบการตัดบรรทัดบนหน้าจอขนาดเล็ก'
                        : th,
                    'en': longLabels
                        ? '$en with a long description to exercise wrapping on a narrow screen'
                        : en,
                  },
                ),
            ],
          ),
    ],
  ),
  state: MotivationMeasurementRunState.started,
  startedAtUtc: DateTime.utc(2026, 9, 5),
  responses: const [],
);

MotivationMeasurementRun _record(
  MotivationMeasurementRun run,
  String itemId,
  String code,
) => MotivationMeasurementRun(
  id: run.id,
  ownerId: run.ownerId,
  permitId: run.permitId,
  assignmentId: run.assignmentId,
  instrument: run.instrument,
  state: run.state,
  startedAtUtc: run.startedAtUtc,
  closedAtUtc: run.closedAtUtc,
  firstExposureAtUtc: run.firstExposureAtUtc,
  indexCompletionAtUtc: run.indexCompletionAtUtc,
  responses: [
    ...run.responses,
    RecordedMotivationResponse(
      itemId: itemId,
      responseCode: code,
      ordinalValue: run.instrument.response(itemId, code).ordinalValue,
      answeredAtUtc: DateTime.utc(2026, 9, 5, 0, 1),
    ),
  ],
);
