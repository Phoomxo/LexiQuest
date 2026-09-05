import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_result_view.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;

void main() {
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairMatchingResultView(
              result: result,
              onPracticeReplay: () => replay++,
            ),
          ),
        ),
      );
      expect(find.text('จับคู่แล้ว 4 คู่'), findsOneWidget);
      expect(find.text('ทำได้เอง 4 คู่'), findsOneWidget);
      expect(find.text('ใช้ตัวช่วย 0 คู่'), findsOneWidget);
      expect(find.text('ดาว 3/3'), findsOneWidget);
      expect(find.text('ไม่ได้จับเวลา'), findsOneWidget);
      expect(find.text('เวลาเล่น 0 วินาที'), findsNothing);
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
    },
  );
}
