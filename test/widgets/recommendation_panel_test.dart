import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/widgets/recommendation_panel.dart';

void main() {
  testWidgets('G4.1 old completion cannot unlock replacement action', (
    tester,
  ) async {
    final oldPending = Completer<void>();
    final currentPending = Completer<void>();
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _recommended,
          onActivitySelected: (_) => oldPending.future,
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _constrained,
          onActivitySelected: (_) => currentPending.future,
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    oldPending.complete();
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    currentPending.complete();
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('G4.1 launch failure is visible and retryable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _recommended,
          onActivitySelected: (_) async {
            if (++calls == 1) throw StateError('unavailable');
          },
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(
      find.text('ไม่สามารถเปิดกิจกรรมได้ กรุณาลองอีกครั้ง'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('G4.1 stale recommendation preserves manual alternatives', (
    tester,
  ) async {
    final selected = <LessonMode>[];
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: RecommendationPanelResult.recommended(
            ownerId: 'owner-1',
            mode: LessonMode.flashcard,
            reason: RecommendationPanelReason.staleEvidence,
            freshness: RecommendationEvidenceFreshness.stale,
            protocolConstraint: RecommendationProtocolConstraint.open,
            alternatives: const [LessonMode.meaningQuiz],
          ),
          onActivitySelected: (mode) async {
            selected.add(mode);
          },
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    await tester.tap(find.bySemanticsLabel('เลือกกิจกรรม Meaning quiz'));
    await tester.pump();
    expect(selected, [LessonMode.meaningQuiz]);
  });

  testWidgets('G4.1 rejects captured action after owner replacement', (
    tester,
  ) async {
    var calls = 0;
    Future<void> select(LessonMode _) async {
      calls++;
    }

    await tester.pumpWidget(
      _app(
        RecommendationPanel(result: _recommended, onActivitySelected: select),
      ),
    );
    final captured = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: RecommendationPanelResult.recommended(
            ownerId: 'owner-2',
            mode: LessonMode.typedRecall,
            reason: RecommendationPanelReason.weakEvidence,
            freshness: RecommendationEvidenceFreshness.current,
            protocolConstraint: RecommendationProtocolConstraint.open,
            alternatives: const [],
          ),
          onActivitySelected: select,
        ),
      ),
    );
    captured();
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('renders an explained recommendation with a typed action', (
    tester,
  ) async {
    LessonMode? selected;
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _recommended,
          onActivitySelected: (mode) async {
            selected = mode;
          },
        ),
      ),
    );

    expect(find.text('กิจกรรมถัดไป'), findsOneWidget);
    expect(find.text('Flashcard'), findsOneWidget);
    expect(find.text('แนะนำจากหลักฐานที่ยังใหม่'), findsOneWidget);
    expect(find.text('พบคำที่ควรทบทวนจากหลักฐานการฝึก'), findsOneWidget);
    expect(find.bySemanticsLabel('เริ่มกิจกรรม Flashcard'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('เริ่มกิจกรรม Flashcard'));
    await tester.pump();

    expect(selected, LessonMode.flashcard);
  });

  testWidgets('neutral stale state shows safe alternatives without a score', (
    tester,
  ) async {
    final selected = <LessonMode>[];
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _neutral,
          onActivitySelected: (mode) async {
            selected.add(mode);
          },
        ),
      ),
    );

    expect(find.text('หลักฐานเดิมเกินช่วงที่ใช้แนะนำได้'), findsOneWidget);
    expect(find.text('เลือกกิจกรรมที่พร้อมใช้งานได้'), findsOneWidget);
    expect(find.textContaining('คะแนนรวม'), findsNothing);
    expect(find.textContaining('ระดับความสามารถ'), findsNothing);

    await tester.tap(find.bySemanticsLabel('เลือกกิจกรรม Meaning quiz'));
    await tester.pump();

    expect(selected, [LessonMode.meaningQuiz]);
  });

  testWidgets('protocol lock is explicit and exposes only safe alternatives', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _protocolLocked,
          onActivitySelected: (_) async {},
        ),
      ),
    );

    expect(find.text('โปรโตคอลจำกัดกิจกรรมที่เลือกได้'), findsOneWidget);
    expect(find.text('Typed recall'), findsOneWidget);
    expect(find.text('Speaking'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
    'constrained recommendation explains protocol independently at 200 percent',
    (tester) async {
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: RecommendationPanel(
              result: _constrained,
              onActivitySelected: (_) async {},
            ),
          ),
        ),
      );

      expect(
        find.text('โปรโตคอลจำกัดกิจกรรมไว้ในขอบเขตที่อนุญาต'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('สถานะโปรโตคอล: จำกัดตามโปรโตคอล'),
        findsOneWidget,
      );
      expect(find.text('Flashcard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable state has no activity action', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        RecommendationPanel(
          result: _unavailable,
          onActivitySelected: (_) async {
            calls += 1;
          },
        ),
      ),
    );

    expect(find.text('ยังไม่มีกิจกรรมที่พร้อมใช้งาน'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(calls, 0);
  });

  testWidgets('remains semantic and usable at 200 percent text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: RecommendationPanel(
            result: _recommended,
            onActivitySelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('คำแนะนำกิจกรรมถัดไป'), findsOneWidget);
    expect(find.bySemanticsLabel('เริ่มกิจกรรม Flashcard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: Colors.indigo),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

final _recommended = RecommendationPanelResult.recommended(
  ownerId: 'owner-1',
  mode: LessonMode.flashcard,
  contentId: 'word-1',
  reason: RecommendationPanelReason.weakEvidence,
  freshness: RecommendationEvidenceFreshness.current,
  protocolConstraint: RecommendationProtocolConstraint.open,
  alternatives: const [LessonMode.meaningQuiz, LessonMode.typedRecall],
);

final _neutral = RecommendationPanelResult.neutral(
  ownerId: 'owner-1',
  reason: RecommendationPanelReason.staleEvidence,
  freshness: RecommendationEvidenceFreshness.stale,
  protocolConstraint: RecommendationProtocolConstraint.open,
  alternatives: const [LessonMode.meaningQuiz, LessonMode.typedRecall],
);

final _protocolLocked = RecommendationPanelResult.neutral(
  ownerId: 'owner-1',
  reason: RecommendationPanelReason.protocolLocked,
  freshness: RecommendationEvidenceFreshness.current,
  protocolConstraint: RecommendationProtocolConstraint.overrideDenied,
  alternatives: const [LessonMode.typedRecall],
);

final _constrained = RecommendationPanelResult.recommended(
  ownerId: 'owner-1',
  mode: LessonMode.flashcard,
  contentId: 'word-1',
  reason: RecommendationPanelReason.weakEvidence,
  freshness: RecommendationEvidenceFreshness.current,
  protocolConstraint: RecommendationProtocolConstraint.constrained,
  alternatives: const [LessonMode.typedRecall],
);

final _unavailable = RecommendationPanelResult.unavailable(
  ownerId: 'owner-1',
  reason: RecommendationPanelReason.noEligibleActivity,
  freshness: RecommendationEvidenceFreshness.missing,
  protocolConstraint: RecommendationProtocolConstraint.open,
);
