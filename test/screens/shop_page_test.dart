import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';

void main() {
  testWidgets(
    'disabled shop does not load products or expose purchase controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ShopPage()));
      await tester.pump();

      expect(find.text('Shop is currently unavailable.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    },
  );
}
