import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _CompleterGuestSessionService implements GuestSessionService {
  final Completer<GuestSessionResult> _completer =
      Completer<GuestSessionResult>();

  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() {
    startCalls++;
    return _completer.future;
  }

  void complete(GuestSessionResult result) => _completer.complete(result);
}

const guestModeButtonKey = ValueKey<String>('guest-mode-button');

Widget _loginHarness({
  required GuestSessionService guestSessionService,
  ResearchConsentUseCases? researchConsent,
}) {
  return MaterialApp(
    initialRoute: '/login',
    routes: <String, WidgetBuilder>{
      '/login': (context) => LoginScreen(
        guestSessionService: guestSessionService,
        researchConsent: researchConsent,
      ),
      '/home': (context) =>
          const Scaffold(body: Center(child: Text('HOME_SCREEN_REACHED'))),
    },
  );
}

void main() {
  testWidgets('guest tap starts once and waits before navigating', (
    tester,
  ) async {
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(_loginHarness(guestSessionService: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pump();

    expect(service.startCalls, 1);
    expect(find.text('HOME_SCREEN_REACHED'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();
  });

  testWidgets('success replaces login with home', (tester) async {
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(_loginHarness(guestSessionService: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pump();
    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('failure stays on login and shows a safe SnackBar', (
    tester,
  ) async {
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(_loginHarness(guestSessionService: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pump();

    const failure = GuestSessionFailed(GuestSessionFailure.providerDisabled);
    service.complete(failure);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('HOME_SCREEN_REACHED'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);

    final visible = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join(' ');
    expect(visible, isNotEmpty);
    expect(visible, isNot(contains(failure.reason.name)));
    expect(visible, isNot(contains('GuestSessionFailed')));
  });

  testWidgets('repeated taps while pending start only once', (tester) async {
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(_loginHarness(guestSessionService: service));
    await tester.pumpAndSettle();

    final button = find.byKey(guestModeButtonKey);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button, warnIfMissed: false);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();

    expect(service.startCalls, 1);

    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();
  });

  testWidgets('completion after disposal does not throw or navigate', (
    tester,
  ) async {
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(_loginHarness(guestSessionService: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pump();
    expect(service.startCalls, 1);

    // Replace the entire MaterialApp so LoginScreen is genuinely unmounted,
    // rather than updating the existing Navigator with a different route map.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_SCREEN_REACHED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'declining research export still permits offline guest learning',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'consent-owner',
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final consent = ResearchConsentUseCases(
        owners: owners,
        repository: DriftResearchConsentRepository(database),
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      );
      final service = _CompleterGuestSessionService();
      await tester.pumpWidget(
        _loginHarness(guestSessionService: service, researchConsent: consent),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(guestModeButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่ยินยอม'), findsOneWidget);

      await tester.tap(find.text('ยังไม่ยินยอม'));
      await tester.pump();
      expect(service.startCalls, 1);

      final status = await consent.load();
      expect(status.accepted, isFalse);
      expect(status.withdrawnAtUtc, isNotNull);

      service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
      await tester.pumpAndSettle();
      expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
    },
  );
}
