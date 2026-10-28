import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/domain/reward_models.dart';
import '../runtime/app_dependencies.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key, this.rewards, this.generateIntentId});

  final RewardShopOperations? rewards;
  final String Function()? generateIntentId;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  RewardShopOperations? _rewards;
  Future<RewardSession>? _session;
  final Set<String> _busyItems = <String>{};
  final Map<String, _RewardIntent> _purchaseIntents = <String, _RewardIntent>{};
  final Map<String, _RewardIntent> _equipIntents = <String, _RewardIntent>{};
  StreamSubscription<RewardAppearance>? _appearanceSubscription;
  String? _activeAppearanceOwnerId;
  var _hasAppearanceSnapshot = false;
  var _section = _CatalogSection.themes;
  var _requestSequence = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rewards ??=
        widget.rewards ?? AppDependenciesScope.maybeOf(context)?.rewards;
    _session ??= _rewards == null
        ? Future<RewardSession>.error(
            StateError('reward dependency unavailable'),
          )
        : _loadCurrentSession();
    _appearanceSubscription ??= _rewards?.watchAppearance().listen(
      _onAppearance,
    );
  }

  Future<RewardSession> _loadCurrentSession() async {
    final rewards = _rewards!;
    try {
      return await rewards.loadSession();
    } on RewardException catch (error) {
      if (error.code != RewardFailureCode.ownerChanged) rethrow;
      return rewards.loadSession();
    }
  }

  void _onAppearance(RewardAppearance appearance) {
    if (!mounted) return;
    final hadSnapshot = _hasAppearanceSnapshot;
    final previousOwnerId = _activeAppearanceOwnerId;
    _hasAppearanceSnapshot = true;
    _activeAppearanceOwnerId = appearance.ownerId;
    if (!hadSnapshot || previousOwnerId == appearance.ownerId) {
      return;
    }
    _purchaseIntents.clear();
    _equipIntents.clear();
    if (appearance.ownerId == null) {
      setState(() {});
    } else {
      _reloadSession();
    }
  }

  Future<void> _confirmPurchase(
    RewardCatalogItem item,
    RewardSession session,
  ) async {
    final balance = session.account.balance;
    final hasUncertainIntent =
        _purchaseIntents[item.id]?.ownerId == session.ownerId;
    if (!hasUncertainIntent && balance < item.price) {
      final missing = item.price - balance;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('เหรียญไม่เพียงพอ'),
          content: Semantics(
            key: const ValueKey<String>('insufficient-purchase-message'),
            container: true,
            excludeSemantics: true,
            label:
                'ไม่สามารถซื้อ${item.name} ยอดคงเหลือ $balance เหรียญ '
                'ราคา ${item.price} เหรียญ ขาดอีก $missing เหรียญ '
                'สะสมเหรียญเพิ่มแล้วลองอีกครั้ง',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name),
                Text('ยอดคงเหลือ $balance เหรียญ'),
                Text('ราคา ${item.price} เหรียญ'),
                const SizedBox(height: 12),
                Text('ขาดอีก $missing เหรียญ'),
                const SizedBox(height: 12),
                const Text('สะสมเหรียญเพิ่มแล้วลองอีกครั้ง'),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey<String>('insufficient-purchase-close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ยกเลิก'),
            ),
          ],
        ),
      );
      return;
    }
    var confirmed = false;
    final shouldPurchase = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('ยืนยันการซื้อ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name),
            Text('${item.price} เหรียญ'),
            const SizedBox(height: 12),
            Text(
              '${session.account.balance} → ${session.account.balance - item.price} เหรียญ',
            ),
            const SizedBox(height: 12),
            const Text('เป็นของตกแต่งเท่านั้น ไม่เพิ่มความได้เปรียบในการเรียน'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm-purchase'),
            onPressed: () {
              if (confirmed) return;
              confirmed = true;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('ยืนยันซื้อ'),
          ),
        ],
      ),
    );
    if (shouldPurchase == true && mounted) await _purchase(item, session);
  }

  Future<void> _purchase(RewardCatalogItem item, RewardSession session) async {
    final rewards = _rewards;
    if (rewards == null || _busyItems.contains(item.id)) return;
    final intent = _intentFor(
      _purchaseIntents,
      ownerId: session.ownerId,
      itemId: item.id,
      operation: 'purchase',
    );
    setState(() => _busyItems.add(item.id));
    try {
      final result = await rewards.purchase(
        expectedOwnerId: intent.ownerId,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        idempotencyKey: intent.idempotencyKey,
      );
      if (!mounted) return;
      _purchaseIntents.remove(item.id);
      setState(() {
        _session = Future.value(
          RewardSession(ownerId: intent.ownerId, account: result.account),
        );
      });
      final text = result.status == PurchaseStatus.purchased
          ? 'ซื้อรายการและบันทึกในเครื่องแล้ว'
          : 'รายการนี้เป็นของคุณอยู่แล้ว';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } on RewardException catch (error) {
      if (!mounted) return;
      _purchaseIntents.remove(item.id);
      final text = switch (error.code) {
        RewardFailureCode.insufficientBalance => 'เหรียญไม่เพียงพอ',
        RewardFailureCode.staleCatalog =>
          'ข้อมูลราคาเปลี่ยนแล้ว กรุณาเปิดหน้าใหม่',
        RewardFailureCode.ownerChanged => 'บัญชีเปลี่ยนแล้ว กรุณาลองใหม่',
        _ => 'ไม่สามารถซื้อรายการนี้ได้',
      };
      if (error.code == RewardFailureCode.ownerChanged ||
          error.code == RewardFailureCode.insufficientBalance) {
        _reloadSession();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่ทราบผลการซื้อ กรุณาลองอีกครั้ง')),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  Future<void> _equip(RewardCatalogItem item, RewardSession session) async {
    final rewards = _rewards;
    if (rewards == null || _busyItems.contains(item.id)) return;
    final intent = _intentFor(
      _equipIntents,
      ownerId: session.ownerId,
      itemId: item.id,
      operation: 'equip',
    );
    setState(() => _busyItems.add(item.id));
    try {
      final result = await rewards.equip(
        expectedOwnerId: intent.ownerId,
        itemId: item.id,
        idempotencyKey: intent.idempotencyKey,
      );
      if (!mounted) return;
      _equipIntents.remove(item.id);
      setState(() {
        _session = Future.value(
          RewardSession(ownerId: intent.ownerId, account: result.account),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ใช้งานรายการนี้แล้ว')));
    } on RewardException catch (error) {
      if (!mounted) return;
      _equipIntents.remove(item.id);
      if (error.code == RewardFailureCode.ownerChanged) _reloadSession();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == RewardFailureCode.ownerChanged
                ? 'บัญชีเปลี่ยนแล้ว กรุณาลองใหม่'
                : 'ต้องเป็นเจ้าของรายการก่อนใช้งาน',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่ทราบผลการใช้งาน กรุณาลองอีกครั้ง')),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  _RewardIntent _intentFor(
    Map<String, _RewardIntent> intents, {
    required String ownerId,
    required String itemId,
    required String operation,
  }) {
    final existing = intents[itemId];
    if (existing != null && existing.ownerId == ownerId) return existing;
    final id =
        widget.generateIntentId?.call() ??
        'shop:$operation:$itemId:${DateTime.now().toUtc().microsecondsSinceEpoch}:${_requestSequence++}';
    final intent = _RewardIntent(ownerId: ownerId, idempotencyKey: id);
    intents[itemId] = intent;
    return intent;
  }

  void _reloadSession() {
    final rewards = _rewards;
    if (rewards == null || !mounted) return;
    setState(() {
      _session = _loadCurrentSession();
    });
  }

  @override
  void dispose() {
    unawaited(_appearanceSubscription?.cancel());
    super.dispose();
  }

  Future<void> _showDetail({
    required RewardCatalogItem item,
    required bool owned,
    required bool equipped,
    required Map<String, String> equippedBySlot,
  }) {
    final previewThemeId = item.kind == RewardItemKind.theme
        ? item.id
        : equippedBySlot['theme'];
    final previewWallpaperId = item.kind == RewardItemKind.wallpaper
        ? item.id
        : equippedBySlot['wallpaper'];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => _CatalogDetailSheet(
        item: item,
        owned: owned,
        equipped: equipped,
        previewThemeId: previewThemeId,
        previewWallpaperId: previewWallpaperId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ร้านค้ารางวัล'),
      ),
      body: _hasAppearanceSnapshot && _activeAppearanceOwnerId == null
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'กำลังโหลดร้านค้ารางวัล',
              ),
            )
          : FutureBuilder<RewardSession>(
              future: _session,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: const Text(
                            'ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _reloadSession,
                          child: const Text('ลองใหม่'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'กำลังโหลดร้านค้ารางวัล',
                    ),
                  );
                }
                final session = snapshot.data!;
                if (_hasAppearanceSnapshot &&
                    session.ownerId != _activeAppearanceOwnerId) {
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'กำลังโหลดร้านค้ารางวัล',
                    ),
                  );
                }
                final account = session.account;
                return ListView(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 360 ? 16 : 20,
                  ),
                  children: [
                    Semantics(
                      label: 'เหรียญคงเหลือ ${account.balance} เหรียญ',
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.toll_outlined),
                          title: const Text('เหรียญคงเหลือ'),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${account.balance}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              Text(
                                'มีรายการรับและใช้เหรียญ ${account.transactionCount} รายการ',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'เลือกหมวดหมู่',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final section in _CatalogSection.values) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: ChoiceChip(
                                key: ValueKey<String>(
                                  'shop-filter-${section.key}',
                                ),
                                label: Text(section.label),
                                selected: _section == section,
                                onSelected: (_) =>
                                    setState(() => _section = section),
                              ),
                            ),
                            if (section != _CatalogSection.values.last)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 12.0;
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1);
                        final minimumTileWidth =
                            320.0 + (textScale - 1).clamp(0.0, 1.0) * 80.0;
                        final possibleColumns =
                            ((constraints.maxWidth + gap) /
                                    (minimumTileWidth + gap))
                                .floor();
                        final columnCount = possibleColumns < 1
                            ? 1
                            : possibleColumns > 3
                            ? 3
                            : possibleColumns;
                        final tileWidth =
                            (constraints.maxWidth - gap * (columnCount - 1)) /
                            columnCount;

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final item in _section.items)
                              SizedBox(
                                width: tileWidth,
                                child: _CatalogTile(
                                  item: item,
                                  owned:
                                      item.price == 0 ||
                                      account.ownedItemIds.contains(item.id),
                                  equipped:
                                      account.equippedBySlot[item.slot] ==
                                      item.id,
                                  busy: _busyItems.contains(item.id),
                                  onPurchase: () =>
                                      _confirmPurchase(item, session),
                                  onEquip: () => _equip(item, session),
                                  onOpenDetail: () => _showDetail(
                                    item: item,
                                    owned:
                                        item.price == 0 ||
                                        account.ownedItemIds.contains(item.id),
                                    equipped:
                                        account.equippedBySlot[item.slot] ==
                                        item.id,
                                    equippedBySlot: account.equippedBySlot,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}

final class _RewardIntent {
  const _RewardIntent({required this.ownerId, required this.idempotencyKey});

  final String ownerId;
  final String idempotencyKey;
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onPurchase,
    required this.onEquip,
    required this.onOpenDetail,
  });

  final RewardCatalogItem item;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onPurchase;
  final VoidCallback onEquip;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_icon(item.kind), size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(item.description),
                  Text('${item.price} เหรียญ'),
                  TextButton.icon(
                    key: ValueKey<String>('reward-detail-${item.id}'),
                    onPressed: onOpenDetail,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('ดูตัวอย่าง'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'กำลังดำเนินการกับ ${item.name}',
                ),
              )
            else if (equipped)
              const Chip(label: Text('กำลังใช้'))
            else
              SizedBox(
                height: 48,
                child: owned
                    ? OutlinedButton(
                        key: ValueKey<String>('reward-equip-${item.id}'),
                        onPressed: onEquip,
                        child: const Text('ใช้งาน'),
                      )
                    : FilledButton(
                        key: ValueKey<String>('reward-purchase-${item.id}'),
                        onPressed: onPurchase,
                        child: const Text('ซื้อ'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _CatalogSection {
  themes('theme', 'ธีม'),
  wallpapers('wallpaper', 'พื้นหลัง'),
  decorations('decoration', 'ของตกแต่ง');

  const _CatalogSection(this.key, this.label);

  final String key;
  final String label;

  Iterable<RewardCatalogItem> get items => RewardCatalog.items.where(
    (item) => switch (this) {
      themes => item.kind == RewardItemKind.theme,
      wallpapers => item.kind == RewardItemKind.wallpaper,
      decorations =>
        item.kind != RewardItemKind.theme &&
            item.kind != RewardItemKind.wallpaper,
    },
  );
}

class _CatalogDetailSheet extends StatelessWidget {
  const _CatalogDetailSheet({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.previewThemeId,
    required this.previewWallpaperId,
  });

  final RewardCatalogItem item;
  final bool owned;
  final bool equipped;
  final String? previewThemeId;
  final String? previewWallpaperId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = switch (item.kind) {
      RewardItemKind.theme => [
        scheme.primaryContainer,
        scheme.secondaryContainer,
      ],
      RewardItemKind.wallpaper => [
        scheme.tertiaryContainer,
        scheme.surfaceContainerHighest,
      ],
      _ => [scheme.secondaryContainer, scheme.surfaceContainerHighest],
    };
    final status = equipped
        ? 'กำลังใช้'
        : owned
        ? 'เป็นเจ้าของแล้ว'
        : '${item.price} เหรียญ';
    final isAppearance =
        item.kind == RewardItemKind.theme ||
        item.kind == RewardItemKind.wallpaper;
    final previewTheme = Theme.of(context).brightness == Brightness.dark
        ? M3Theme.darkThemeFor(
            themeId: previewThemeId,
            wallpaperId: previewWallpaperId,
          )
        : M3Theme.lightThemeFor(
            themeId: previewThemeId,
            wallpaperId: previewWallpaperId,
          );
    final preview = isAppearance
        ? Theme(
            data: previewTheme,
            child: Builder(
              builder: (previewContext) {
                final theme = Theme.of(previewContext);
                final previewScheme = theme.colorScheme;
                return Semantics(
                  key: ValueKey<String>('reward-preview-${item.id}'),
                  image: true,
                  excludeSemantics: true,
                  label: 'ตัวอย่าง${item.name} · $status',
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 220),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: previewScheme.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'บทเรียนวันนี้',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'ทบทวนคำศัพท์',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                const LinearProgressIndicator(value: 0.6),
                                const SizedBox(height: 8),
                                const Text('3 คำ · ประมาณ 4 นาที'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: previewScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'ฝึกต่อ',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: previewScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        : Semantics(
            key: ValueKey<String>('reward-preview-${item.id}'),
            image: true,
            excludeSemantics: true,
            label: 'ตัวอย่าง${item.name} · $status',
            child: Container(
              constraints: const BoxConstraints(minHeight: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              child: Center(
                child: Icon(
                  _icon(item.kind),
                  size: 72,
                  color: scheme.onSurface,
                ),
              ),
            ),
          );

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ตัวอย่าง${item.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              preview,
              const SizedBox(height: 16),
              Text(item.description),
              const SizedBox(height: 8),
              Text(status, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('ปิดตัวอย่าง'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _icon(RewardItemKind kind) => switch (kind) {
  RewardItemKind.theme => Icons.palette_outlined,
  RewardItemKind.wallpaper => Icons.wallpaper_outlined,
  RewardItemKind.headgear => Icons.face_outlined,
  RewardItemKind.weapon => Icons.sports_martial_arts_outlined,
  RewardItemKind.armor => Icons.shield_outlined,
  RewardItemKind.relic => Icons.diamond_outlined,
};
