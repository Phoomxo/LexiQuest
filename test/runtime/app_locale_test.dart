import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/learning_time_settings_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('Thai app and child routes stay Thai on an English device', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      MyApp(
        dependencies: AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _GuestSession(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('th'));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'ยกเลิก');

    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const LearningTimeSettingsScreen(
            time: null,
            expectedOwnerId: 'synthetic-locale-owner',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เวลาการเรียนในเครื่อง'), findsOneWidget);
    expect(find.text('บันทึกเวลาจากการโต้ตอบ'), findsOneWidget);
    expect(find.text('Local learning time'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('English component host retains its English copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LearningTimeSettingsScreen(
          time: null,
          expectedOwnerId: 'synthetic-locale-owner',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Local learning time'), findsOneWidget);
    expect(find.text('Record interaction time'), findsOneWidget);
    expect(find.text('เวลาการเรียนในเครื่อง'), findsNothing);
  });
}

class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-locale-owner');
}
