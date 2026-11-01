import 'dart:async';

import 'package:flutter/material.dart';

import '../../progress/application/progress_use_cases.dart';
import '../../progress/domain/progress_models.dart';
import '../../progress/presentation/progress_host_binding.dart';
import '../../rewards/domain/reward_models.dart';

class AvatarProgressPanel extends StatefulWidget {
  const AvatarProgressPanel({
    super.key,
    required this.ownerId,
    required this.account,
    required this.stillCurrent,
    this.progress,
    this.loader,
  });
  final String ownerId;
  final RewardAccount account;
  final bool Function() stillCurrent;
  final ProgressUseCases? progress;
  final ProgressLoader? loader;
  @override
  State<AvatarProgressPanel> createState() => _AvatarProgressPanelState();
}

class _AvatarProgressPanelState extends State<AvatarProgressPanel> {
  ProgressSnapshot? _progress;
  var _failed = false;
  var _read = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final read = ++_read;
    bool current() => mounted && read == _read && widget.stillCurrent();
    try {
      final value = widget.loader != null
          ? await widget.loader!()
          : await widget.progress!.loadForOwner(
              expectedOwnerId: widget.ownerId,
              stillCurrent: current,
            );
      if (!current()) return;
      setState(() {
        _progress = value;
        _failed = false;
      });
    } on Object {
      if (current()) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('อวตารของคุณ', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          AvatarCosmeticPreview(account: widget.account),
          const SizedBox(height: 12),
          if (progress != null) ...[
            Text(
              'ระดับอวตาร ${progress.gameLevel}',
              key: const ValueKey('avatar-canonical-level'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${progress.totalXp} XP จากการเรียนและภารกิจที่บันทึก'),
            const Text('ระดับอวตารเป็นรางวัลการร่วมฝึก ไม่ใช่ระดับภาษา'),
          ] else if (_failed) ...[
            const Text('ยังอ่านระดับอวตารไม่ได้ ของตกแต่งยังใช้งานได้'),
            TextButton(
              onPressed: _load,
              child: const Text('อ่านระดับอีกครั้ง'),
            ),
          ] else
            const Text('กำลังอ่านระดับจากข้อมูลที่บันทึก'),
          const SizedBox(height: 8),
          const Text(
            'ปลดล็อกของตกแต่งด้วยเหรียญตามราคาที่แสดง '
            'การดูตัวอย่างไม่ซื้อหรือเปลี่ยนอุปกรณ์',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _read++;
    super.dispose();
  }
}

class AvatarCosmeticPreview extends StatelessWidget {
  const AvatarCosmeticPreview({super.key, required this.account, this.preview});
  final RewardAccount account;
  final RewardCatalogItem? preview;

  @override
  Widget build(BuildContext context) {
    final cosmetics = RewardCatalog.items.where(
      (item) =>
          item.kind != RewardItemKind.theme &&
          item.kind != RewardItemKind.wallpaper,
    );
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 192,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 100,
                    color: scheme.onSurface,
                  ),
                  for (final item in cosmetics)
                    if (preview?.id == item.id ||
                        (preview?.slot != item.slot &&
                            account.equippedBySlot[item.slot] == item.id))
                      Align(
                        alignment: switch (item.kind) {
                          RewardItemKind.headgear => Alignment.topCenter,
                          RewardItemKind.armor => Alignment.bottomCenter,
                          _ => Alignment.centerRight,
                        },
                        child: Semantics(
                          image: true,
                          label: item.name,
                          child: Icon(
                            switch (item.kind) {
                              RewardItemKind.headgear => Icons.school_outlined,
                              RewardItemKind.armor => Icons.shield_outlined,
                              _ => Icons.sports_martial_arts_outlined,
                            },
                            size: 40,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in cosmetics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${item.name} · ${preview?.id == item.id
                    ? 'กำลังดูตัวอย่าง'
                    : account.equippedBySlot[item.slot] == item.id
                    ? 'กำลังใช้'
                    : account.ownedItemIds.contains(item.id)
                    ? 'เป็นเจ้าของแล้ว'
                    : 'ยังไม่ปลดล็อก · ${item.price} เหรียญ'}',
              ),
            ),
          if (preview != null)
            const Text('ตัวอย่างเท่านั้น อุปกรณ์ที่ใช้จริงยังไม่เปลี่ยน'),
        ],
      ),
    );
  }
}
