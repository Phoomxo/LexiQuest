import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';

void main() {
  testWidgets(
    'disabled shop does not load products or expose purchase controls',
    (tester) async {
      var loadCalls = 0;

      await tester.pumpWidget(
        MaterialApp(home: ShopPage(onLoadData: () async => loadCalls++)),
      );
      await tester.pump();

      expect(loadCalls, 0);
      expect(find.text('Shop is currently unavailable.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    },
  );
}
