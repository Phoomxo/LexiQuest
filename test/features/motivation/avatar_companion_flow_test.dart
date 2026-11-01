import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/motivation/presentation/contextual_companion_panel.dart';
import 'package:vocab_learning_app/features/motivation/presentation/avatar_progress_panel.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';

import '../quest/support/quest_repository_harness.dart';
import '../../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  testWidgets(
    'owned cosmetics stay unequipped while a locked cosmetic is previewed',
    (tester) async {
      const account = RewardAccount(
        balance: 0,
        catalogVersion: 1,
        ownedItemIds: {'headgear_ipa'},
        equippedBySlot: {},
        transactionCount: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvatarCosmeticPreview(
              account: account,
              preview: RewardCatalog.byId('armor_srs'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.school_outlined), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.text('หมวกนักออกเสียง · เป็นเจ้าของแล้ว'), findsOneWidget);
      expect(find.text('เกราะช่วยทบทวน · กำลังดูตัวอย่าง'), findsOneWidget);
      expect(account.equippedBySlot, isEmpty);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'avatar uses canonical level and catalog facts without preview writes ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = (await motivationPresentationDeadline(
          tester,
          'avatar-$dark/open',
          () => tester.runAsync(QuestHarness.open),
        ))!;
        Future<void>? closing;
        Future<void> close() =>
            closing ??= closeMotivationPresentation(tester, h.close);
        try {
          final progress = ProgressUseCases(
            owners: h.storage.owners,
            queries: DriftProgressQueries(h.database),
            nowUtc: () => h.now,
          );
          var ids = 0;
          final rewards = RewardUseCases(
            owners: h.storage.owners,
            repository: DriftRewardRepository(h.database),
            generateId: () => 'synthetic-avatar-${++ids}',
            nowUtc: () => h.now,
          );
          await motivationPresentationIo(
            tester,
            () => h.answer(),
            stage: 'avatar-$dark/answer',
          );
          final canonical = await motivationPresentationIo(
            tester,
            progress.load,
            stage: 'avatar-$dark/progress',
          );
          final before = await motivationPresentationIo(
            tester,
            h.storage.snapshot,
            stage: 'avatar-$dark/before',
          );
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await motivationPresentationDeadline(
            tester,
            'avatar-$dark/mount',
            () => tester.pumpWidget(
              _app(
                AvatarEquipmentScreen(
                  rewards: rewards,
                  progressLoader: progress.load,
                ),
                dark,
              ),
            ),
          );
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('avatar-canonical-level'))
                .evaluate()
                .isNotEmpty,
          );
          expect(
            find.text('ระดับอวตาร ${canonical.gameLevel}'),
            findsOneWidget,
          );
          expect(
            find.text('${canonical.totalXp} XP จากการเรียนและภารกิจที่บันทึก'),
            findsOneWidget,
          );
          expect(
            find.textContaining('หมวกนักออกเสียง · ยังไม่ปลดล็อก'),
            findsOneWidget,
          );
          expect(
            await motivationPresentationIo(tester, h.storage.snapshot),
            before,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await close();
        }
      },
    );
  }

  testWidgets(
    'companion reacts to actual stored motivation and invalidates retained owner ABA actions',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'companion/open',
        () => tester.runAsync(QuestHarness.open),
      ))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      var ids = 0;
      final runtime = MotivationRuntime(
        database: h.database,
        ownerWrites: h.storage.ownerWrites,
        owners: h.storage.owners,
        ownerChanges: owners.stream,
        nowUtc: () => h.now,
        generateId: () => 'synthetic-companion-${++ids}',
      );
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, () async {
            await runtime.dispose();
            await owners.close();
            await h.close();
          });
      try {
        owners.add(configuredOwnerId);
        runtime.setForeground(true);
        await motivationPresentationIo(
          tester,
          () => runtime.activate(
            ownerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
        );
        final progress = ProgressUseCases(
          owners: h.storage.owners,
          queries: DriftProgressQueries(h.database),
          nowUtc: () => h.now,
        );
        var actions = 0;
        await motivationPresentationDeadline(
          tester,
          'companion/mount',
          () => tester.pumpWidget(
            _app(
              Scaffold(
                body: SingleChildScrollView(
                  child: ContextualCompanionPanel(
                    runtime: runtime,
                    ownerId: configuredOwnerId,
                    progress: progress,
                    onPractice: () => actions++,
                  ),
                ),
              ),
              false,
            ),
          ),
        );
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('companion-practice'))
              .evaluate()
              .isNotEmpty,
        );
        final before = await motivationPresentationIo(
          tester,
          h.storage.snapshot,
        );
        expect(find.textContaining('เริ่มจากแบบฝึกสั้น'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('companion-dismiss')),
        );
        await tester.tap(find.byKey(const ValueKey('companion-dismiss')));
        await tester.pump();
        expect(find.byKey(const ValueKey('companion-practice')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('companion-show')));
        await tester.pump();
        final retained = tester
            .widget<TextButton>(
              find.byKey(const ValueKey('companion-practice')),
            )
            .onPressed!;
        owners.add('synthetic-other');
        owners.add(configuredOwnerId);
        retained();
        await tester.pump();
        expect(actions, 0);
        expect(
          await motivationPresentationIo(tester, h.storage.snapshot),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await close();
      }
    },
  );
}

Widget _app(Widget child, bool dark) => MaterialApp(
  theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2), disableAnimations: true),
    child: child!,
  ),
  home: child,
);

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150; i++) {
    await motivationPresentationDeadline(
      tester,
      'avatar-companion-wait/io-$i',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      ),
    );
    await motivationPresentationDeadline(
      tester,
      'avatar-companion-wait/pump-$i',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    if (done()) return;
  }
  fail('Actual canonical avatar/companion view did not become ready');
}
