import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database_open_policy.dart';
import 'package:vocab_learning_app/runtime/local_storage_readiness_app.dart';

void main() {
  for (final error in AppDatabaseOpenError.values) {
    testWidgets(
      'storage readiness explains $error without a destructive action',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          LocalStorageReadinessApp(failure: AppDatabaseOpenException(error)),
        );
        expect(find.text('ยังเปิดข้อมูลการเรียนไม่ได้'), findsOneWidget);
        expect(
          find.text('แอปไม่ได้ลบหรือรีเซ็ตไฟล์ข้อมูลของคุณ'),
          findsOneWidget,
        );
        expect(find.byType(ElevatedButton), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
