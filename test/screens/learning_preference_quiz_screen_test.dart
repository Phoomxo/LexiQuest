import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/screens/learning_preference_quiz_screen.dart';

void main() {
  recoveryTests();
  testWidgets(
    'optional preferences separate draft and confirmed data across reconnect',
    (tester) async {
      final repository = _Preferences();
      final pending = Completer<void>();
      repository.beforeSave = pending;
      String? aiOwner;
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: LearningPreferenceQuizScreen(
              useCases: LearnerPreferencesUseCases(
                repository: repository,
                owners: _Owner(),
                nowUtc: () => DateTime.utc(2026, 9, 23),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
      aiOwner = 'local:preferences-screen';
      registry.invalidateSession(preserveContext: true);
      expect(_context(registry)['lastConfirmed']['minutes'], 20);
      await tester.enterText(find.byType(TextField), '45');
      tester
          .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
            find.byKey(const ValueKey('learning-preferences/goal')),
          )
          .onChanged!(LearnerPreferenceGoal.examPreparation);
      await tester.pump();
      expect(_context(registry)['draft']['minutes'], 45);
      expect(_context(registry)['draft']['goal'], 'examPreparation');
      expect(_context(registry)['lastConfirmed']['minutes'], 20);
      expect(_context(registry)['status'], 'editing');
      expect(repository.saveCount, 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('learning-preferences/save')),
      );
      await tester.tap(find.byKey(const ValueKey('learning-preferences/save')));
      await tester.pump();
      expect(_context(registry)['status'], 'saving');
      aiOwner = null;
      registry.invalidateSession(preserveContext: true);
      expect(registry.snapshot()['context'], isEmpty);
      pending.complete();
      await tester.pumpAndSettle();
      expect(repository.saveCount, 1);
      expect(repository.current.availableMinutesPerDay, 45);
      expect(registry.snapshot()['context'], isEmpty);
      aiOwner = 'local:preferences-screen';
      registry.invalidateSession(preserveContext: true);
      expect(_context(registry)['status'], 'saved');
      expect(_context(registry)['lastConfirmed']['minutes'], 45);
      expect(registry.snapshot()['actions'], isEmpty);
      aiOwner = 'another-owner';
      expect(registry.snapshot()['context'], isEmpty);
    },
  );

  testWidgets(
    'invalid and failed preference saves never claim confirmed draft',
    (tester) async {
      final repository = _Preferences();
      final registry = MenuActionRegistry(
        currentOwner: () => 'local:preferences-screen',
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: LearningPreferenceQuizScreen(
              useCases: LearnerPreferencesUseCases(
                repository: repository,
                owners: _Owner(),
                nowUtc: () => DateTime.utc(2026, 9, 23),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'private-invalid-text');
      await tester.ensureVisible(
        find.byKey(const ValueKey('learning-preferences/save')),
      );
      await tester.tap(find.byKey(const ValueKey('learning-preferences/save')));
      await tester.pump();
      expect(_context(registry)['status'], 'invalidDraft');
      expect(_context(registry)['draft']['minutes'], isNull);
      expect(
        _context(registry).toString(),
        isNot(contains('private-invalid-text')),
      );
      expect(repository.saveCount, 0);
      final pending = Completer<void>();
      repository.beforeSave = pending;
      await tester.enterText(find.byType(TextField), '60');
      await tester.ensureVisible(
        find.byKey(const ValueKey('learning-preferences/save')),
      );
      await tester.tap(find.byKey(const ValueKey('learning-preferences/save')));
      await tester.pump();
      pending.completeError(StateError('private failure detail'));
      await tester.pumpAndSettle();
      expect(_context(registry)['status'], 'saveFailed');
      expect(_context(registry)['lastConfirmed']['minutes'], 20);
      expect(_context(registry)['draft']['minutes'], 60);
      expect(
        _context(registry).toString(),
        isNot(contains('private failure detail')),
      );
      expect(repository.saveCount, 0);
    },
  );

  testWidgets(
    'leaving questionnaire skips unsaved edits and reopen loads saved values',
    (tester) async {
      final repository = _Preferences();
      final useCases = LearnerPreferencesUseCases(
        repository: repository,
        owners: _Owner(),
        nowUtc: () => DateTime.utc(2026, 9, 13),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LearningPreferenceQuizScreen(useCases: useCases),
                  ),
                ),
                child: const Text('Open preferences'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preferences'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '90');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repository.saveCount, 0);
      await tester.tap(find.text('Open preferences'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '20',
      );
      expect(repository.saveCount, 0);
    },
  );

  testWidgets(
    'old pending save is fenced before mutation after dependency replacement',
    (tester) async {
      final pending = Completer<void>();
      final first = _Preferences()..beforeSave = pending;
      final second = _Preferences();
      LearnerPreferencesUseCases cases(_Preferences repo) =>
          LearnerPreferencesUseCases(
            repository: repo,
            owners: _Owner(),
            nowUtc: () => DateTime.utc(2026, 9, 13),
          );
      await tester.pumpWidget(
        MaterialApp(home: LearningPreferenceQuizScreen(useCases: cases(first))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('learning-preferences/save')),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPreferenceQuizScreen(useCases: cases(second)),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(first.saveCount, 0);
      expect(second.saveCount, 0);
      expect(find.text('บันทึกการตั้งค่าการเรียนแล้ว'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('learning-preferences/save')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('owner switch cannot save choices from the previous owner', (
    tester,
  ) async {
    final repository = _Preferences();
    final owners = _Owner();
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: owners,
      nowUtc: () => DateTime.utc(2026, 9, 13),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pumpAndSettle();
    owners.id = 'local:second-owner';
    await tester.tap(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
    );
    await tester.pumpAndSettle();
    expect(repository.saveCount, 0);
    expect(repository.current.ownerId, 'local:preferences-screen');
  });

  testWidgets('late read cannot touch a disposed preferences form', (
    tester,
  ) async {
    final pending = Completer<LearnerPreferences>();
    final repository = _Preferences()..pendingRead = pending;
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 9, 13),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(repository.current);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('new dependency wins over an old pending preference read', (
    tester,
  ) async {
    final pending = Completer<LearnerPreferences>();
    final first = _Preferences()..pendingRead = pending;
    final second = _Preferences()
      ..current = LearnerPreferences(
        ownerId: 'local:preferences-screen',
        preferenceVersion: 2,
        goal: LearnerPreferenceGoal.examPreparation,
        availableMinutesPerDay: 45,
        activityPreference: LearnerActivityPreference.quiz,
        updatedAtUtc: DateTime.utc(2026, 9, 13),
      );
    LearnerPreferencesUseCases cases(_Preferences repo) =>
        LearnerPreferencesUseCases(
          repository: repo,
          owners: _Owner(),
          nowUtc: () => DateTime.utc(2026, 9, 13),
        );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: cases(first))),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: cases(second))),
    );
    await tester.pump();
    pending.complete(first.current);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '45');
  });

  testWidgets('device regression: preferences fit phone at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 833);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final useCases = LearnerPreferencesUseCases(
      repository: _Preferences(),
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 9, 10),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: LearningPreferenceQuizScreen(useCases: useCases),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final activity = find.byKey(
      const ValueKey('learning-preferences/activity-preference'),
    );
    await tester.ensureVisible(activity);
    await tester.tap(activity);
    await tester.pumpAndSettle();
    await tester.tap(find.text('แบบทดสอบ').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('f35 quiz edits goal time and activity without style labels', (
    tester,
  ) async {
    final repository = _Preferences();
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'การตั้งค่าการเรียน'), findsOneWidget);
    expect(find.text('balancedGrowth'), findsNothing);
    expect(find.text('mixedPractice'), findsNothing);
    expect(find.text('พัฒนาทักษะอย่างสมดุล'), findsWidgets);
    expect(find.textContaining('learning style'), findsNothing);
    expect(find.textContaining('personality'), findsNothing);
    final goal = tester.widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
      find.byKey(const ValueKey<String>('learning-preferences/goal')),
    );
    goal.onChanged!(LearnerPreferenceGoal.examPreparation);
    final activity = tester
        .widget<DropdownButtonFormField<LearnerActivityPreference>>(
          find.byKey(
            const ValueKey<String>('learning-preferences/activity-preference'),
          ),
        );
    activity.onChanged!(LearnerActivityPreference.quiz);
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('learning-preferences/available-minutes'),
      ),
      '45',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
    );
    await tester.pumpAndSettle();

    expect(repository.saveCount, 1);
    expect(repository.current.goal, LearnerPreferenceGoal.examPreparation);
    expect(repository.current.availableMinutesPerDay, 45);
    expect(
      repository.current.activityPreference,
      LearnerActivityPreference.quiz,
    );
    expect(find.text('บันทึกการตั้งค่าการเรียนแล้ว'), findsOneWidget);
  });

  testWidgets('f35 quiz rejects invalid time without mutating authority', (
    tester,
  ) async {
    final repository = _Preferences();
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        const ValueKey<String>('learning-preferences/available-minutes'),
      ),
      '0',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
    );
    await tester.pump();

    expect(repository.saveCount, 0);
    expect(find.text('กรุณาระบุเวลาตั้งแต่ 1 ถึง 240 นาที'), findsOneWidget);
  });

  testWidgets('f35 general constructor fails closed without dependency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LearningPreferenceQuizScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่พร้อมตั้งค่าการเรียน'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
      findsNothing,
    );
  });
}

final class _Preferences implements LearnerPreferencesRepository {
  LearnerPreferences current = LearnerPreferences.defaults(
    ownerId: 'local:preferences-screen',
    updatedAtUtc: DateTime.utc(2026, 8, 30),
  );
  int saveCount = 0;
  int readCount = 0;
  int failures = 0;
  bool throwSynchronously = false;
  bool failAcknowledgement = false;
  Future<void>? acknowledgement;
  Completer<void>? beforeSave;
  Completer<LearnerPreferences>? pendingRead;

  @override
  Future<LearnerPreferences> read(String ownerId) {
    readCount++;
    if (failures > 0) {
      failures--;
      if (throwSynchronously) throw StateError('private read failure');
      return Future.error(StateError('private read failure'));
    }
    return pendingRead?.future ?? Future.value(current);
  }

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (beforeSave != null) await beforeSave!.future;
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
    saveCount += 1;
    await acknowledgement;
    if (failAcknowledgement) throw StateError("ack lost");
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = LearnerPreferences(
      ownerId: current.ownerId,
      preferenceVersion: current.preferenceVersion,
      goal: current.goal,
      availableMinutesPerDay: current.availableMinutesPerDay,
      activityPreference: current.activityPreference,
      updatedAtUtc: current.updatedAtUtc,
      display: display,
    );
  }
}

final class _Owner implements LocalOwnerRepository {
  String id = 'local:preferences-screen';
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 8, 30));

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      getOrCreateActiveOwner();
}

Map<String, dynamic> _context(MenuActionRegistry registry) =>
    jsonDecode(
          (registry.snapshot()['context'] as List).single['value'] as String,
        )
        as Map<String, dynamic>;

LearnerPreferencesUseCases _cases(_Preferences repo, [_Owner? owner]) =>
    LearnerPreferencesUseCases(
      repository: repo,
      owners: owner ?? _Owner(),
      nowUtc: () => DateTime.utc(2026, 9, 24),
    );

void recoveryTests() {
  testWidgets(
    'AJ post save owner revalidation rejects retired acknowledgement',
    (tester) async {
      final ack = Completer<void>();
      final repo = _Preferences()..acknowledgement = ack.future;
      final owners = _Owner();
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPreferenceQuizScreen(useCases: _cases(repo, owners)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '56');
      await tester.tap(find.byKey(const ValueKey('learning-preferences/save')));
      await tester.pump();
      expect(repo.saveCount, 1);
      owners.id = 'local:replacement';
      ack.complete();
      await tester.pumpAndSettle();
      expect(find.text('บันทึกการตั้งค่าการเรียนแล้ว'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(repo.saveCount, 1);
    },
  );
  testWidgets(
    'AJ failed refresh retains same owner draft but not replacement owner',
    (tester) async {
      final repo = _Preferences();
      final owner = _Owner();
      final cases = _cases(repo, owner);
      var active = true;
      Widget app() => MaterialApp(
        home: TickerMode(
          enabled: active,
          child: LearningPreferenceQuizScreen(useCases: cases),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '77');
      active = false;
      await tester.pumpWidget(app());
      repo.failures = 1;
      active = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '77',
      );
      active = false;
      await tester.pumpWidget(app());
      owner.id = 'local:other';
      repo.current = LearnerPreferences.defaults(
        ownerId: owner.id,
        updatedAtUtc: DateTime.utc(2026),
      );
      active = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '20',
      );
      expect(repo.saveCount, 0);
    },
  );
  testWidgets(
    'AJ failed acknowledgement and failed read disable save until read retry',
    (tester) async {
      final repo = _Preferences()..failAcknowledgement = true;
      final hold = Completer<void>();
      repo.beforeSave = hold;
      final cases = _cases(repo);
      final registry = MenuActionRegistry(
        currentOwner: () => 'local:preferences-screen',
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: LearningPreferenceQuizScreen(useCases: cases),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '66');
      final save = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('learning-preferences/save')),
          )
          .onPressed!;
      save();
      await tester.pump();
      repo.failures = 1;
      hold.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('learning-preferences/save')),
        findsNothing,
      );
      save();
      await tester.pump();
      expect(repo.saveCount, 1);
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(_context(registry)['lastConfirmed']['minutes'], 66);
      expect(_context(registry)['status'], 'saved');
      expect(repo.saveCount, 1);
    },
  );
  testWidgets('AJ dropdown selection and dismissal preserve user draft', (
    tester,
  ) async {
    final repo = _Preferences();
    final registry = MenuActionRegistry(
      currentOwner: () => 'local:preferences-screen',
    );
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(
          home: LearningPreferenceQuizScreen(useCases: _cases(repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '43');
    await tester.tap(find.byKey(const ValueKey('learning-preferences/goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เตรียมสอบ').last);
    await tester.pumpAndSettle();
    expect(_context(registry)['draft']['goal'], 'examPreparation');
    await tester.tap(find.byKey(const ValueKey('learning-preferences/goal')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_context(registry)['draft']['minutes'], 43);
    expect(repo.saveCount, 0);
  });
  for (final sync in [false, true]) {
    testWidgets('AJ repeated read failure retry is bounded sync=$sync', (
      tester,
    ) async {
      final repo = _Preferences()
        ..failures = 2
        ..throwSynchronously = sync;
      await tester.pumpWidget(
        MaterialApp(home: LearningPreferenceQuizScreen(useCases: _cases(repo))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retry = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองใหม่'))
          .onPressed!;
      retry();
      retry();
      await tester.pumpAndSettle();
      expect(repo.readCount, 2);
      expect(tester.takeException(), isNull);
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองใหม่'))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(repo.readCount, 3);
      expect(repo.saveCount, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '20',
      );
      retry();
      await tester.pump();
      expect(repo.readCount, 3);
    });
  }
  for (final boundary in ['cover', 'pop', 'tab', 'dispose', 'replacement']) {
    testWidgets('AJ stale draft callbacks retired on $boundary', (
      tester,
    ) async {
      final repo = _Preferences();
      var cases = _cases(repo);
      final nav = GlobalKey<NavigatorState>();
      var active = true;
      Widget app() => MaterialApp(
        navigatorKey: nav,
        home: TickerMode(
          enabled: active,
          child: LearningPreferenceQuizScreen(useCases: cases),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      if (boundary == 'pop') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => LearningPreferenceQuizScreen(useCases: cases),
          ),
        );
        await tester.pumpAndSettle();
      }
      final goal = tester
          .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
            find.byKey(const ValueKey('learning-preferences/goal')),
          )
          .onChanged!;
      final activity = tester
          .widget<DropdownButtonFormField<LearnerActivityPreference>>(
            find.byKey(
              const ValueKey('learning-preferences/activity-preference'),
            ),
          )
          .onChanged!;
      final text = tester.widget<TextField>(find.byType(TextField)).onChanged!;
      final save = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('learning-preferences/save')),
          )
          .onPressed!;
      switch (boundary) {
        case 'cover':
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
        case 'pop':
          nav.currentState!.pop();
        case 'tab':
          active = false;
          await tester.pumpWidget(app());
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'replacement':
          cases = _cases(_Preferences());
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
      }
      goal(LearnerPreferenceGoal.examPreparation);
      activity(LearnerActivityPreference.quiz);
      text('90');
      save();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.saveCount, 0);
      if (boundary == 'cover') {
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
      if (boundary == 'tab') {
        active = true;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
      }
      if (boundary != 'dispose') {
        final current = tester
            .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
              find.byKey(const ValueKey('learning-preferences/goal')),
            );
        expect(current.initialValue, LearnerPreferenceGoal.balancedGrowth);
      }
    });
  }
  for (final boundary in ['cover', 'pop', 'tab']) {
    testWidgets('AJ pending save cannot mutate after $boundary', (
      tester,
    ) async {
      final release = Completer<void>();
      final repo = _Preferences()..beforeSave = release;
      final cases = _cases(repo);
      final nav = GlobalKey<NavigatorState>();
      var active = true;
      Widget app() => MaterialApp(
        navigatorKey: nav,
        home: TickerMode(
          enabled: active,
          child: LearningPreferenceQuizScreen(useCases: cases),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      if (boundary == 'pop') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => LearningPreferenceQuizScreen(useCases: cases),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), '65');
      final save = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('learning-preferences/save')),
          )
          .onPressed!;
      save();
      save();
      await tester.pump();
      if (boundary == 'cover')
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        );
      if (boundary == 'pop') nav.currentState!.pop();
      if (boundary == 'tab') {
        active = false;
        await tester.pumpWidget(app());
      }
      release.complete();
      await tester.pumpAndSettle();
      expect(repo.saveCount, 0);
      expect(tester.takeException(), isNull);
      if (boundary == 'cover') {
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
      if (boundary == 'tab') {
        active = true;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
      }
      if (boundary != 'pop')
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '65',
        );
    });
  }
  testWidgets(
    'AJ uncertain acknowledgement reconciles without automatic resave',
    (tester) async {
      final repo = _Preferences()..failAcknowledgement = true;
      final registry = MenuActionRegistry(
        currentOwner: () => 'local:preferences-screen',
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: LearningPreferenceQuizScreen(useCases: _cases(repo)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '55');
      await tester.tap(find.byKey(const ValueKey('learning-preferences/save')));
      await tester.pumpAndSettle();
      expect(repo.saveCount, 1);
      expect(_context(registry)['lastConfirmed']['minutes'], 55);
      expect(_context(registry)['status'], 'saved');
      expect(registry.snapshot()['actions'], isEmpty);
    },
  );
  testWidgets('AJ owner changes during read cannot display previous receipt', (
    tester,
  ) async {
    final pending = Completer<LearnerPreferences>();
    final repo = _Preferences()..pendingRead = pending;
    final owner = _Owner();
    await tester.pumpWidget(
      MaterialApp(
        home: LearningPreferenceQuizScreen(useCases: _cases(repo, owner)),
      ),
    );
    await tester.pump();
    owner.id = 'local:replacement';
    pending.complete(repo.current);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'ลองใหม่'), findsOneWidget);
    expect(repo.saveCount, 0);
  });
  testWidgets('AJ Thai failure scrolls at 360px and 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    final repo = _Preferences()..failures = 1;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: LearningPreferenceQuizScreen(useCases: _cases(repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('ลองใหม่'));
    expect(
      tester.getSemantics(find.text('ลองใหม่')).label,
      contains('ลองใหม่'),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('learning-preferences/save')),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
