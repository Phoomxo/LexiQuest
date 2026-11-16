import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets('hub prioritizes due review and displays real queue counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ChooseModeScreen(loader: () async => snapshot(due: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ทบทวน 3 คำ'), findsOneWidget);
    expect(find.text('ถึงกำหนด 3 คำ • คำที่ควรฝึก 1 คำ'), findsOneWidget);
    expect(find.text('ฝึกคำศัพท์'), findsOneWidget);
    expect(find.text('ฝึกคำแปล แล้วดูคำที่ควรทบทวน'), findsOneWidget);
    expect(find.text('ฝึกจากคลังคำศัพท์'), findsNothing);
  });

  testWidgets(
    'hub prioritizes weaknesses when nothing is due and refreshes on return',
    (tester) async {
      var calls = 0;
      var due = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async {
              calls++;
              return snapshot(due: due);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ฝึกคำที่ผิด 1 คำ'), findsOneWidget);
      await tester.tap(find.text('ฝึกคำที่ผิด 1 คำ'));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);
      due = 2;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ทบทวน 2 คำ'), findsOneWidget);
      expect(calls, greaterThanOrEqualTo(3));
    },
  );

  testWidgets(
    'hub recovers from a failed load without inventing queue counts',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async {
              if (calls++ == 0) throw StateError('synthetic read failure');
              return snapshot(due: 2);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final error = find.text('โหลดคำแนะนำการฝึกไม่สำเร็จ');
      expect(error, findsOneWidget);
      expect(
        find.ancestor(
          of: error,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('ทบทวน 2 คำ'), findsNothing);
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('ทบทวน 2 คำ'), findsOneWidget);
    },
  );

  testWidgets('fresh owner sees a quiz recommendation without fake progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(loader: () async => snapshot(empty: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เริ่มฝึกคำศัพท์'), findsOneWidget);
    expect(find.textContaining('ถึงกำหนด 0 คำ'), findsNothing);
    expect(find.textContaining('คำที่ควรฝึก 0 คำ'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('tablet centers the learning actions within 720dp', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(),
          featureRegistry: const BuildFieldFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final primaryAction = tester.getRect(find.byType(FilledButton).first);
    expect(primaryAction.width, lessThanOrEqualTo(720));
    expect(primaryAction.center.dx, closeTo(640, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading-only registry does not expose hidden practice modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(due: 3),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.reading: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทบทวน 3 คำ'), findsNothing);
    expect(find.text('เริ่มฝึกคำศัพท์'), findsNothing);
    expect(find.text('ฝึกคำศัพท์'), findsNothing);
    expect(find.text('ฝึกตามหมวดหมู่'), findsNothing);
    expect(find.text('ทบทวนคำศัพท์ที่ถึงกำหนด'), findsNothing);
    expect(find.text('ภาพรวมการเรียน'), findsNothing);
    expect(find.text('ฝึกจุดอ่อน'), findsNothing);
    expect(find.text('อ่านเรื่องสั้นและจำคำศัพท์'), findsOneWidget);
  });

  testWidgets('nested progress keeps the feature registry closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(due: 3),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.mastery: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ภาพรวมการเรียน'));
    await tester.pumpAndSettle();
    expect(find.byType(MasteryDashboardScreen), findsOneWidget);
    expect(find.text('คำที่ควรฝึกเพิ่ม'), findsNothing);
    expect(find.text('ความสำเร็จ'), findsNothing);
    expect(find.text('ร้านธีม'), findsNothing);
  });

  testWidgets('progress activity explains that it uses saved answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.mastery: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ดูความก้าวหน้าจากคำตอบที่บันทึกไว้'), findsOneWidget);
  });
}

ProgressSnapshot snapshot({int due = 0, bool empty = false}) =>
    ProgressSnapshot(
      sampleSize: empty ? 0 : 3,
      correctCount: empty ? 0 : 1,
      wrongCount: empty ? 0 : 2,
      accuracy: empty ? null : 1 / 3,
      totalXp: 0,
      completedSessions: 0,
      streakDays: 0,
      dueReviewCount: due,
      masteredWordCount: 0,
      achievementCount: 0,
      gameLevel: 1,
      skills: [],
      weaknesses: empty
          ? []
          : const [
              WeaknessEvidence(
                wordId: 'synthetic-1',
                spelling: 'station',
                meaning: 'สถานี',
                sampleSize: 3,
                incorrectCount: 2,
                errorRate: 2 / 3,
                dueAtUtc: null,
              ),
            ],
      recommendations: [],
    );
