import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/recall_ladder.dart';
import 'package:vocab_learning_app/features/learning/presentation/recall_ladder_panel.dart';

const _word = QuizWord(
  id: 'synthetic-word',
  categoryId: 'synthetic-category',
  spelling: 'harbor',
  meaning: 'ท่าเรือ',
  partOfSpeech: 'noun',
  contentRevision: 'local-vocabulary-v1:1',
);

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'recall suggestion fits 320px 200 percent ${dark ? 'dark' : 'light'} and preserves manual keyboard choice',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final owners = StreamController<String?>.broadcast(sync: true);
        final reader = _Reader();
        final chosen = <RecallLadderStage>[];
        try {
          await tester.pumpWidget(
            _app(
              RecallLadderPanel(
                reader: reader,
                ownerId: 'synthetic-owner',
                ownerChanges: owners.stream,
                onPractice: (stage, word) async {
                  expect(word.id, _word.id);
                  chosen.add(stage);
                },
              ),
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(FilledButton), findsOneWidget);
          expect(find.byType(OutlinedButton), findsNothing);
          final details = find.byKey(const ValueKey('recall-ladder-details'));
          await tester.ensureVisible(details);
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(
            find.text('เป็นคำแนะนำกิจกรรม ไม่ใช่ระดับความชำนาญ'),
            findsOneWidget,
          );
          expect(find.text('แนะนำ: จับคู่คำศัพท์'), findsOneWidget);
          expect(reader.reads, 1);
          final target = find.byKey(const ValueKey('recall-ladder-dictation'));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await _keyboard(tester, target);
          await tester.pumpAndSettle();
          expect(chosen, [RecallLadderStage.dictation]);
          expect(reader.reads, greaterThanOrEqualTo(2));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await owners.close();
        }
      },
    );
  }

  testWidgets(
    'owner ABA while revalidating prevents a retained practice callback',
    (tester) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      final reader = _Reader();
      var launches = 0;
      try {
        await tester.pumpWidget(
          _app(
            RecallLadderPanel(
              reader: reader,
              ownerId: 'synthetic-owner',
              ownerChanges: owners.stream,
              onPractice: (_, _) async => launches++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retained = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('recall-ladder-suggested')),
            )
            .onPressed!;
        reader.pending = Completer<RecallLadderSnapshot>();
        retained();
        await tester.pump();
        owners.add('synthetic-other-owner');
        owners.add('synthetic-owner');
        reader.pending!.complete(reader.snapshot);
        await tester.pumpAndSettle();
        expect(launches, 0);
        expect(
          find.text('คำอ้างอิง: harbor', skipOffstage: false),
          findsNothing,
        );
        retained();
        await tester.pumpAndSettle();
        expect(launches, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await owners.close();
      }
    },
  );

  testWidgets(
    'source revision changes before launch and unavailable modes remain truthful',
    (tester) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      final reader = _Reader();
      var launches = 0;
      try {
        await tester.pumpWidget(
          _app(
            RecallLadderPanel(
              reader: reader,
              ownerId: 'synthetic-owner',
              ownerChanges: owners.stream,
              canPractice: (stage, _) => stage != RecallLadderStage.speaking,
              onPractice: (_, _) async => launches++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('recall-ladder-details')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('recall-ladder-speaking')),
              )
              .onPressed,
          isNull,
        );
        final retained = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('recall-ladder-suggested')),
            )
            .onPressed!;
        reader.snapshot = RecallLadderSnapshot(
          ownerId: 'synthetic-owner',
          word: const QuizWord(
            id: 'synthetic-word',
            categoryId: 'synthetic-category',
            spelling: 'harbor',
            meaning: 'updated',
            partOfSpeech: 'noun',
            contentRevision: 'local-vocabulary-v1:2',
          ),
          observations: const [],
        );
        retained();
        await tester.pumpAndSettle();
        expect(launches, 0);
        if (find
            .text('ยังไม่พบหลักฐานที่ใช้ได้ในรายการล่าสุด')
            .evaluate()
            .isEmpty) {
          await tester.tap(find.byKey(const ValueKey('recall-ladder-details')));
          await tester.pumpAndSettle();
        }
        expect(
          find.text('ยังไม่พบหลักฐานที่ใช้ได้ในรายการล่าสุด'),
          findsOneWidget,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await owners.close();
      }
    },
  );
}

Widget _app(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

final class _Reader implements RecallLadderReader {
  var reads = 0;
  Completer<RecallLadderSnapshot>? pending;
  RecallLadderSnapshot snapshot = RecallLadderSnapshot(
    ownerId: 'synthetic-owner',
    word: _word,
    observations: [
      RecallLadderObservation.fromEvidence(
        attemptId: 'synthetic-answer',
        promptMode: 'meaningChoice',
        isCorrect: true,
        occurredAtUtc: DateTime.utc(2026, 11, 1),
        context: EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.recognition,
          skillId: 'meaning-recall',
          hintLevel: 0,
          contentRevision: _word.contentRevision!,
          rolloutMode: EvidencePolicyRolloutMode.legacy,
        ),
      )!,
    ],
  );
  @override
  Future<RecallLadderSnapshot> load({
    required String expectedOwnerId,
    String? wordId,
    required bool Function() stillCurrent,
  }) async {
    reads++;
    if (!stillCurrent()) throw StateError('Synthetic scope changed');
    final value = pending == null ? snapshot : await pending!.future;
    if (!stillCurrent()) throw StateError('Synthetic scope changed');
    return value;
  }
}

Future<void> _keyboard(WidgetTester tester, Finder target) async {
  for (var step = 0; step < 30; step++) {
    final element = target.evaluate().single;
    final context = FocusManager.instance.primaryFocus?.context;
    var within = identical(context, element);
    context?.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) {
        within = true;
        return false;
      }
      return true;
    });
    if (within) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('A manual recall activity is not keyboard reachable');
}
