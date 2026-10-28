import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final screen in <Widget>[
      const LoginScreen(),
      const RegisterScreen(),
    ]) {
      testWidgets(
        '${screen.runtimeType} supports 200% text in ${brightness.name} mode',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: M3Theme.lightTheme,
              darkTheme: M3Theme.darkTheme,
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: screen,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsWidgets);
          final context = tester.element(find.byType(Scaffold));
          expect(Theme.of(context).brightness, brightness);
        },
      );
    }
  }
}
