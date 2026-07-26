import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';
import 'package:vocab_learning_app/screens/register_form_screen.dart';

void main() {
  group('Registration Flow End-to-End System Audit', () {
    testWidgets('RegisterScreen renders Thai labels and input fields cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('สมัครสมาชิก'), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('ส่งอีเมลยืนยัน (Send Email)'), findsOneWidget);
    });

    testWidgets('Submitting valid email and password navigates to OTPScreen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pumpAndSettle();

      // Enter valid email and password into TextFields
      await tester.enterText(
        find.byType(TextField).at(0),
        'student@example.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      // Tap submit button
      await tester.tap(find.text('ส่งอีเมลยืนยัน (Send Email)'));
      await tester.pumpAndSettle();

      // Verify navigation to OTPScreen
      expect(find.byType(OTPScreen), findsOneWidget);
      expect(find.textContaining('student@example.com'), findsOneWidget);
    });

    testWidgets(
      'OTPScreen allows student to proceed directly to RegisterFormScreen',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: OTPScreen(email: 'student@example.com')),
        );
        await tester.pumpAndSettle();

        expect(find.text('ยืนยันอีเมลของคุณ'), findsOneWidget);
        expect(find.textContaining('student@example.com'), findsOneWidget);

        // Tap confirmation button
        await tester.tap(
          find.widgetWithText(ElevatedButton, '✅ ฉันได้ยืนยันแล้ว'),
        );
        await tester.pumpAndSettle();

        // Verify navigation to RegisterFormScreen
        expect(find.byType(RegisterFormScreen), findsOneWidget);
      },
    );

    testWidgets(
      'RegisterFormScreen renders fields and completes registration',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            routes: {
              '/home': (context) =>
                  const Scaffold(body: Text('HOME_SCREEN_REACHED')),
            },
            home: const RegisterFormScreen(email: 'student@example.com'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('student@example.com'), findsOneWidget);

        // Fill in student profile information
        await tester.enterText(find.byType(TextField).at(0), 'น้องอนันต์');
        await tester.enterText(find.byType(TextField).at(1), 'ใจดี');
        await tester.enterText(find.byType(TextField).at(2), '10');

        // Tap submit registration button
        await tester.tap(find.text('สมัครสมาชิก'));
        await tester.pumpAndSettle();

        // Verify successful navigation to Home Screen
        expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
      },
    );
  });
}
