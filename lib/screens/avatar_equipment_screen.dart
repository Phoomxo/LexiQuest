import 'dart:async';
import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/domain/avatar_progression_policy.dart';
import '../features/rewards/domain/reward_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/reward_avatar_preview.dart';

class AvatarEquipmentScreen extends StatefulWidget {
  const AvatarEquipmentScreen({super.key, this.rewards});

  final RewardUseCases? rewards;

  @override
  State<AvatarEquipmentScreen> createState() => _AvatarEquipmentScreenState();
}

class _AvatarEquipmentScreenState extends State<AvatarEquipmentScreen> {
  RewardUseCases? _rewards;
  Future<AvatarRewardState>? _state;
  final Set<String> _busyItems = <String>{};
  final Map<String, String> _itemMessages = <String, String>{};
  final Set<String> _checkingItems = <String>{};
  final ScrollController _scrollController = ScrollController();
  String? _previewItemId;
  var _previewGeneration = 0;
  var _requestSequence = 0;
  var _authorityGeneration = 0;

  var _readGeneration = 0;
  var _pending = false;
  var _active = false;
  var _exited = false;
  var _ownerEpoch = 0;
  var _ownerReady = false;
  String? _ownerId;
  StreamSubscription<({String ownerId, String? firebaseUid})?>?
  _ownerSubscription;

  bool get _visible =>
      !_exited &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;
  bool _current(int authority, int read) =>
      mounted &&
      !_exited &&
      _active &&
      authority == _authorityGeneration &&
      read == _readGeneration &&
      _visible;

  @override
  void didUpdateWidget(covariant AvatarEquipmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  void _retire() {
    _authorityGeneration++;
    _readGeneration++;
    _pending = false;
    _state = null;
    _busyItems.clear();
    _checkingItems.clear();
    _itemMessages.clear();
    _previewItemId = null;
  }

  void _bind() {
    final rewards =
        widget.rewards ?? AppDependenciesScope.maybeOf(context)?.rewards;
    final active = _visible;
    if (identical(rewards, _rewards) && active == _active) return;
    _retire();
    _rewards = rewards;
    _active = active;
    _observeOwner();
  }

  void _observeOwner() {
    final epoch = ++_ownerEpoch;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _ownerId = null;
    _ownerReady = false;
    if (!_active || _exited) return;
    if (_rewards == null) {
      _state = _loadAvatar();
      return;
    }
    _ownerSubscription = _rewards!.progress.watchProfileOwner().listen(
      (owner) {
        if (!mounted || _exited || epoch != _ownerEpoch) return;
        setState(() {
          _retire();
          _ownerReady = true;
          _ownerId = owner?.ownerId;
          _state = _loadAvatar();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _ownerEpoch) return;
        setState(() {
          _retire();
          _ownerReady = false;
          _ownerId = null;
          _state = Future<AvatarRewardState>.error(error, stack);
          _state!.ignore();
        });
      },
    );
  }

  Future<AvatarRewardState> _loadAvatar() {
    final rewards = _rewards;
    final authority = _authorityGeneration;
    final read = ++_readGeneration;
    final ownerId = _ownerId;
    _pending = true;
    final load = Future<AvatarRewardState>.sync(() async {
      if (rewards == null || ownerId == null)
        throw StateError('reward dependency unavailable');
      final state = await rewards.loadAvatar();
      final currentOwner = await rewards.owners.getOrCreateActiveOwner();
      if (state.ownerId != ownerId || currentOwner.id != ownerId) {
        throw const RewardException(RewardFailureCode.evidenceUnavailable);
      }
      return state;
    });
    load.then<void>(
      (_) {
        if (!_current(authority, read)) return;
        _pending = false;
        for (final itemId in _checkingItems) {
          _itemMessages.remove(itemId);
        }
        _checkingItems.clear();
      },
      onError: (Object _, StackTrace __) {
        if (_current(authority, read)) _pending = false;
      },
    );
    return load;
  }

  void _reload(int authority, int read) {
    if (!_current(authority, read) || _pending) return;
    setState(() {
      _previewItemId = null;
      if (!_ownerReady && _rewards != null) {
        _retire();
        _observeOwner();
      } else {
        _state = _loadAvatar();
      }
    });
  }

  void _preview(RewardCatalogItem item, int authority, int read) {
    if (!_current(authority, read)) return;
    final preview = ++_previewGeneration;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    setState(() => _previewItemId = item.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_current(authority, read) ||
          preview != _previewGeneration ||
          _previewItemId != item.id ||
          !_scrollController.hasClients)
        return;
      if (disableAnimations) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController
            .animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            )
            .ignore();
      }
    });
  }

  void _exit() {
    _exited = true;
    _ownerEpoch++;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _retire();
  }

  @override
  void dispose() {
    _exit();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _purchase(
    RewardCatalogItem item,
    int generation,
    int read,
    String? ownerId,
  ) async {
    final rewards = _rewards;
    bool current() =>
        _current(generation, read) && ownerId != null && ownerId == _ownerId;
    if (!current() ||
        rewards == null ||
        _pending ||
        _busyItems.contains(item.id))
      return;
    setState(() {
      _busyItems.add(item.id);
      _itemMessages.remove(item.id);
    });
    try {
      final result = await rewards.purchase(
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        idempotencyKey: _operationKey('purchase', item),
        mutationAllowed: current,
        expectedOwnerId: ownerId,
      );
      if (!mounted || !current()) return;
      final text = result.status == PurchaseStatus.purchased
          ? 'ซื้อรายการและบันทึกในเครื่องแล้ว'
          : 'รายการนี้เป็นของคุณอยู่แล้ว';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } on Object catch (error) {
      if (!mounted || !current()) return;
      final text = switch (error is RewardException ? error.code : null) {
        RewardFailureCode.insufficientBalance => 'เหรียญไม่เพียงพอ',
        RewardFailureCode.lockedByProgression =>
          'เลเวลอวาตาร์ยังไม่ถึงเงื่อนไข',
        RewardFailureCode.staleCatalog =>
          'ข้อมูลราคาเปลี่ยนแล้ว กรุณาเปิดหน้าใหม่',
        RewardFailureCode.evidenceUnavailable =>
          'ข้อมูลรางวัลกำลังรอตรวจสอบ กรุณาลองใหม่ภายหลัง',
        _ => 'การบันทึกขัดข้อง กำลังตรวจสอบสถานะรายการล่าสุด',
      };
      _itemMessages[item.id] = text;
      if (error is! RewardException) _checkingItems.add(item.id);
      if (!_checkingItems.contains(item.id)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (current()) _reconcileItems();
    }
  }

  Future<void> _equip(
    RewardCatalogItem item,
    int generation,
    int read,
    String? ownerId,
  ) async {
    final rewards = _rewards;
    bool current() =>
        _current(generation, read) && ownerId != null && ownerId == _ownerId;
    if (!current() ||
        rewards == null ||
        _pending ||
        _busyItems.contains(item.id))
      return;
    setState(() {
      _busyItems.add(item.id);
      _itemMessages.remove(item.id);
    });
    try {
      await rewards.equip(
        item.id,
        idempotencyKey: _operationKey('equip', item),
        mutationAllowed: current,
        expectedOwnerId: ownerId,
      );
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกรายการที่เลือกใช้งานแล้ว')),
      );
    } on Object catch (error) {
      if (!mounted || !current()) return;
      final message =
          error is RewardException &&
              error.code == RewardFailureCode.evidenceUnavailable
          ? 'ข้อมูลรางวัลกำลังรอตรวจสอบ กรุณาลองใหม่ภายหลัง'
          : 'ยังยืนยันการใช้งานไม่ได้ กำลังตรวจสอบสถานะรายการล่าสุด';
      _itemMessages[item.id] = message;
      if (error is! RewardException ||
          error.code != RewardFailureCode.evidenceUnavailable) {
        _checkingItems.add(item.id);
      }
      if (!_checkingItems.contains(item.id)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (current()) _reconcileItems();
    }
  }

  void _reconcileItems() {
    final authority = _authorityGeneration;
    _previewItemId = null;
    final load = _loadAvatar();
    final read = _readGeneration;
    final next = load.whenComplete(() {
      // This read retires all callbacks from the preceding displayed receipt.
      if (_current(authority, read)) _busyItems.clear();
    });
    next.ignore();
    setState(() {
      _state = next;
    });
  }

  String _operationKey(String operation, RewardCatalogItem item) {
    final sequence = _requestSequence++;
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'avatar:$operation:${item.id}:$now:$sequence';
  }

  Map<String, Object?> _itemContext(
    AvatarRewardState state,
    RewardCatalogItem item,
  ) => {
    'itemId': item.id,
    'priceCoins': item.price,
    'catalogVersion': item.catalogVersion,
    'unlocked': state.progression.isItemUnlocked(item.id),
    'owned': item.price == 0 || state.account.ownedItemIds.contains(item.id),
    'equipped': state.account.equippedBySlot[item.slot] == item.id,
    'previewing': _previewItemId == item.id,
    'busy': _busyItems.contains(item.id),
    'interpretation': 'preview-is-not-purchase-or-equip',
  };

  Widget _withItemContext(
    AvatarRewardState state,
    RewardCatalogItem item,
    Widget child,
  ) {
    if (state.ownerId == null) return child;
    return MenuActionBinding(
      id: 'rewards/item/${item.id}',
      label: 'Reward catalog item',
      ownerId: state.ownerId,
      onInvoke: null,
      readValue: jsonEncode(_itemContext(state, item)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authority = _authorityGeneration;
    final read = _readGeneration;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_exited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ร้านค้ารางวัล')),
        body: !_active || _exited
            ? const SizedBox.shrink()
            : FutureBuilder<AvatarRewardState>(
                key: ValueKey((authority, read)),
                future: _state,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasError) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
                            if (_checkingItems.isNotEmpty)
                              const Text(
                                'ยังยืนยันสถานะรายการไม่ได้ ลองอ่านข้อมูลอีกครั้งโดยไม่บันทึกซ้ำ',
                              ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => _reload(authority, read),
                              child: const Text('ลองใหม่'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done ||
                      !snapshot.hasData) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          if (_checkingItems.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('กำลังตรวจสอบสถานะรายการล่าสุด'),
                          ],
                        ],
                      ),
                    );
                  }
                  final state = snapshot.data!;
                  final account = state.account;
                  final progression = state.progression;
                  final equippedHeadgear = account.equippedBySlot['headgear'];
                  final visibleHeadgear = _previewItemId ?? equippedHeadgear;
                  final isPreviewing = _previewItemId != null;
                  final preview = _previewGeneration;
                  Widget body = ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _AvatarPreviewPanel(
                        catalogVersion: account.catalogVersion,
                        itemId: visibleHeadgear,
                        previewing: isPreviewing,
                        onCancelPreview: isPreviewing
                            ? () {
                                if (_current(authority, read) &&
                                    preview == _previewGeneration) {
                                  setState(() {
                                    _previewGeneration++;
                                    _previewItemId = null;
                                  });
                                }
                              }
                            : null,
                      ),
                      _AvatarLevelCard(progression: progression),
                      Semantics(
                        label: 'เหรียญคงเหลือ ${account.coinBalance} เหรียญ',
                        child: Card(
                          child: _RewardMetricLayout(
                            icon: Icons.toll_outlined,
                            title: 'เหรียญคงเหลือ',
                            value: Text(
                              '${account.coinBalance}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            summary: Text(
                              'ธุรกรรม ${account.transactionCount} รายการ',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ขณะนี้ภาพรองรับตัวละครพื้นฐานและหมวก IPA เท่านั้น',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      for (final item in RewardCatalog.items)
                        _CatalogTile(
                          item: item,
                          unlocked: progression.isItemUnlocked(item.id),
                          owned:
                              item.price == 0 ||
                              account.ownedItemIds.contains(item.id),
                          equipped:
                              account.equippedBySlot[item.slot] == item.id,
                          busy: _busyItems.contains(item.id),
                          message: _itemMessages[item.id],
                          canPreview: RewardAvatarPreview.supports(
                            catalogVersion: item.catalogVersion,
                            itemId: item.id,
                          ),
                          previewing: _previewItemId == item.id,
                          onPreview: () => _preview(item, authority, read),
                          onPurchase: () =>
                              _purchase(item, authority, read, state.ownerId),
                          onEquip: () =>
                              _equip(item, authority, read, state.ownerId),
                        ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('รายละเอียดบัญชีรางวัล'),
                        children: [
                          Text('แค็ตตาล็อก v${account.catalogVersion}'),
                        ],
                      ),
                    ],
                  );
                  if (state.ownerId == null) return body;
                  // Keep finite catalog metadata mounted independently of lazy tiles.
                  for (final item in RewardCatalog.items) {
                    body = _withItemContext(state, item, body);
                  }
                  return MenuActionBinding(
                    id: 'rewards/account',
                    label: 'Reward account evidence',
                    ownerId: state.ownerId,
                    onInvoke: null,
                    readValue: jsonEncode({
                      'coinBalance': account.coinBalance,
                      'lifetimeXp': progression.lifetimeXp,
                      'level': progression.level,
                      'xpUntilNextLevel': progression.xpUntilNextLevel,
                      'catalogVersion': account.catalogVersion,
                      // Catalog state must not depend on which lazy tiles are mounted.
                      'catalogScope': 'complete-current-catalog',
                      'previewItemId': _previewItemId,
                      'previewIsEquipped': false,
                      'previewing': isPreviewing,
                      'mutationPending':
                          _busyItems.isNotEmpty || _checkingItems.isNotEmpty,
                      'interpretation':
                          'coins-are-spendable-xp-is-lifetime-not-language-proficiency',
                    }),
                    child: body,
                  );
                },
              ),
      ),
    );
  }
}

class _AvatarPreviewPanel extends StatelessWidget {
  const _AvatarPreviewPanel({
    required this.catalogVersion,
    required this.itemId,
    required this.previewing,
    required this.onCancelPreview,
  });

  final int catalogVersion;
  final String? itemId;
  final bool previewing;
  final VoidCallback? onCancelPreview;

  @override
  Widget build(BuildContext context) {
    final supported =
        itemId != null &&
        RewardAvatarPreview.supports(
          catalogVersion: catalogVersion,
          itemId: itemId!,
        );
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RewardAvatarPreview(
              catalogVersion: catalogVersion,
              itemId: itemId,
              size: 144,
            ),
            const SizedBox(height: 8),
            Text(
              previewing
                  ? 'กำลังลองหมวก IPA'
                  : supported
                  ? 'สวมหมวก IPA'
                  : 'ตัวละครของฉัน',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              previewing
                  ? 'ลองดูเท่านั้น ยังไม่ได้ซื้อหรือสวม'
                  : supported
                  ? 'อุปกรณ์ที่เลือกใช้งานอยู่'
                  : itemId == null
                  ? 'ยังไม่ได้สวมหมวก'
                  : 'ภาพอุปกรณ์นี้ยังไม่พร้อม',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (previewing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onCancelPreview,
                child: const Text('เลิกลอง'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvatarLevelCard extends StatelessWidget {
  const _AvatarLevelCard({required this.progression});

  final AvatarProgression progression;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'เลเวลอวาตาร์ ${progression.level} '
          'จาก XP สะสม ${progression.lifetimeXp}',
      child: Card(
        child: _RewardMetricLayout(
          icon: Icons.person_outline,
          title: 'เลเวลอวาตาร์',
          value: Text(
            'เลเวล ${progression.level}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          summary: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('XP สะสม ${progression.lifetimeXp}'),
              Text(
                'อีก ${progression.xpUntilNextLevel} XP '
                'ถึงเลเวล ${progression.level + 1}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardMetricLayout extends StatelessWidget {
  const _RewardMetricLayout({
    required this.icon,
    required this.title,
    required this.value,
    required this.summary,
  });

  final IconData icon;
  final String title;
  final Widget value;
  final Widget summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stackDetails =
          constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(16) >= 24;
      if (!stackDetails) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Icon(icon),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          trailing: value,
          subtitle: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodySmall,
            child: summary,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            value,
            const SizedBox(height: 8),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall,
              child: summary,
            ),
          ],
        ),
      );
    },
  );
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.unlocked,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onPurchase,
    required this.onEquip,
    required this.canPreview,
    required this.previewing,
    required this.onPreview,
    this.message,
  });

  final RewardCatalogItem item;
  final bool unlocked;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onPurchase;
  final VoidCallback onEquip;
  final bool canPreview;
  final bool previewing;
  final VoidCallback onPreview;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('reward-item/${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_icon(item.kind), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description),
                const SizedBox(height: 8),
                Text(owned ? 'เป็นเจ้าของแล้ว' : '${item.price} เหรียญ'),
                Text('เงื่อนไข: เลเวล ${item.requiredAvatarLevel}'),
              ],
            ),
            const SizedBox(height: 12),
            if (canPreview) ...[
              OutlinedButton(
                key: ValueKey('reward-preview/${item.id}'),
                onPressed: previewing ? null : onPreview,
                child: Text(previewing ? 'กำลังลอง' : 'ลองดู'),
              ),
              const SizedBox(height: 8),
            ],
            if (busy)
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('กำลังบันทึกรายการ…')),
                ],
              )
            else if (equipped)
              const Chip(label: Text('กำลังใช้'))
            else if (owned)
              OutlinedButton(
                key: ValueKey('reward-equip/${item.id}'),
                onPressed: onEquip,
                child: const Text('ใช้งาน'),
              )
            else if (!unlocked)
              Text('ปลดล็อกที่เลเวล ${item.requiredAvatarLevel}')
            else
              FilledButton(
                key: ValueKey('reward-purchase/${item.id}'),
                onPressed: onPurchase,
                child: const Text('ซื้อ'),
              ),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
          ],
        ),
      ),
    );
  }

  IconData _icon(RewardItemKind kind) => switch (kind) {
    RewardItemKind.theme => Icons.palette_outlined,
    RewardItemKind.wallpaper => Icons.wallpaper_outlined,
    RewardItemKind.headgear => Icons.face_outlined,
    RewardItemKind.weapon => Icons.sports_martial_arts_outlined,
    RewardItemKind.armor => Icons.shield_outlined,
    RewardItemKind.relic => Icons.diamond_outlined,
  };
}
