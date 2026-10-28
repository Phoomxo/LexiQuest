import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';

void shopTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    await callback(tester);
    await _disposeShop(tester);
  });
}

Finder _catalogCard(String itemId) => find.ancestor(
  of: find.byKey(ValueKey<String>('reward-detail-$itemId')),
  matching: find.byType(Card),
);

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late RewardUseCases rewards;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    sequence = 0;
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'shop-owner',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: () => 'shop-tx-${sequence++}',
      nowUtc: () => DateTime.utc(2026, 10, 20, 12),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database.customInsert(
      'INSERT INTO points_ledger_entries '
      '(id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) '
      "VALUES ('shop-seed', '${owner.id}', 'shop-seed', 'learning', 200, 1)",
    );
  });

  tearDown(() => database.close());

  shopTestWidgets('announces catalog loading state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ShopPage(rewards: rewards)));

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.semanticsLabel, 'กำลังโหลดร้านค้ารางวัล');
    await _waitFor(tester, find.text('เหรียญคงเหลือ'));
  });

  shopTestWidgets(
    'catalog filters theme templates, wallpapers, and decorations',
    (tester) async {
      await _pumpShop(tester, rewards);

      expect(find.text('ธีมมาตรฐาน'), findsOneWidget);
      expect(find.text('ธีมมหาสมุทร'), findsOneWidget);
      expect(find.text('พื้นหลังสมาธิ'), findsNothing);
      expect(find.textContaining('รายการรางวัลรุ่น'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('shop-filter-wallpaper')),
      );
      await tester.pump();

      expect(find.text('ธีมมหาสมุทร'), findsNothing);
      expect(find.text('พื้นหลังสมาธิ'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('shop-filter-decoration')),
      );
      await tester.pumpAndSettle();

      expect(find.text('พื้นหลังสมาธิ'), findsNothing);
      expect(find.text('หมวกนักออกเสียง'), findsOneWidget);
      expect(find.text('ดาบนักไต่ระดับ'), findsOneWidget);
      expect(find.text('เกราะช่วยทบทวน'), findsOneWidget);
    },
  );

  shopTestWidgets('catalog retries one failed session load and recovers', (
    tester,
  ) async {
    final retrying = _RetryLoadRewardShop(rewards);
    await tester.pumpWidget(MaterialApp(home: ShopPage(rewards: retrying)));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );
    await tester.tap(find.text('ลองใหม่'));
    await _waitFor(tester, find.text('เหรียญคงเหลือ'));

    expect(retrying.loadCalls, 2);
    expect(find.text('เหรียญคงเหลือ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  shopTestWidgets('wide catalog places theme cards in separate columns', (
    tester,
  ) async {
    await _pumpShop(tester, rewards, size: const Size(1024, 768));

    final standard = tester.getRect(_catalogCard('theme_default'));
    final ocean = tester.getRect(_catalogCard('theme_ocean'));

    expect((standard.top - ocean.top).abs(), lessThan(1));
    expect(standard.right, lessThanOrEqualTo(ocean.left));
    expect(standard.left, lessThan(ocean.left));
  });

  for (final (size, scale, dark, multiColumn) in <(Size, double, bool, bool)>[
    (const Size(360, 800), 2, false, false),
    (const Size(393, 876), 2, true, false),
    (const Size(412, 915), 2, false, false),
    (const Size(600, 900), 1, true, false),
    (const Size(800, 900), 1, false, true),
    (const Size(1024, 900), 2, true, true),
    (const Size(1280, 900), 2, false, true),
  ]) {
    shopTestWidgets(
      'catalog cards fit $size at ${scale}x text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pumpShop(
          tester,
          rewards,
          size: size,
          textScale: scale,
          dark: dark,
        );

        final context = tester.element(find.byType(ShopPage));
        expect(MediaQuery.sizeOf(context), size);
        expect(MediaQuery.textScalerOf(context).scale(1), scale);
        expect(
          Theme.of(context).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);

        await _bringIntoView(
          tester,
          find.byKey(const ValueKey<String>('reward-detail-theme_default')),
        );

        final standardCard = tester.getRect(_catalogCard('theme_default'));
        final oceanCard = tester.getRect(_catalogCard('theme_ocean'));
        for (final card in [standardCard, oceanCard]) {
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(size.width));
        }
        expect(standardCard.overlaps(oceanCard), isFalse);
        if (multiColumn) {
          expect((standardCard.top - oceanCard.top).abs(), lessThan(1));
          expect(standardCard.right, lessThanOrEqualTo(oceanCard.left));
        } else {
          expect((standardCard.left - oceanCard.left).abs(), lessThan(1));
          expect(standardCard.bottom, lessThanOrEqualTo(oceanCard.top));
        }

        for (final item in RewardCatalog.items.where(
          (item) => item.kind == RewardItemKind.theme,
        )) {
          final card = tester.getRect(_catalogCard(item.id));
          for (final text in [
            find.text(item.name),
            find.text(item.description),
            find.text('${item.price} เหรียญ'),
          ]) {
            final textRect = tester.getRect(text);
            expect(card.contains(textRect.topLeft), isTrue);
            expect(card.contains(textRect.bottomRight), isTrue);
          }
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey<String>('reward-detail-${item.id}')),
                )
                .height,
            greaterThanOrEqualTo(48),
          );
        }
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey<String>('reward-equip-theme_default'),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey<String>('reward-purchase-theme_ocean'),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .where(
                (state) =>
                    state.axisDirection == AxisDirection.down ||
                    state.axisDirection == AxisDirection.up,
              ),
          hasLength(1),
        );
      },
    );
  }

  shopTestWidgets(
    'reduced-motion reward preview opens and closes without a timed transition',
    (tester) async {
      await _pumpShop(tester, rewards, reducedMotion: true);
      await tester.tap(
        find.byKey(const ValueKey<String>('reward-detail-theme_ocean')),
      );
      await tester.pump();

      final sheetContext = tester.element(find.byType(BottomSheet));
      final route = ModalRoute.of(sheetContext)!;
      expect(route.animation!.value, 1);
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(find.text('ตัวอย่างธีมมหาสมุทร').hitTestable(), findsOneWidget);

      Navigator.of(sheetContext).pop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('เหรียญคงเหลือ').hitTestable(), findsOneWidget);
    },
  );

  shopTestWidgets('detail preview and Back perform no reward writes', (
    tester,
  ) async {
    var intentCalls = 0;
    await _pumpShop(
      tester,
      rewards,
      generateIntentId: () {
        intentCalls += 1;
        return 'unused-preview-intent';
      },
    );
    final transactionsBefore = await database
        .select(database.rewardTransactions)
        .get();
    final ownedBefore = await database.select(database.ownedRewardItems).get();
    final equippedBefore = await database
        .select(database.equippedRewardItems)
        .get();
    final outboxBefore = await database.select(database.outboxOperations).get();

    await tester.tap(
      find.byKey(const ValueKey<String>('reward-detail-theme_ocean')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตัวอย่างธีมมหาสมุทร'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reward-preview-theme_ocean')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('ตัวอย่างธีมมหาสมุทร'), findsNothing);
    expect(
      await database.select(database.rewardTransactions).get(),
      transactionsBefore,
    );
    expect(await database.select(database.ownedRewardItems).get(), ownedBefore);
    expect(
      await database.select(database.equippedRewardItems).get(),
      equippedBefore,
    );
    expect(
      await database.select(database.outboxOperations).get(),
      outboxBefore,
    );
    expect(intentCalls, 0);
  });

  shopTestWidgets(
    'Ocean preview uses selected theme with equipped Focus wallpaper',
    (tester) async {
      await tester.runAsync(() async {
        await rewards.purchase(
          expectedOwnerId: 'local:shop-owner',
          itemId: 'wallpaper_focus',
          catalogVersion: RewardCatalog.version,
          idempotencyKey: 'preview-buy-wallpaper',
        );
        await rewards.equip(
          expectedOwnerId: 'local:shop-owner',
          itemId: 'wallpaper_focus',
          idempotencyKey: 'preview-equip-wallpaper',
        );
      });
      final transactionsBefore = await database
          .select(database.rewardTransactions)
          .get();
      final ownedBefore = await database
          .select(database.ownedRewardItems)
          .get();
      final equippedBefore = await database
          .select(database.equippedRewardItems)
          .get();
      final outboxBefore = await database
          .select(database.outboxOperations)
          .get();

      await _pumpShop(tester, rewards);
      final outerTheme = Theme.of(tester.element(find.byType(ShopPage)));
      expect(outerTheme.colorScheme.primary, M3Theme.primary);
      expect(outerTheme.scaffoldBackgroundColor, M3Theme.background);

      await tester.tap(
        find.byKey(const ValueKey<String>('reward-detail-theme_ocean')),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(
        const ValueKey<String>('reward-preview-theme_ocean'),
      );
      final previewTheme = Theme.of(tester.element(preview));
      final expected = M3Theme.lightThemeFor(
        themeId: 'theme_ocean',
        wallpaperId: 'wallpaper_focus',
      );
      expect(previewTheme.colorScheme.primary, expected.colorScheme.primary);
      expect(
        previewTheme.scaffoldBackgroundColor,
        expected.scaffoldBackgroundColor,
      );
      expect(
        Theme.of(tester.element(find.byType(ShopPage))).colorScheme.primary,
        outerTheme.colorScheme.primary,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        await database.select(database.rewardTransactions).get(),
        transactionsBefore,
      );
      expect(
        await database.select(database.ownedRewardItems).get(),
        ownedBefore,
      );
      expect(
        await database.select(database.equippedRewardItems).get(),
        equippedBefore,
      );
      expect(
        await database.select(database.outboxOperations).get(),
        outboxBefore,
      );
    },
  );

  shopTestWidgets(
    'Focus preview uses selected wallpaper with equipped Ocean theme in dark mode',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() async {
        await rewards.purchase(
          expectedOwnerId: 'local:shop-owner',
          itemId: 'theme_ocean',
          catalogVersion: RewardCatalog.version,
          idempotencyKey: 'preview-buy-theme',
        );
        await rewards.equip(
          expectedOwnerId: 'local:shop-owner',
          itemId: 'theme_ocean',
          idempotencyKey: 'preview-equip-theme',
        );
      });

      await _pumpShop(tester, rewards, dark: true);
      final outerTheme = Theme.of(tester.element(find.byType(ShopPage)));
      await tester.tap(
        find.byKey(const ValueKey<String>('shop-filter-wallpaper')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('reward-detail-wallpaper_focus')),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(
        const ValueKey<String>('reward-preview-wallpaper_focus'),
      );
      final previewTheme = Theme.of(tester.element(preview));
      final expected = M3Theme.darkThemeFor(
        themeId: 'theme_ocean',
        wallpaperId: 'wallpaper_focus',
      );
      expect(previewTheme.colorScheme.primary, expected.colorScheme.primary);
      expect(
        previewTheme.scaffoldBackgroundColor,
        expected.scaffoldBackgroundColor,
      );
      expect(
        Theme.of(tester.element(find.byType(ShopPage))).colorScheme.primary,
        outerTheme.colorScheme.primary,
      );
      final previewSemantics = tester.getSemantics(preview);
      expect(previewSemantics.label, contains('ตัวอย่างพื้นหลังสมาธิ'));
      expect(previewSemantics.label, contains('60 เหรียญ'));
      expect(previewSemantics.flagsCollection.isButton, isFalse);
      expect(
        previewSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      semantics.dispose();
    },
  );

  shopTestWidgets('purchase confirmation shows balance and disclaimer', (
    tester,
  ) async {
    await _pumpShop(tester, rewards);

    await tester.tap(find.widgetWithText(FilledButton, 'ซื้อ'));
    await tester.pumpAndSettle();

    expect(find.text('ยืนยันการซื้อ'), findsOneWidget);
    expect(find.text('80 เหรียญ'), findsWidgets);
    expect(find.text('200 → 120 เหรียญ'), findsOneWidget);
    expect(
      find.text('เป็นของตกแต่งเท่านั้น ไม่เพิ่มความได้เปรียบในการเรียน'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('confirm-purchase')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
    );

    expect(find.text('ตัวอย่างธีมมหาสมุทร'), findsNothing);
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((r) => r.transactionType.equals('purchase'))).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.ownedRewardItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(1),
    );
  });

  shopTestWidgets('tablet purchase confirmation is reachable without writes', (
    tester,
  ) async {
    var intentCalls = 0;
    await _pumpShop(
      tester,
      rewards,
      size: const Size(1024, 768),
      textScale: 2,
      dark: true,
      generateIntentId: () {
        intentCalls += 1;
        return 'unused-tablet-dialog-intent';
      },
    );
    final transactionsBefore = await database
        .select(database.rewardTransactions)
        .get();
    final ownedBefore = await database.select(database.ownedRewardItems).get();
    final equippedBefore = await database
        .select(database.equippedRewardItems)
        .get();
    final outboxBefore = await database.select(database.outboxOperations).get();

    final purchase = find.byKey(
      const ValueKey<String>('reward-purchase-theme_ocean'),
    );
    expect(tester.getSize(purchase).height, greaterThanOrEqualTo(48));
    await tester.tap(purchase);
    await tester.pumpAndSettle();

    final confirm = find.byKey(const ValueKey<String>('confirm-purchase'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(intentCalls, 0);
    expect(
      await database.select(database.rewardTransactions).get(),
      transactionsBefore,
    );
    expect(await database.select(database.ownedRewardItems).get(), ownedBefore);
    expect(
      await database.select(database.equippedRewardItems).get(),
      equippedBefore,
    );
    expect(
      await database.select(database.outboxOperations).get(),
      outboxBefore,
    );
  });

  shopTestWidgets(
    'long balance remains readable on a compact large-text view',
    (tester) async {
      const balance = 999999999;
      await _pumpShop(
        tester,
        _LostAckRewardShop(initialBalance: balance),
        size: const Size(360, 800),
        textScale: 2,
      );

      await _bringIntoView(tester, find.text('$balance'));
      final balanceText = tester.getRect(find.text('$balance'));
      final balanceCard = tester.getRect(
        find.ancestor(of: find.text('$balance'), matching: find.byType(Card)),
      );
      expect(balanceCard.contains(balanceText.topLeft), isTrue);
      expect(balanceCard.contains(balanceText.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (balance, missing) in <(int, int)>[(0, 80), (79, 1)]) {
    shopTestWidgets(
      'known balance $balance blocks purchase and shows missing $missing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var intentCalls = 0;
        final guardedRewards = _LostAckRewardShop(initialBalance: balance);
        final transactionsBefore = await database
            .select(database.rewardTransactions)
            .get();
        final ownedBefore = await database
            .select(database.ownedRewardItems)
            .get();
        final equippedBefore = await database
            .select(database.equippedRewardItems)
            .get();
        final outboxBefore = await database
            .select(database.outboxOperations)
            .get();

        await _pumpShop(
          tester,
          guardedRewards,
          generateIntentId: () {
            intentCalls += 1;
            return 'must-not-create-an-intent';
          },
        );
        await _bringIntoView(
          tester,
          find.byKey(const ValueKey<String>('reward-detail-theme_ocean')),
        );
        final purchase = find.byKey(
          const ValueKey<String>('reward-purchase-theme_ocean'),
        );
        expect(purchase, findsOneWidget);
        await tester.ensureVisible(purchase);
        await tester.pumpAndSettle();
        await tester.tap(purchase);
        await tester.pumpAndSettle();

        expect(find.text('เหรียญไม่เพียงพอ'), findsOneWidget);
        expect(find.text('ยอดคงเหลือ $balance เหรียญ'), findsOneWidget);
        expect(find.text('ราคา 80 เหรียญ'), findsOneWidget);
        expect(find.text('ขาดอีก $missing เหรียญ'), findsOneWidget);
        expect(find.text('$balance → ${balance - 80} เหรียญ'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('confirm-purchase')),
          findsNothing,
        );
        final message = find.byKey(
          const ValueKey<String>('insufficient-purchase-message'),
        );
        final messageSemantics = tester.getSemantics(message);
        expect(messageSemantics.label, contains('ไม่สามารถซื้อธีมมหาสมุทร'));
        expect(messageSemantics.label, contains('ยอดคงเหลือ $balance เหรียญ'));
        expect(messageSemantics.label, contains('ราคา 80 เหรียญ'));
        expect(messageSemantics.label, contains('ขาดอีก $missing เหรียญ'));
        expect(guardedRewards.purchaseCalls, isEmpty);
        expect(intentCalls, 0);

        final close = find.byKey(
          const ValueKey<String>('insufficient-purchase-close'),
        );
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
        if (balance == 0) {
          await tester.tap(close);
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();

        expect(find.text('เหรียญไม่เพียงพอ'), findsNothing);
        expect(
          await database.select(database.rewardTransactions).get(),
          transactionsBefore,
        );
        expect(
          await database.select(database.ownedRewardItems).get(),
          ownedBefore,
        );
        expect(
          await database.select(database.equippedRewardItems).get(),
          equippedBefore,
        );
        expect(
          await database.select(database.outboxOperations).get(),
          outboxBefore,
        );
        semantics.dispose();
      },
    );
  }

  for (final (balance, missing, size, dark, itemId)
      in <(int, int, Size, bool, String)>[
        (1, 59, const Size(360, 800), false, 'wallpaper_focus'),
        (79, 1, const Size(800, 360), true, 'theme_ocean'),
      ]) {
    shopTestWidgets(
      'insufficient dialog fits $size at 2x in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.runAsync(
          () => database.customStatement(
            "UPDATE points_ledger_entries SET amount = $balance WHERE id = 'shop-seed'",
          ),
        );
        await _pumpShop(tester, rewards, size: size, textScale: 2, dark: dark);
        if (itemId == 'wallpaper_focus') {
          final filter = find.byKey(
            const ValueKey<String>('shop-filter-wallpaper'),
          );
          await tester.ensureVisible(filter);
          await tester.tap(filter);
          await tester.pumpAndSettle();
        }
        await _bringIntoView(
          tester,
          find.byKey(ValueKey<String>('reward-detail-$itemId')),
        );
        final purchase = find.byKey(
          ValueKey<String>('reward-purchase-$itemId'),
        );
        expect(purchase, findsOneWidget);
        await tester.ensureVisible(purchase);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(purchase);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ขาดอีก $missing เหรียญ'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('confirm-purchase')),
          findsNothing,
        );
        final close = find.byKey(
          const ValueKey<String>('insufficient-purchase-close'),
        );
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
      },
    );
  }

  shopTestWidgets('exact-price purchase can confirm and reaches zero', (
    tester,
  ) async {
    await tester.runAsync(
      () => database.customStatement(
        "UPDATE points_ledger_entries SET amount = 80 WHERE id = 'shop-seed'",
      ),
    );
    await _pumpShop(tester, rewards);

    await tester.tap(
      find.byKey(const ValueKey<String>('reward-purchase-theme_ocean')),
    );
    await tester.pumpAndSettle();

    expect(find.text('80 → 0 เหรียญ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('confirm-purchase')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('confirm-purchase')))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(const ValueKey<String>('confirm-purchase')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
    );

    expect(find.text('0'), findsOneWidget);
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((row) => row.transactionType.equals('purchase'))).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.ownedRewardItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(1),
    );
  });

  shopTestWidgets(
    'repository insufficiency after an affordable snapshot reloads honestly',
    (tester) async {
      var intentCalls = 0;
      await _pumpShop(
        tester,
        rewards,
        generateIntentId: () {
          intentCalls += 1;
          return 'race-insufficient-intent';
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('reward-purchase-theme_ocean')),
      );
      await tester.pumpAndSettle();
      expect(find.text('200 → 120 เหรียญ'), findsOneWidget);
      final transactionsBefore = await database
          .select(database.rewardTransactions)
          .get();
      final ownedBefore = await database
          .select(database.ownedRewardItems)
          .get();
      final equippedBefore = await database
          .select(database.equippedRewardItems)
          .get();
      final outboxBefore = await database
          .select(database.outboxOperations)
          .get();

      await tester.runAsync(
        () => database.customStatement(
          "DELETE FROM points_ledger_entries WHERE id = 'shop-seed'",
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('confirm-purchase')));
      await _waitFor(tester, find.text('เหรียญไม่เพียงพอ'));
      await _waitFor(
        tester,
        find.byKey(const ValueKey<String>('reward-purchase-theme_ocean')),
      );

      expect(intentCalls, 1);
      expect(find.text('0'), findsWidgets);
      expect(
        await database.select(database.rewardTransactions).get(),
        transactionsBefore,
      );
      expect(
        await database.select(database.ownedRewardItems).get(),
        ownedBefore,
      );
      expect(
        await database.select(database.equippedRewardItems).get(),
        equippedBefore,
      );
      expect(
        await database.select(database.outboxOperations).get(),
        outboxBefore,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reward-purchase-theme_ocean')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ขาดอีก 80 เหรียญ'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('confirm-purchase')),
        findsNothing,
      );
      expect(intentCalls, 1);
    },
  );

  shopTestWidgets('purchase cancel and Back perform no writes', (tester) async {
    await _pumpShop(tester, rewards);
    final transactionsBefore = await database
        .select(database.rewardTransactions)
        .get();

    await tester.tap(find.widgetWithText(FilledButton, 'ซื้อ'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('ยืนยันการซื้อ'), findsNothing);
    expect(
      await database.select(database.rewardTransactions).get(),
      transactionsBefore,
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  shopTestWidgets('purchase double tap and replay debit only once', (
    tester,
  ) async {
    var intentCalls = 0;
    final retryRewards = _LostAckRewardShop();
    await _pumpShop(
      tester,
      retryRewards,
      generateIntentId: () {
        intentCalls += 1;
        return 'stable-purchase-intent';
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ซื้อ'));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const ValueKey<String>('confirm-purchase'));
    final confirmPurchase = tester.widget<FilledButton>(confirm).onPressed!;
    confirmPurchase();
    confirmPurchase();
    await _waitFor(tester, find.text('ไม่ทราบผลการซื้อ กรุณาลองอีกครั้ง'));

    expect(intentCalls, 1);
    expect(retryRewards.purchaseCalls, hasLength(1));
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).clearSnackBars();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'ซื้อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('confirm-purchase')));
    await _waitFor(tester, find.text('รายการนี้เป็นของคุณอยู่แล้ว'));
    await tester.pump();

    expect(retryRewards.purchaseCalls, hasLength(2));
    expect(
      retryRewards.purchaseCalls.map((call) => call.expectedOwnerId),
      everyElement('local:shop-owner'),
    );
    expect(
      retryRewards.purchaseCalls.map((call) => call.idempotencyKey),
      everyElement('stable-purchase-intent'),
    );
    expect(
      retryRewards.purchaseCalls.map((call) => call.itemId),
      everyElement('theme_ocean'),
    );
    expect(
      retryRewards.purchaseCalls.map((call) => call.catalogVersion),
      everyElement(RewardCatalog.version),
    );
    expect(find.text('120'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
      findsOneWidget,
    );
    expect(intentCalls, 1);
  });

  shopTestWidgets('owner switch while confirming cannot spend the new owner', (
    tester,
  ) async {
    await _pumpShop(tester, rewards);
    await tester.tap(find.widgetWithText(FilledButton, 'ซื้อ'));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () =>
          (database.update(database.localOwners)
                ..where((row) => row.id.equals('local:shop-owner')))
              .write(const LocalOwnersCompanion(isActive: Value(false))),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
      findsNothing,
    );

    await tester.runAsync(
      () => database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
          ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('confirm-purchase')));
    await _waitFor(tester, find.text('บัญชีเปลี่ยนแล้ว กรุณาลองใหม่'));

    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((row) => row.transactionType.equals('purchase'))).get(),
      isEmpty,
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  shopTestWidgets(
    'mounted shop replaces owner A snapshot when owner B activates',
    (tester) async {
      await tester.runAsync(
        () => rewards.purchase(
          expectedOwnerId: 'local:shop-owner',
          itemId: 'theme_ocean',
          catalogVersion: 1,
          idempotencyKey: 'owner-a-purchase',
        ),
      );
      await _pumpShop(tester, rewards);
      expect(
        find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
        findsOneWidget,
      );

      await tester.runAsync(
        () => database.transaction(() async {
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals('local:shop-owner')))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
              );
        }),
      );
      await _waitFor(
        tester,
        find.byKey(const ValueKey<String>('reward-purchase-theme_ocean')),
      );

      expect(find.text('0'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('reward-equip-theme_ocean')),
        findsNothing,
      );
    },
  );

  shopTestWidgets(
    'existing equip button still equips without opening preview',
    (tester) async {
      await _pumpShop(tester, rewards);

      await tester.tap(find.widgetWithText(OutlinedButton, 'ใช้งาน'));
      await _waitFor(tester, find.widgetWithText(Chip, 'กำลังใช้'));

      expect(find.text('ตัวอย่างธีมมาตรฐาน'), findsNothing);
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((r) => r.transactionType.equals('equip'))).get(),
        hasLength(1),
      );
      expect((await rewards.load()).equippedBySlot['theme'], 'theme_default');
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
    },
  );

  for (final (size, scale, dark) in <(Size, double, bool)>[
    (const Size(360, 800), 2, false),
    (const Size(800, 500), 1, true),
  ]) {
    shopTestWidgets('preview preserves filter, scroll, and data at $size', (
      tester,
    ) async {
      var intentCalls = 0;
      await _pumpShop(
        tester,
        rewards,
        size: size,
        textScale: scale,
        dark: dark,
        generateIntentId: () {
          intentCalls += 1;
          return 'unused-layout-intent';
        },
      );
      final transactionsBefore = await database
          .select(database.rewardTransactions)
          .get();
      final ownedBefore = await database
          .select(database.ownedRewardItems)
          .get();
      final equippedBefore = await database
          .select(database.equippedRewardItems)
          .get();
      final outboxBefore = await database
          .select(database.outboxOperations)
          .get();

      await _bringIntoView(
        tester,
        find.byKey(const ValueKey<String>('shop-filter-decoration')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('shop-filter-decoration')),
      );
      await tester.pumpAndSettle();
      await _bringIntoView(
        tester,
        find.byKey(const ValueKey<String>('reward-detail-armor_srs')),
      );
      final verticalScroll = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere(
            (state) =>
                state.axisDirection == AxisDirection.down ||
                state.axisDirection == AxisDirection.up,
          );
      final offsetBefore = verticalScroll.position.pixels;

      await tester.tap(
        find.byKey(const ValueKey<String>('reward-detail-armor_srs')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(verticalScroll.position.pixels, offsetBefore);
      expect(find.text('เกราะช่วยทบทวน'), findsOneWidget);
      expect(intentCalls, 0);
      expect(
        await database.select(database.rewardTransactions).get(),
        transactionsBefore,
      );
      expect(
        await database.select(database.ownedRewardItems).get(),
        ownedBefore,
      );
      expect(
        await database.select(database.equippedRewardItems).get(),
        equippedBefore,
      );
      expect(
        await database.select(database.outboxOperations).get(),
        outboxBefore,
      );
    });
  }

  shopTestWidgets('resize preserves catalog state and performs no writes', (
    tester,
  ) async {
    var intentCalls = 0;
    await _pumpShop(
      tester,
      rewards,
      size: const Size(600, 500),
      generateIntentId: () {
        intentCalls += 1;
        return 'unused-resize-intent';
      },
    );
    final transactionsBefore = await database
        .select(database.rewardTransactions)
        .get();
    final ownedBefore = await database.select(database.ownedRewardItems).get();
    final equippedBefore = await database
        .select(database.equippedRewardItems)
        .get();
    final outboxBefore = await database.select(database.outboxOperations).get();
    final shopState = tester.state(find.byType(ShopPage));

    await _bringIntoView(
      tester,
      find.byKey(const ValueKey<String>('shop-filter-decoration')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('shop-filter-decoration')),
    );
    await tester.pumpAndSettle();
    await _bringIntoView(
      tester,
      find.byKey(const ValueKey<String>('reward-detail-armor_srs')),
    );
    final verticalScroll = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere(
          (state) =>
              state.axisDirection == AxisDirection.down ||
              state.axisDirection == AxisDirection.up,
        );
    expect(verticalScroll.position.pixels, greaterThan(0));

    tester.view.physicalSize = const Size(800, 500);
    await tester.pumpAndSettle();

    final resizedScroll = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere(
          (state) =>
              state.axisDirection == AxisDirection.down ||
              state.axisDirection == AxisDirection.up,
        );
    expect(identical(tester.state(find.byType(ShopPage)), shopState), isTrue);
    expect(identical(resizedScroll, verticalScroll), isTrue);
    expect(resizedScroll.position.pixels, greaterThan(0));
    expect(find.text('เกราะช่วยทบทวน'), findsOneWidget);
    expect(find.text('ธีมมหาสมุทร'), findsNothing);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(ShopPage))),
      const Size(800, 500),
    );
    expect(tester.takeException(), isNull);
    expect(intentCalls, 0);
    expect(
      await database.select(database.rewardTransactions).get(),
      transactionsBefore,
    );
    expect(await database.select(database.ownedRewardItems).get(), ownedBefore);
    expect(
      await database.select(database.equippedRewardItems).get(),
      equippedBefore,
    );
    expect(
      await database.select(database.outboxOperations).get(),
      outboxBefore,
    );
  });

  for (final (size, scale, dark, itemId) in <(Size, double, bool, String)>[
    (const Size(360, 800), 2, false, 'theme_ocean'),
    (const Size(360, 800), 2, true, 'wallpaper_focus'),
    (const Size(393, 876), 1.3, false, 'theme_ocean'),
    (const Size(412, 915), 2, true, 'wallpaper_focus'),
    (const Size(800, 360), 2, false, 'wallpaper_focus'),
    (const Size(800, 360), 2, true, 'theme_ocean'),
  ]) {
    shopTestWidgets(
      '$itemId preview fits $size at ${scale}x text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pumpShop(
          tester,
          rewards,
          size: size,
          textScale: scale,
          dark: dark,
        );
        final title = find.text('ร้านค้ารางวัล');
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
          scale >= 1.5 ? 96 : kToolbarHeight,
        );
        expect(tester.takeException(), isNull);

        await _bringIntoView(
          tester,
          find.byKey(const ValueKey<String>('shop-filter-wallpaper')),
        );
        final filterSize = tester.getSize(
          find.byKey(const ValueKey<String>('shop-filter-wallpaper')),
        );
        expect(filterSize.height, greaterThanOrEqualTo(48));
        if (itemId == 'wallpaper_focus') {
          await tester.tap(
            find.byKey(const ValueKey<String>('shop-filter-wallpaper')),
          );
          await tester.pumpAndSettle();
        }

        final detailButton = find.byKey(
          ValueKey<String>('reward-detail-$itemId'),
        );
        await _bringIntoView(tester, detailButton);
        expect(tester.getSize(detailButton).height, greaterThanOrEqualTo(48));
        await tester.tap(detailButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final close = find.widgetWithText(OutlinedButton, 'ปิดตัวอย่าง');
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
      },
    );
  }
}

Future<void> _pumpShop(
  WidgetTester tester,
  RewardShopOperations rewards, {
  Size size = const Size(393, 876),
  double textScale = 1,
  bool dark = false,
  bool reducedMotion = false,
  String Function()? generateIntentId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      darkTheme: M3Theme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: ShopPage(rewards: rewards, generateIntentId: generateIntentId),
    ),
  );
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.text('เหรียญคงเหลือ').evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the reward catalog: ${tester.takeException()}');
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 10 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _disposeShop(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final class _LostAckRewardShop implements RewardShopOperations {
  _LostAckRewardShop({int initialBalance = 200})
    : _initialAccount = RewardAccount(
        balance: initialBalance,
        catalogVersion: RewardCatalog.version,
        ownedItemIds: const {},
        equippedBySlot: const {},
        transactionCount: 0,
      );

  final List<
    ({
      String expectedOwnerId,
      String itemId,
      int catalogVersion,
      String idempotencyKey,
    })
  >
  purchaseCalls = [];

  final RewardAccount _initialAccount;
  final RewardAccount _replayedAccount = const RewardAccount(
    balance: 120,
    catalogVersion: RewardCatalog.version,
    ownedItemIds: {'theme_ocean'},
    equippedBySlot: {},
    transactionCount: 1,
  );

  @override
  Future<RewardSession> loadSession() async =>
      RewardSession(ownerId: 'local:shop-owner', account: _initialAccount);

  @override
  Stream<RewardAppearance> watchAppearance() => Stream.value(
    const RewardAppearance(ownerId: 'local:shop-owner', equippedBySlot: {}),
  );

  @override
  Future<PurchaseResult> purchase({
    required String expectedOwnerId,
    required String itemId,
    required int catalogVersion,
    required String idempotencyKey,
  }) async {
    purchaseCalls.add((
      expectedOwnerId: expectedOwnerId,
      itemId: itemId,
      catalogVersion: catalogVersion,
      idempotencyKey: idempotencyKey,
    ));
    if (purchaseCalls.length == 1) {
      throw StateError('synthetic acknowledgement loss');
    }
    return PurchaseResult(
      status: PurchaseStatus.replayed,
      account: _replayedAccount,
    );
  }

  @override
  Future<EquipResult> equip({
    required String expectedOwnerId,
    required String itemId,
    required String idempotencyKey,
  }) {
    throw UnsupportedError('equip is outside this fixture');
  }
}

final class _RetryLoadRewardShop implements RewardShopOperations {
  _RetryLoadRewardShop(this.delegate);

  final RewardShopOperations delegate;
  var loadCalls = 0;

  @override
  Future<RewardSession> loadSession() {
    loadCalls++;
    if (loadCalls == 1) {
      return Future.error(StateError('synthetic reward read failure'));
    }
    return delegate.loadSession();
  }

  @override
  Stream<RewardAppearance> watchAppearance() => delegate.watchAppearance();

  @override
  Future<PurchaseResult> purchase({
    required String expectedOwnerId,
    required String itemId,
    required int catalogVersion,
    required String idempotencyKey,
  }) => delegate.purchase(
    expectedOwnerId: expectedOwnerId,
    itemId: itemId,
    catalogVersion: catalogVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<EquipResult> equip({
    required String expectedOwnerId,
    required String itemId,
    required String idempotencyKey,
  }) => delegate.equip(
    expectedOwnerId: expectedOwnerId,
    itemId: itemId,
    idempotencyKey: idempotencyKey,
  );
}
