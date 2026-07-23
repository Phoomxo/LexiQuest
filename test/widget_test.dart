import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    // Build LoginScreen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Verify the Login title appears
    expect(find.text('Login'), findsWidgets);

    // Verify Email and Password TextFields are present
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    // Verify the Login button
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

    // Verify the registration prompt
    expect(find.text('Don\'t have an account? Register here'), findsOneWidget);
  });
}
