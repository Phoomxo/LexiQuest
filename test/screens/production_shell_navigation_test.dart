import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/email_action_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'guest-shell-test');
  }
}

final class _GuestEntryStateStore implements AppEntryStateStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> markGuest() async {}

  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

AppBootstrap _fileBackedBootstrap(String databasePath) {
  return AppBootstrap(
    initializeFirebase: () async => throw StateError('firebase unavailable'),
    initializeSupabase: () async => throw StateError('supabase unavailable'),
    loadConfig: () => throw StateError('backend config unavailable'),
    guestSessionService: _FakeGuestSessionService(),
    createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
    createEntryStateStore: () async => _GuestEntryStateStore(),
  );
}

const _drawerButtonKey = ValueKey<String>('legacy-drawer-button');
const _flutterTtsChannel = MethodChannel('flutter_tts');

AppDependencies _dependencies({
  bool ready = true,
  AppRoute initialRoute = AppRoute.home,
}) {
  final availability = ready
      ? RuntimeAvailability.ready
      : RuntimeAvailability.unavailable;
  return AppDependencies(
    initialRoute: initialRoute,
    runtimeStatus: AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: availability,
      supabase: availability,
      backends: availability,
    ),
    config: null,
    guestSessionService: _FakeGuestSessionService(),
  );
}

Future<void> _pumpHome(WidgetTester tester, {bool ready = true}) async {
  await tester.pumpWidget(MyApp(dependencies: _dependencies(ready: ready)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(_drawerButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(Drawer), findsOneWidget);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget did not appear after $maxPumps bounded pumps: $finder');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget remained after $maxPumps bounded pumps: $finder');
}

Future<void> _pumpUntilComplete(
  WidgetTester tester,
  Future<void> future, {
  int maxPumps = 250,
}) async {
  var completed = false;
  Object? failure;
  StackTrace? failureStackTrace;
  future.then<void>(
    (_) => completed = true,
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      completed = true;
    },
  );
  for (var index = 0; index < maxPumps && !completed; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (completed) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  if (!completed) {
    fail('Future did not complete after $maxPumps bounded pumps');
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStackTrace!);
  }
}

void main() {
  testWidgets('supported cold-start email action overrides bootstrap route', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'https://vocab-learning-app-219ef.firebaseapp.com/auth/action'
        '?mode=resetPassword&oobCode=abc123';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(EmailActionScreen), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });

  testWidgets('unsupported cold-start route uses bootstrap fallback', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/unsupported';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });

  testWidgets('signed-out bootstrap rejects cold-start /home', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/home';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(
      MyApp(dependencies: _dependencies(initialRoute: AppRoute.login)),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });

  testWidgets('cold-start email verification without args uses bootstrap', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/email-verification';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(OTPScreen), findsNothing);
  });

  testWidgets('/home resolves to the field-safe shell', (tester) async {
    await _pumpHome(tester);

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byKey(_drawerButtonKey), findsOneWidget);
  });

  testWidgets('field shell exposes all completed primary workspaces', (
    tester,
  ) async {
    await _pumpHome(tester);

    final destinations = tester
        .widgetList<NavigationDestination>(
          find.descendant(
            of: find.byType(MainNavigationScreen),
            matching: find.byType(NavigationDestination),
          ),
        )
        .toList();

    expect(destinations.map((destination) => destination.label), <String>[
      'คลังคำศัพท์',
      'เรียนรู้',
      'สถิติ',
      'จุดอ่อน',
      'รางวัล',
      'โปรไฟล์',
    ]);
  });

  testWidgets('field destinations switch the persistent IndexedStack', (
    tester,
  ) async {
    await _pumpHome(tester);

    final stackFinder = find.descendant(
      of: find.byType(MainNavigationScreen),
      matching: find.byType(IndexedStack),
    );
    final destinations = find.descendant(
      of: find.byType(MainNavigationScreen),
      matching: find.byType(NavigationDestination),
    );

    for (var index = 0; index < 6; index++) {
      await tester.tap(destinations.at(index));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<IndexedStack>(stackFinder).index, index);
    }
  });

  testWidgets('drawer keeps completed local features during cloud outage', (
    tester,
  ) async {
    await _pumpHome(tester, ready: false);
    await _openDrawer(tester);

    expect(find.text('คลังคำศัพท์'), findsWidgets);
    expect(find.text('ร้านค้า'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, contains('การเรียนในเครื่องยังใช้ได้'));
  });

  testWidgets('drawer vocabulary item keeps the category workspace selected', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.tap(find.text('คลังคำศัพท์').last);
    await tester.pumpAndSettle();

    expect(find.byType(CategoriesPage), findsOneWidget);
  });

  testWidgets('drawer settings item reaches SettingScreen', (tester) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.scrollUntilVisible(
      find.text('ตั้งค่า'),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('ตั้งค่า'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SettingScreen), findsOneWidget);
  });

  testWidgets(
    'resolved production Home creates vocabulary through the scoped dependency',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        _flutterTtsChannel,
        (_) async => 1,
      );
      final temporaryDirectory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          'lexiquest-production-shell-vocabulary-',
        ),
      ))!;
      final databasePath =
          '${temporaryDirectory.path}${Platform.pathSeparator}'
          'lexiquest.sqlite';
      AppDependencies? dependencies;

      try {
        final bootstrap = _fileBackedBootstrap(databasePath);
        dependencies = await bootstrap.initialize();
        expect(dependencies.initialRoute, AppRoute.home);

        await tester.pumpWidget(MyApp(dependencies: dependencies));
        await _pumpUntilFound(tester, find.byType(CategoriesPage));

        final vocabularyDestination = find
            .descendant(
              of: find.byType(MainNavigationScreen),
              matching: find.byType(NavigationDestination),
            )
            .first;
        await tester.tap(vocabularyDestination);
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byKey(const ValueKey('add-category')));
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('category-name-field')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('category-name-field')),
          'Travel',
        );
        await tester.tap(find.byKey(const ValueKey('save-category')));
        await _pumpUntilFound(tester, find.text('Travel'));

        await tester.tap(find.text('Travel'));
        await _pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<VocabListScreen>(find.byType(VocabListScreen))
              .vocabulary,
          isNull,
          reason:
              'Production vocabulary screens must resolve use cases from '
              'AppDependenciesScope instead of route-owned injection.',
        );

        await tester.tap(find.byTooltip('นำเข้าคำศัพท์'));
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('import-rows-field')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<AddMultipleWordsScreen>(
                find.byType(AddMultipleWordsScreen),
              )
              .importer,
          isNull,
          reason:
              'Production bulk-add routes must resolve ImportVocabulary from '
              'AppDependenciesScope instead of route-owned injection.',
        );
        await tester.pageBack();
        await _pumpUntilGone(
          tester,
          find.byKey(const ValueKey('import-rows-field')),
        );

        await tester.tap(find.byKey(const ValueKey('add-word')));
        await _pumpUntilFound(tester, find.byKey(const ValueKey('word-field')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester.widget<AddWordScreen>(find.byType(AddWordScreen)).vocabulary,
          isNull,
          reason:
              'Production add-word routes must resolve VocabularyUseCases '
              'from AppDependenciesScope instead of route-owned injection.',
        );
        await tester.enterText(
          find.byKey(const ValueKey('word-field')),
          'station',
        );
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'สถานี',
        );
        await tester.enterText(
          find.byKey(const ValueKey('part-of-speech-field')),
          'noun',
        );
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilGone(tester, find.byKey(const ValueKey('word-field')));
        await _pumpUntilFound(tester, find.text('station'));

        expect(find.text('station'), findsOneWidget);
        expect(find.textContaining('สถานี'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _pumpUntilComplete(
          tester,
          dependencies?.dispose() ?? Future<void>.value(),
        );
        await tester.runAsync(() async {
          if (await temporaryDirectory.exists()) {
            await temporaryDirectory.delete(recursive: true);
          }
        });
        binaryMessenger.setMockMethodCallHandler(_flutterTtsChannel, null);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
