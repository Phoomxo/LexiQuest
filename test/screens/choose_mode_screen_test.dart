import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets('active home replaces progress without retaining the old owner', (
    tester,
  ) async {
    final ownerB = Completer<ProgressSnapshot>();
    var ownerBReads = 0;
    Future<ProgressSnapshot> loadA() async => snapshot(
      due: 1,
      nextDueSpelling: 'private-a',
      nextDueCategoryName: 'Owner A',
    );
    Future<ProgressSnapshot> loadB() {
      ownerBReads++;
      return ownerB.future;
    }

    Widget home(ProgressLoader loader) =>
        MaterialApp(home: ChooseModeScreen(loader: loader));
    await tester.pumpWidget(home(loadA));
    await tester.pumpAndSettle();
    expect(find.text('private-a'), findsOneWidget);
    await tester.pumpWidget(home(loadB));
    await tester.pump();
    expect(ownerBReads, 1);
    expect(find.text('private-a'), findsNothing);
    expect(find.text('จากชุด Owner A'), findsNothing);
    expect(find.text('ฝึกคำที่ตอบผิด'), findsNothing);
    ownerB.complete(snapshot(empty: true));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsOneWidget);
  });

  testWidgets('late progress from the old owner cannot replace the new owner', (
    tester,
  ) async {
    final ownerA = Completer<ProgressSnapshot>();
    Future<ProgressSnapshot> loadA() => ownerA.future;
    Future<ProgressSnapshot> loadB() async => snapshot(empty: true);
    Widget home(ProgressLoader loader) =>
        MaterialApp(home: ChooseModeScreen(loader: loader));
    await tester.pumpWidget(home(loadA));
    await tester.pumpWidget(home(loadB));
    await tester.pump();
    expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsOneWidget);
    ownerA.complete(snapshot(due: 1, nextDueSpelling: 'private-a'));
    await tester.pumpAndSettle();
    expect(find.text('private-a'), findsNothing);
    expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsOneWidget);
  });

  testWidgets('refresh hides activities from the previous progress read', (
    tester,
  ) async {
    final refreshed = Completer<ProgressSnapshot>();
    var reads = 0;
    Future<ProgressSnapshot> load() =>
        reads++ == 0 ? Future.value(snapshot()) : refreshed.future;
    Widget home(bool active) => MaterialApp(
      home: ChooseModeScreen(loader: load, isActive: active),
    );
    await tester.pumpWidget(home(true));
    await tester.pumpAndSettle();
    expect(find.text('ฝึกคำที่ตอบผิด'), findsOneWidget);
    await tester.pumpWidget(home(false));
    await tester.pumpWidget(home(true));
    await tester.pump();
    expect(find.text('ฝึกคำที่ตอบผิด'), findsNothing);
    refreshed.complete(snapshot(empty: true));
    await tester.pumpAndSettle();
    expect(find.text('ฝึกคำที่ตอบผิด'), findsNothing);
  });

  testWidgets('home offers set practice and omits errors without evidence', (
    tester,
  ) async {
    var openedLibrary = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(empty: true, words: 3, due: 1),
          onOpenLibrary: () => openedLibrary = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ฝึกคำที่ตอบผิด'), findsNothing);
    expect(find.text('ฝึกจุดอ่อน'), findsNothing);
    final action = find.text('ฝึกจากชุดคำ');
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(openedLibrary, isTrue);
  });

  testWidgets(
    'due preview identifies its actual set without an invented example',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async => snapshot(
              due: 1,
              nextDueSpelling: 'platform',
              nextDueCategoryName: 'การเดินทาง',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('จากชุด การเดินทาง'), findsOneWidget);
      expect(find.text('Meet me on platform two.'), findsNothing);
      expect(find.text('ชานชาลา'), findsNothing);
    },
  );

  testWidgets('hub prioritizes due review and displays real queue counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ChooseModeScreen(loader: () async => snapshot(due: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ทบทวน 3 คำ'), findsOneWidget);
    expect(find.text('ถึงเวลาทบทวน 3 คำ'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ดูแบบฝึกทั้งหมด'), 200);
    await tester.tap(find.text('ดูแบบฝึกทั้งหมด'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกวิธีฝึก'), findsOneWidget);
    expect(find.text('ฝึกคำศัพท์'), findsOneWidget);
    expect(find.text('ฝึกคำแปล แล้วดูคำที่ควรทบทวน'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('เลือกวิธีฝึก'), findsNothing);
  });

  testWidgets(
    'hub keeps extra practice reachable and refreshes due words on return',
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
      expect(find.text('ทบทวนครบแล้ว'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('ฝึกคำที่ตอบผิด'), 200);
      await tester.tap(find.text('ฝึกคำที่ตอบผิด'));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);
      due = 2;
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('ทบทวน 2 คำ'), -200);
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
      expect(find.text('ทบทวนครบแล้ว'), findsNothing);
      expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsNothing);
      await tester.tap(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(find.text('ทบทวน 2 คำ'), findsOneWidget);
    },
  );

  testWidgets('fresh owner reaches the library without an empty quiz', (
    tester,
  ) async {
    var libraryOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(empty: true),
          onOpenLibrary: () => libraryOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsOneWidget);
    expect(find.text('เริ่มฝึกคำศัพท์'), findsNothing);
    expect(find.textContaining('ถึงกำหนด 0 คำ'), findsNothing);
    expect(find.textContaining('คำที่ควรฝึก 0 คำ'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'เลือกชุดคำศัพท์'));
    expect(libraryOpened, isTrue);
  });

  testWidgets('saved vocabulary with no due words shows a completed queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(empty: true, words: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทบทวนครบแล้ว'), findsOneWidget);
    expect(find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'เลือกชุดคำศัพท์'),
      findsOneWidget,
    );
  });

  testWidgets('the first due word is shown without exposing its meaning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(due: 3, nextDueSpelling: 'station'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('station'), findsOneWidget);
    expect(find.text('สถานี'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'ทบทวนคำนี้'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'เลือกชุดคำศัพท์'), findsNothing);
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

    await tester.scrollUntilVisible(find.text('ดูแบบฝึกทั้งหมด'), 200);
    await tester.tap(find.text('ดูแบบฝึกทั้งหมด'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ภาพรวมการเรียน'), 200);
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

    await tester.tap(find.text('ดูแบบฝึกทั้งหมด'));
    await tester.pumpAndSettle();
    expect(find.text('ดูความก้าวหน้าจากคำตอบที่บันทึกไว้'), findsOneWidget);
  });
}

ProgressSnapshot snapshot({
  int due = 0,
  bool empty = false,
  int? words,
  String? nextDueSpelling,
  String? nextDueCategoryName,
}) => ProgressSnapshot(
  sampleSize: empty ? 0 : 3,
  correctCount: empty ? 0 : 1,
  wrongCount: empty ? 0 : 2,
  accuracy: empty ? null : 1 / 3,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: due,
  vocabularyWordCount: words ?? (empty ? 0 : 2),
  nextDueSpelling: nextDueSpelling,
  nextDueCategoryName: nextDueCategoryName,
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
