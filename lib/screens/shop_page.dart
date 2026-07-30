import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/domain/reward_models.dart';
import '../runtime/app_dependencies.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key, this.rewards});

  final RewardUseCases? rewards;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  RewardUseCases? _rewards;
  Future<RewardAccount>? _account;
  final Set<String> _busyItems = <String>{};
  var _requestSequence = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rewards ??=
        widget.rewards ?? AppDependenciesScope.maybeOf(context)?.rewards;
    _account ??= _rewards == null
        ? Future<RewardAccount>.error(
            StateError('reward dependency unavailable'),
          )
        : _rewards!.load();
  }

  Future<void> _purchase(RewardCatalogItem item) async {
    final rewards = _rewards;
    if (rewards == null || _busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    try {
      final result = await rewards.purchase(
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        idempotencyKey:
            'shop:${item.id}:${DateTime.now().toUtc().microsecondsSinceEpoch}:${_requestSequence++}',
      );
      if (!mounted) return;
      setState(() => _account = Future.value(result.account));
      final text = result.status == PurchaseStatus.purchased
          ? 'ซื้อรายการและบันทึกในเครื่องแล้ว'
          : 'รายการนี้เป็นของคุณอยู่แล้ว';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } on RewardException catch (error) {
      if (!mounted) return;
      final text = switch (error.code) {
        RewardFailureCode.insufficientBalance => 'คะแนนสะสมไม่เพียงพอ',
        RewardFailureCode.staleCatalog =>
          'ข้อมูลราคาเปลี่ยนแล้ว กรุณาเปิดหน้าใหม่',
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
      final account = await rewards.equip(item.id);
      if (!mounted) return;
      setState(() => _account = Future.value(account));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ใช้งานรายการนี้แล้ว')));
    } on RewardException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องเป็นเจ้าของรายการก่อนใช้งาน')),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ร้านค้ารางวัล')),
      body: FutureBuilder<RewardAccount>(
        future: _account,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final account = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Semantics(
                label: 'คะแนนสะสมคงเหลือ ${account.balance} คะแนน',
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.toll_outlined),
                    title: const Text('คะแนนสะสมคงเหลือ'),
                    trailing: Text(
                      '${account.balance}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    subtitle: Text(
                      'ธุรกรรม ${account.transactionCount} รายการ · แค็ตตาล็อก v${account.catalogVersion}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in RewardCatalog.items)
                _CatalogTile(
                  item: item,
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

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onPurchase,
    required this.onEquip,
  });

  final RewardCatalogItem item;
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
                  Text('${item.price} คะแนน'),
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
            else
              SizedBox(
                height: 48,
                child: owned
                    ? OutlinedButton(
                        onPressed: onEquip,
                        child: const Text('ใช้งาน'),
                      )
                    : FilledButton(
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
