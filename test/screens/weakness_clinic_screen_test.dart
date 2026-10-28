import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets(
    'WeaknessClinicScreen displays weakness items and practice button',
    (WidgetTester tester) async {
      final customItems = [
        SrsItem(
          word: 'ephemeral',
          boxLevel: 1,
          intervalDays: 1,
          lastReviewedAt: DateTime.now(),
          nextReviewAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: WeaknessClinicScreen(customItems: customItems)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('คลินิกซ่อมแซมจุดอ่อน (Weakness Clinic)'),
        findsOneWidget,
      );
      expect(find.text('ephemeral'), findsOneWidget);
      expect(find.text('เริ่มฝึกซ่อมจุดอ่อนทันที'), findsOneWidget);
    },
  );
}
