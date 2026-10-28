import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_result_view.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;

void main() {
  testWidgets('R15 first 5 of 6 stays separate from repair 1 of 1', (
    tester,
  ) async {
    final h = PairHarness(density: PairDensity.standard6);
    late PairMatchingHistoryProjection result;
    await tester.runAsync(() async {
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-1', PairTileSide.target);
      for (final i in [1, 2, 3, 4, 5, 0]) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await c.finish();
      result = PairMatchingHistoryProjection(
        (await DriftPairMatchingSessionPurposeReader(h.db).read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        )).snapshot!,
      );
      await h.db.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PairMatchingResultView(result: result)),
      ),
    );
    expect(find.text('คำตอบครั้งแรก 5/6'), findsOneWidget);
    expect(find.text('ฝึกซ้ำแก้คำตอบ 1/1'), findsOneWidget);
    expect(find.text('คำตอบครั้งแรก 6/6'), findsNothing);
    expect(result.result.stars, 2);
    await tester.pump();
    expect(find.text('คำตอบครั้งแรก 5/6'), findsOneWidget);
  });

  testWidgets(
    'result shows separate axes and explicit practice replay action',
    (tester) async {
      final h = PairHarness();
      late PairMatchingHistoryProjection result;
      await tester.runAsync(() async {
        await h.initialize();
        final c = await h.restore();
        for (var i = 0; i < 4; i++) {
          await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(c, 'synthetic-$i', PairTileSide.target);
        }
        await c.finish();
        result = PairMatchingHistoryProjection(
          (await DriftPairMatchingSessionPurposeReader(h.db).read(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
          )).snapshot!,
        );
        await h.db.close();
      });
      var replay = 0;
      var returned = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairMatchingResultView(
              result: result,
              onReturn: () => returned++,
              onPracticeReplay: () => replay++,
            ),
          ),
        ),
      );
      expect(find.text('จับคู่แล้ว 4 คู่'), findsOneWidget);
      expect(find.text('ทำได้เอง 4 คู่'), findsOneWidget);
      expect(find.text('ใช้ตัวช่วย 0 คู่'), findsOneWidget);
      expect(find.text('ดาว 3/3'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(3));
      expect(find.bySemanticsLabel('ดาว 3 จาก 3'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'กลับไปเรียนต่อ'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'ฝึกซ้ำชุดเดิม'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('กลับไปเรียนต่อ'));
      await tester.tap(find.text('กลับไปเรียนต่อ'));
      expect(returned, 1);
      expect(find.text('ไม่ได้จับเวลา'), findsOneWidget);
      expect(find.text('ไม่มีข้อมูลเวลาเรียนจริงครบทั้งรอบ'), findsOneWidget);
      expect(find.text('เวลาเล่น 0 วินาที'), findsNothing);
      await tester.ensureVisible(find.text('ฝึกซ้ำชุดเดิม'));
      await tester.tap(find.text('ฝึกซ้ำชุดเดิม'));
      expect(replay, 1);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final locale in [const Locale('th'), const Locale('en')]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: PairMatchingResultView(
                result: result,
                onReturn: () => returned++,
                locale: locale,
                onPracticeReplay: () => replay++,
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '320px and 200% text in ${locale.languageCode}',
        );
      }
      semantics.dispose();
    },
  );
}
