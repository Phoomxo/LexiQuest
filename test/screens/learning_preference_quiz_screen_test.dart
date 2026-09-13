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
  Completer<void>? beforeSave;
  Completer<LearnerPreferences>? pendingRead;

  @override
  Future<LearnerPreferences> read(String ownerId) async =>
      pendingRead == null ? current : await pendingRead!.future;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (beforeSave != null) await beforeSave!.future;
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
    saveCount += 1;
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
