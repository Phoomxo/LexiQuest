import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/presentation/study_presentations.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  testWidgets('standard mission is explicit and uses supplied copy', (
    tester,
  ) async {
    var starts = 0;
    await _mount(
      tester,
      presentation: TodayExperiencePresentation.standard,
      onStart: () async {
        starts++;
      },
    );
    expect(starts, 0);
    expect(
      find.byKey(const ValueKey('study-standard-mission')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('study-adventure-node')), findsNothing);
    expect(find.text(_catalog.title('th')), findsOneWidget);
    expect(find.text(_catalog.description('th')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('study-mission-start')));
    await tester.pump();
    expect(starts, 1);
  });

  testWidgets('adventure node opens its real mission detail before starting', (
    tester,
  ) async {
    var starts = 0;
    await _mount(
      tester,
      presentation: TodayExperiencePresentation.adventure,
      onStart: () async {
        starts++;
      },
    );
    expect(starts, 0);
    expect(find.byKey(const ValueKey('study-standard-mission')), findsNothing);
    expect(find.byKey(const ValueKey('study-mission-start')), findsNothing);
    final node = find.byKey(const ValueKey('study-adventure-node'));
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(find.text(_catalog.description('th')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('study-mission-start')),
    );
    await tester.tap(find.byKey(const ValueKey('study-mission-start')));
    await tester.pumpAndSettle();
    expect(starts, 1);
    await tester.ensureVisible(find.text('กลับไปยังแผนที่'));
    await tester.tap(find.text('กลับไปยังแผนที่'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-mission-start')), findsNothing);
    expect(tester.widget<FilledButton>(node).focusNode!.hasFocus, isTrue);
  });

  for (final presentation in TodayExperiencePresentation.values) {
    testWidgets('busy ${presentation.name} cannot start another mission', (
      tester,
    ) async {
      var starts = 0;
      Future<void> start() async {
        starts++;
      }

      await _mount(tester, presentation: presentation, onStart: start);
      if (presentation == TodayExperiencePresentation.adventure) {
        await tester.tap(find.byKey(const ValueKey('study-adventure-node')));
        await tester.pumpAndSettle();
      }
      await _mount(
        tester,
        presentation: presentation,
        onStart: start,
        busy: true,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('study-mission-start')),
      );
      expect(button.onPressed, isNull);
      expect(starts, 0);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  }

  testWidgets('continue label comes from the canonical active session', (
    tester,
  ) async {
    await _mount(
      tester,
      presentation: TodayExperiencePresentation.standard,
      index: _index('active'),
      onStart: () async {},
    );
    expect(find.text('ฝึกต่อรอบเดิม'), findsOneWidget);
    expect(find.text('กำลังฝึก'), findsOneWidget);
  });

  for (final state in ['completed', 'abandoned']) {
    testWidgets('terminal $state cannot launch a replacement', (tester) async {
      var starts = 0;
      await _mount(
        tester,
        presentation: TodayExperiencePresentation.standard,
        index: _index(state),
        onStart: () async {
          starts++;
        },
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('study-mission-start')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text(state == 'completed' ? 'จบภารกิจแล้ว' : 'รอบนี้หยุดแล้ว'),
        findsOneWidget,
      );
      expect(starts, 0);
    });
  }

  for (final language in ['th', 'en']) {
    for (final presentation in TodayExperiencePresentation.values) {
      testWidgets(
        '$language ${presentation.name} remains readable and reachable at 200 percent',
        (tester) async {
          tester.view
            ..physicalSize = const Size(360, 800)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            await _mount(
              tester,
              presentation: presentation,
              language: language,
              scale: 2,
              dark: true,
              onStart: () async {},
            );
            if (presentation == TodayExperiencePresentation.adventure) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('study-adventure-node')),
              );
              await tester.tap(
                find.byKey(const ValueKey('study-adventure-node')),
              );
              await tester.pumpAndSettle();
            }
            final start = find.byKey(const ValueKey('study-mission-start'));
            await tester.ensureVisible(start);
            expect(start.hitTestable(), findsOneWidget);
            expect(tester.getSize(start).height, greaterThanOrEqualTo(48));
            expect(find.text(_catalog.description(language)), findsOneWidget);
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

final _catalog = StudyPresentationCatalog(
  version: 'synthetic-presentation-v1',
  missionId: 'synthetic-mission',
  titles: const {
    'th': 'คำศัพท์สำหรับการเดินทางของคุณ',
    'en': 'Words for your journey',
  },
  descriptions: const {
    'th':
        'ทบทวนคำศัพท์จากเนื้อหาที่เตรียมไว้ เลือกคำแปลและใช้คำใบ้ได้ตามต้องการ',
    'en':
        'Review the supplied vocabulary. Choose the meaning and use a hint when needed.',
  },
  configuration: QuizConfiguration.category(
    categoryId: 'synthetic-category',
    limit: 1,
  ),
);

ConfiguredQuizState _index(String state) {
  final plan = AcceptedQuizPlan.create(
    configuration: _catalog.configuration,
    questions: [
      const QuizQuestion(
        word: QuizWord(
          id: 'synthetic-word',
          categoryId: 'synthetic-category',
          spelling: 'station',
          meaning: 'สถานี',
          partOfSpeech: 'noun',
          contentRevision: 'local-vocabulary-v1:1',
        ),
        options: ['สถานี'],
      ),
    ],
  );
  final end = DateTime.utc(2026, 10, 29, 12, 1);
  return ConfiguredQuizState(
    sessionId: 'synthetic-session',
    ownerId: 'synthetic-owner',
    activityType: 'quiz',
    startedAtUtc: DateTime.utc(2026, 10, 29, 12),
    appVersion: 'synthetic',
    buildId: 'synthetic',
    state: state,
    endedAtUtc: state == 'active' ? null : end,
    plan: plan,
    checkpointRevision: state == 'active' ? 1 : 4,
    checkpoint: state == 'active'
        ? QuizCheckpoint.initial(plan)
        : state == 'completed'
        ? CompletedQuizSession(
            planId: plan.id,
            questionOrdinal: 0,
            assistance: QuizAssistance(),
            close: QuizCloseReceipt(
              capturedOwnerId: 'synthetic-owner',
              endedAtUtcMs: end.millisecondsSinceEpoch,
            ),
          )
        : AbandonedQuizSession(
            planId: plan.id,
            questionOrdinal: 0,
            assistance: QuizAssistance(),
            close: QuizCloseReceipt(
              capturedOwnerId: 'synthetic-owner',
              endedAtUtcMs: end.millisecondsSinceEpoch,
            ),
          ),
  );
}

Future<void> _mount(
  WidgetTester tester, {
  required TodayExperiencePresentation presentation,
  required Future<void> Function() onStart,
  ConfiguredQuizState? index,
  bool busy = false,
  String language = 'th',
  double scale = 1,
  bool dark = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: StudyPresentations(
          key: const ValueKey('presentation'),
          catalog: _catalog,
          presentation: presentation,
          index: index,
          canStart: true,
          busy: busy,
          languageCode: language,
          onStart: onStart,
        ),
      ),
    ),
  ),
);
