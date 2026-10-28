import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'device-autonomous-endurance-suite.dart' show waitForEnduranceTarget;

void main() {
  testWidgets('waits for entering route before exposing its controls', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 1200),
      pageBuilder: (_, _, _) => Scaffold(
        body: FilledButton(onPressed: () {}, child: const Text('เริ่มรอบใหม่')),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    navigator.currentState!.push(route);
    await tester.pump();
    await waitForEnduranceTarget(tester, find.text('เริ่มรอบใหม่'));
    expect(route.animation!.status, AnimationStatus.completed);
    expect(find.text('เริ่มรอบใหม่').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('waits for outgoing route before scrolling underlying page', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: ListView(children: const [Text('home list')])),
      ),
    );
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 1200),
      reverseTransitionDuration: const Duration(milliseconds: 1200),
      pageBuilder: (_, _, _) => const Scaffold(body: Text('child')),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await waitForEnduranceTarget(
      tester,
      find.text('home list'),
      requireHitTestable: true,
    );
    expect(find.text('child'), findsNothing);
    expect(find.text('home list').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
