import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/domain/avatar_progression_policy.dart';
import '../features/rewards/domain/reward_models.dart';
import '../runtime/app_dependencies.dart';

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
  var _requestSequence = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rewards =
        widget.rewards ?? AppDependenciesScope.maybeOf(context)?.rewards;
    if (!identical(_rewards, rewards)) {
      _rewards = rewards;
      _state = _loadAvatar();
    }
    _state ??= _loadAvatar();
  }

  Future<AvatarRewardState> _loadAvatar() {
    final rewards = _rewards;
    return rewards == null
        ? Future<AvatarRewardState>.error(
            StateError('reward dependency unavailable'),
          )
        : rewards.loadAvatar();
  }

  void _reload() {
    setState(() {
      _state = _loadAvatar();
    });
  }

  Future<void> _purchase(RewardCatalogItem item) async {
    final rewards = _rewards;
    if (rewards == null || _busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    try {
      final result = await rewards.purchase(
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        idempotencyKey: _operationKey('purchase', item),
      );
      if (!mounted) return;
      setState(() {
        _state = rewards.loadAvatar();
      });
      final text = result.status == PurchaseStatus.purchased
          ? 'ซื้อรายการและบันทึกในเครื่องแล้ว'
          : 'รายการนี้เป็นของคุณอยู่แล้ว';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } on RewardException catch (error) {
      if (!mounted) return;
      final text = switch (error.code) {
        RewardFailureCode.insufficientBalance => 'เหรียญไม่เพียงพอ',
        RewardFailureCode.lockedByProgression =>
          'เลเวลอวาตาร์ยังไม่ถึงเงื่อนไข',
        RewardFailureCode.staleCatalog =>
          'ข้อมูลราคาเปลี่ยนแล้ว กรุณาเปิดหน้าใหม่',
        RewardFailureCode.evidenceUnavailable =>
          'ข้อมูลรางวัลกำลังรอตรวจสอบ กรุณาลองใหม่ภายหลัง',
        _ => 'ไม่สามารถซื้อรายการนี้ได้',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  Future<void> _equip(RewardCatalogItem item) async {
    final rewards = _rewards;
    if (rewards == null || _busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    try {
      await rewards.equip(
        item.id,
        idempotencyKey: _operationKey('equip', item),
      );
      if (!mounted) return;
      setState(() {
        _state = rewards.loadAvatar();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ใช้งานรายการนี้แล้ว')));
    } on RewardException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == RewardFailureCode.evidenceUnavailable
                ? 'ข้อมูลรางวัลกำลังรอตรวจสอบ กรุณาลองใหม่ภายหลัง'
                : 'ต้องเป็นเจ้าของรายการก่อนใช้งาน',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  String _operationKey(String operation, RewardCatalogItem item) {
    final sequence = _requestSequence++;
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'avatar:$operation:${item.id}:$now:$sequence';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ร้านค้ารางวัล')),
      body: FutureBuilder<AvatarRewardState>(
        future: _state,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snapshot.data!;
          final account = state.account;
          final progression = state.progression;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AvatarLevelCard(progression: progression),
              const SizedBox(height: 8),
              Semantics(
                label: 'เหรียญคงเหลือ ${account.coinBalance} เหรียญ',
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.toll_outlined),
                    title: const Text('เหรียญคงเหลือ'),
                    trailing: Text(
                      '${account.coinBalance}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    subtitle: Text(
                      'ธุรกรรม ${account.transactionCount} รายการ · '
                      'แค็ตตาล็อก v${account.catalogVersion}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in RewardCatalog.items)
                _CatalogTile(
                  item: item,
                  unlocked: progression.isItemUnlocked(item.id),
                  owned:
                      item.price == 0 || account.ownedItemIds.contains(item.id),
                  equipped: account.equippedBySlot[item.slot] == item.id,
                  busy: _busyItems.contains(item.id),
                  onPurchase: () => _purchase(item),
                  onEquip: () => _equip(item),
                ),
            ],
          );
        },
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
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('เลเวลอวาตาร์'),
          trailing: Text(
            'Level ${progression.level}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('XP สะสม ${progression.lifetimeXp}'),
              Text(
                'อีก ${progression.xpUntilNextLevel} XP '
                'ถึง Level ${progression.level + 1}',
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  });

  final RewardCatalogItem item;
  final bool unlocked;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onPurchase;
  final VoidCallback onEquip;

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
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (equipped)
              const Chip(label: Text('กำลังใช้'))
            else if (owned)
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onEquip,
                  child: const Text('ใช้งาน'),
                ),
              )
            else if (!unlocked)
              Chip(label: Text('ปลดล็อกที่ Level ${item.requiredAvatarLevel}'))
            else
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: onPurchase,
                  child: const Text('ซื้อ'),
                ),
              ),
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
