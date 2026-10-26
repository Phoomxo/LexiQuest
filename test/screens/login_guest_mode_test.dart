import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
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
const googleSignInButtonKey = ValueKey<String>('google-sign-in-button');
const loginBrandMarkKey = ValueKey<String>('login-brand-mark');
const accountErrorKey = ValueKey<String>('account-error');

Widget _loginHarness({
  required GuestSessionService guestSessionService,
  ResearchConsentUseCases? researchConsent,
  AccountUseCases? account,
}) {
  return MaterialApp(
    initialRoute: '/login',
    routes: <String, WidgetBuilder>{
      '/login': (context) => LoginScreen(
        guestSessionService: guestSessionService,
        researchConsent: researchConsent,
        account: account,
      ),
      '/home': (context) =>
          const Scaffold(body: Center(child: Text('HOME_SCREEN_REACHED'))),
    },
  );
}

void main() {
  testWidgets('login brand mark is specific and labeled for assistive tech', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _loginHarness(guestSessionService: _CompleterGuestSessionService()),
      );

      final mark = find.byKey(loginBrandMarkKey);
      expect(mark, findsOneWidget);
      expect(
        tester.getSemantics(mark).getSemanticsData().label,
        'สัญลักษณ์ LexiQuest',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tablet keeps the login form centered within 560dp', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _loginHarness(guestSessionService: _CompleterGuestSessionService()),
    );
    await tester.pumpAndSettle();

    final emailField = tester.getRect(find.byType(TextField).first);
    expect(emailField.width, lessThanOrEqualTo(560));
    expect(emailField.center.dx, closeTo(640, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('research consent stays within 600dp on tablet', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final consent = ResearchConsentUseCases(
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'tablet-consent-owner',
        nowUtc: () => DateTime.utc(2026, 10, 24),
      ),
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 10, 24),
    );

    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        researchConsent: consent,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AlertDialog)).width,
      lessThanOrEqualTo(600),
    );
    expect(find.text('ยังไม่ยินยอม').hitTestable(), findsOneWidget);
    expect(find.text('ยินยอมเข้าร่วม').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login and research choice stay reachable at 200 percent text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final consent = ResearchConsentUseCases(
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'large-text-consent-owner',
        nowUtc: () => DateTime.utc(2026, 10, 24),
      ),
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 10, 24),
    );
    final account = AccountUseCases(
      gateway: _LoginAccountGateway(googleAvailable: true),
      owners: _MutableOwners(_owner('large-text-owner')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _loginHarness(
          guestSessionService: _CompleterGuestSessionService(),
          researchConsent: consent,
          account: account,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(googleSignInButtonKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final googleButton = find.byKey(googleSignInButtonKey);
    final googleLabel = find.descendant(
      of: googleButton,
      matching: find.text('ใช้บัญชี Google'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(googleLabel);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getRect(googleButton).contains(tester.getRect(googleLabel).center),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.byKey(guestModeButtonKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsOneWidget);
    expect(find.text('ยังไม่ยินยอม').hitTestable(), findsOneWidget);
    expect(find.text('ยินยอมเข้าร่วม').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty credentials show inline guidance before provider call', (
    tester,
  ) async {
    final gateway = _LoginAccountGateway();
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pump();

    expect(find.text('กรอกอีเมล'), findsOneWidget);
    expect(find.text('กรอกรหัสผ่าน'), findsOneWidget);
    expect(gateway.signInCalls, 0);
  });

  testWidgets('password reset validates email inside the dialog', (
    tester,
  ) async {
    final gateway = _LoginAccountGateway();
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    await tester.tap(find.text('ลืมรหัสผ่าน'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ส่งลิงก์'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('กรอกอีเมล'), findsOneWidget);
    expect(gateway.passwordResetEmails, isEmpty);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'ส่งลิงก์'));
    await tester.pump();
    expect(find.text('ตรวจสอบรูปแบบอีเมล'), findsOneWidget);
    expect(gateway.passwordResetEmails, isEmpty);

    await tester.enterText(
      find.byType(TextFormField),
      ' Student@Example.Test ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ส่งลิงก์'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.passwordResetEmails, ['student@example.test']);
  });

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
      final database = db.AppDatabase(NativeDatabase.memory());
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
      expect(status.decidedAtUtc, isNull);
      expect(status.withdrawnAtUtc, isNull);
      expect(await database.select(database.researchConsents).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);

      service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
      await tester.pumpAndSettle();
      expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
    },
  );

  testWidgets('A dialog acceptance cannot be retargeted to B', (tester) async {
    final owners = _MutableOwners(_owner('owner-a'));
    final repository = _RecordingConsentRepository();
    final consent = ResearchConsentUseCases(
      owners: owners,
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(
      _loginHarness(guestSessionService: service, researchConsent: consent),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsOneWidget);
    owners.current = _owner('owner-b');
    await tester.tap(find.text('ยินยอมเข้าร่วม'));
    await tester.pump();

    expect(repository.decisions, isEmpty);
    expect(service.startCalls, 1);
    expect(
      find.textContaining('ไม่ได้บันทึกความยินยอมการวิจัย'),
      findsOneWidget,
    );
    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
  });

  testWidgets('research read failure is fail closed and still starts guest', (
    tester,
  ) async {
    final repository = _RecordingConsentRepository()
      ..loadError = StateError('private-sentinel');
    final consent = ResearchConsentUseCases(
      owners: _MutableOwners(_owner('owner-a')),
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final service = _CompleterGuestSessionService();
    await tester.pumpWidget(
      _loginHarness(guestSessionService: service, researchConsent: consent),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(guestModeButtonKey));
    await tester.pump();

    expect(repository.decisions, isEmpty);
    expect(service.startCalls, 1);
    expect(
      find.textContaining('ไม่ได้บันทึกความยินยอมการวิจัย'),
      findsOneWidget,
    );
    expect(find.textContaining('private-sentinel'), findsNothing);

    service.complete(const GuestSessionStarted(uid: 'guest-uid-123'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
  });

  testWidgets('research read failure does not block verified sign in', (
    tester,
  ) async {
    final owners = _MutableOwners(_owner('owner-a'));
    final repository = _RecordingConsentRepository()
      ..loadError = StateError('private-sentinel');
    final consent = ResearchConsentUseCases(
      owners: owners,
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final account = AccountUseCases(
      gateway: _LoginAccountGateway(),
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        researchConsent: consent,
        account: account,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'student@example.test',
    );
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();

    expect(repository.decisions, isEmpty);
    expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้บันทึกความยินยอมการวิจัย'),
      findsOneWidget,
    );
    expect(find.textContaining('private-sentinel'), findsNothing);
  });

  testWidgets('Google option is hidden when production capability is off', (
    tester,
  ) async {
    final account = AccountUseCases(
      gateway: _LoginAccountGateway(),
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    expect(find.byKey(googleSignInButtonKey), findsNothing);
  });

  testWidgets('Google busy guard opens one flow and routes verified user', (
    tester,
  ) async {
    final gateway = _LoginAccountGateway(googleAvailable: true);
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    await tester.tap(find.byKey(googleSignInButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(googleSignInButtonKey), warnIfMissed: false);
    expect(gateway.googleCalls, 1);

    gateway.googleCompleter.complete(
      const AccountSession(
        uid: 'google-user',
        email: 'google@example.test',
        isAnonymous: false,
        emailVerified: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN_REACHED'), findsOneWidget);
  });

  testWidgets('Google cancellation stays on login without leaking details', (
    tester,
  ) async {
    final gateway = _LoginAccountGateway(
      googleAvailable: true,
      googleFailure: const AccountException(AccountFailureCode.cancelled),
    );
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    await tester.tap(find.byKey(googleSignInButtonKey));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('ยกเลิกรายการแล้ว'), findsOneWidget);
    expect(find.textContaining('secret-token-sentinel'), findsNothing);
  });

  testWidgets('Google provider failure stays inline until the user acts', (
    tester,
  ) async {
    final gateway = _LoginAccountGateway(
      googleAvailable: true,
      googleFailure: const AccountException(AccountFailureCode.network),
    );
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      _loginHarness(
        guestSessionService: _CompleterGuestSessionService(),
        account: account,
      ),
    );

    await tester.tap(find.byKey(googleSignInButtonKey));
    await tester.pump();

    expect(find.byKey(accountErrorKey), findsOneWidget);
    expect(find.text('ไม่สามารถเชื่อมต่อเครือข่ายได้'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.enterText(
      find.byType(TextField).first,
      'student@example.test',
    );
    await tester.pump();
    expect(find.byKey(accountErrorKey), findsNothing);
  });

  testWidgets('password failure is announced inline and reset clears it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _LoginAccountGateway(
      signInFailure: const AccountException(
        AccountFailureCode.invalidCredential,
      ),
    );
    final account = AccountUseCases(
      gateway: gateway,
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    try {
      await tester.pumpWidget(
        _loginHarness(
          guestSessionService: _CompleterGuestSessionService(),
          account: account,
        ),
      );

      await tester.enterText(
        find.byType(TextField).first,
        'student@example.test',
      );
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
      await tester.pumpAndSettle();

      final error = find.byKey(accountErrorKey);
      expect(error, findsOneWidget);
      expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
      expect(tester.widget<Semantics>(error).properties.liveRegion, isTrue);
      final semanticsData = tester.getSemantics(error).getSemanticsData();
      expect(semanticsData.label, contains('อีเมลหรือรหัสผ่านไม่ถูกต้อง'));

      await tester.tap(find.text('ลืมรหัสผ่าน'));
      await tester.pumpAndSettle();
      expect(find.byKey(accountErrorKey), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'ส่งลิงก์'));
      await tester.pumpAndSettle();
      expect(gateway.passwordResetEmails, ['student@example.test']);
      expect(find.byKey(accountErrorKey), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('provider recovery stays readable at 200 percent text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final account = AccountUseCases(
      gateway: _LoginAccountGateway(
        googleAvailable: true,
        googleFailure: const AccountException(AccountFailureCode.network),
      ),
      owners: _MutableOwners(_owner('owner-a')),
      upgradeGuestOwner: UpgradeGuestOwner(_LoginUpgrades()),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _loginHarness(
          guestSessionService: _CompleterGuestSessionService(),
          account: account,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(googleSignInButtonKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(googleSignInButtonKey));
    await tester.pumpAndSettle();

    final message = find.descendant(
      of: find.byKey(accountErrorKey),
      matching: find.text('ไม่สามารถเชื่อมต่อเครือข่ายได้'),
    );
    expect(message.hitTestable(), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

LocalOwner _owner(String id) =>
    LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 10, 21));

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.current);

  LocalOwner current;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _RecordingConsentRepository implements ResearchConsentRepository {
  final List<(String, bool)> decisions = [];
  Object? loadError;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    if (loadError case final error?) throw error;
    return ResearchConsentStatus(
      ownerId: ownerId,
      version: version,
      accepted: false,
    );
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    decisions.add((ownerId, accepted));
    return true;
  }
}

final class _LoginAccountGateway
    implements AccountGateway, GoogleAccountGateway {
  _LoginAccountGateway({
    this.googleAvailable = false,
    this.googleFailure,
    this.signInFailure,
  });

  final bool googleAvailable;
  final Object? googleFailure;
  final Object? signInFailure;
  final Completer<AccountSession> googleCompleter = Completer<AccountSession>();
  int googleCalls = 0;
  int signInCalls = 0;
  final List<String> passwordResetEmails = [];

  @override
  bool get googleSignInAvailable => googleAvailable;

  @override
  AccountSession? currentSession;

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    if (signInFailure case final error?) throw error;
    currentSession = AccountSession(
      uid: 'signed-user',
      email: email,
      isAnonymous: false,
      emailVerified: true,
    );
    return currentSession!;
  }

  @override
  Future<AccountSession> signInWithGoogle() async {
    googleCalls++;
    if (googleFailure case final error?) throw error;
    currentSession = await googleCompleter.future;
    return currentSession!;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> applyEmailVerificationCode(String code) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> reload() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetEmails.add(email);
  }

  @override
  Future<void> sendVerification() => throw UnimplementedError();

  @override
  Future<AccountSession> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}

final class _LoginUpgrades implements OwnerUpgradeRepository {
  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async => OwnerUpgradeResult(
    targetOwnerId: activeOwnerId,
    mode: OwnerUpgradeMode.anonymousBound,
    conflictCount: 0,
  );

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() =>
      throw UnimplementedError();

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) => throw UnimplementedError();
}
