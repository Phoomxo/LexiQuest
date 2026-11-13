import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  Future<void> render(
    WidgetTester tester,
    Widget screen, {
    double scale = 1.8,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'NotoSansThai'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('learning hub fits compact screens with large Thai text', (
    tester,
  ) async {
    await render(tester, ChooseModeScreen(loader: () async => _progress));
    expect(find.text('ทบทวน 3 คำ').hitTestable(), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/learning_hub_large_text.png'),
    );
    await tester.scrollUntilVisible(find.text('ฝึกจุดอ่อน'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weakness actions fit compact screens with large Thai text', (
    tester,
  ) async {
    await render(tester, WeaknessClinicScreen(loader: () async => _progress));
    expect(find.text('ฝึกคำที่ผิด (1)').hitTestable(), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/weakness_large_text.png'),
    );
  });

  testWidgets('score can scroll to next action with large Thai text', (
    tester,
  ) async {
    await render(
      tester,
      ScoreScreen(
        correctAnswers: 1,
        wrongAnswers: 1,
        mistakes: const [_word],
        onPracticeMistakes: () {},
      ),
    );
    expect(
      find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'กลับไปเลือกกิจกรรม'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/score_large_text.png'),
    );
    await tester.scrollUntilVisible(find.text('ฝึกคำที่ผิด (1)'), 200);
    expect(find.text('ฝึกคำที่ผิด (1)').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('score and weakness retain actionable non-color labels at 2x', (
    tester,
  ) async {
    await render(
      tester,
      ScoreScreen(
        correctAnswers: 1,
        wrongAnswers: 1,
        mistakes: const [_word],
        onPracticeMistakes: () {},
      ),
      scale: 2,
    );
    expect(find.text('ตอบผิด'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ฝึกคำที่ผิด (1)'), 150);
    expect(find.text('ฝึกคำที่ผิด (1)').hitTestable(), findsOneWidget);
    await render(
      tester,
      WeaknessClinicScreen(loader: () async => _progress),
      scale: 2,
    );
    expect(find.textContaining('ตอบผิด 2/3'), findsOneWidget);
    expect(find.text('ฝึกคำที่ผิด (1)').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _word = QuizWord(
  id: 'synthetic-1',
  categoryId: 'synthetic-category',
  spelling: 'station',
  meaning: 'สถานีรถไฟและจุดจอดรับส่งผู้โดยสาร',
  partOfSpeech: 'noun',
);
const _progress = ProgressSnapshot(
  sampleSize: 3,
  correctCount: 1,
  wrongCount: 2,
  accuracy: 1 / 3,
  totalXp: 0,
  completedSessions: 1,
  streakDays: 0,
  dueReviewCount: 3,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  recommendations: [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'synthetic-1',
      spelling: 'station',
      meaning: 'สถานีรถไฟและจุดจอดรับส่งผู้โดยสาร',
      sampleSize: 3,
      incorrectCount: 2,
      errorRate: 2 / 3,
      dueAtUtc: null,
    ),
  ],
);
