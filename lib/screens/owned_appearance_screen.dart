import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config/m3_theme.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/domain/reward_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

class OwnedAppearanceScreen extends StatefulWidget {
  const OwnedAppearanceScreen({
    super.key,
    this.wallpaper = false,
    this.rewards,
    this.initialItemId,
    this.expectedOwnerId,
    required this.returnLabel,
    this.onOpenOther,
  });

  final bool wallpaper;
  final RewardUseCases? rewards;
  final String? initialItemId;
  final String? expectedOwnerId;
  final String returnLabel;
  final Future<void> Function(BuildContext context, String ownerId)?
  onOpenOther;

  @override
  State<OwnedAppearanceScreen> createState() => _OwnedAppearanceScreenState();
}

class _OwnedAppearanceScreenState extends State<OwnedAppearanceScreen> {
  AppDependencies? _scope;
  RewardUseCases? _rewards;
  StreamSubscription<void>? _ownerWrites;
  StreamSubscription<RewardAppearance>? _appearance;
  RewardSession? _session;
  RewardCatalogItem? _preview;
  RewardCatalogItem? _applied;
  String? _boundOwner;
  String? _intentKey;
  String? _error;
  bool _bound = false;
  bool _invalidated = false;
  bool _busy = false;
  bool _openingOther = false;

  bool get _current =>
      mounted &&
      !_invalidated &&
      identical(_scope, AppDependenciesScope.maybeOf(context)) &&
      ModalRoute.isCurrentOf(context) == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppDependenciesScope.maybeOf(context);
    if (_bound) {
      if (!identical(_scope, scope)) _invalidate();
      return;
    }
    _bound = true;
    _scope = scope;
    final rewards = _rewards = widget.rewards ?? scope?.rewards;
    if (rewards == null ||
        (scope?.rewards != null && !identical(rewards, scope?.rewards))) {
      _invalidate();
      return;
    }
    _boundOwner = widget.expectedOwnerId;
    if (scope?.database == null) {
      _appearance = rewards.watchAppearance().listen((appearance) {
        final owner = _boundOwner;
        if (owner != null && appearance.ownerId != owner) _invalidate();
      }, onError: (Object _) => _invalidate());
    } else {
      _ownerWrites = scope?.watchLocalOwnerWrites()?.listen(
        (_) => _invalidate(),
        onError: (Object _) => _invalidate(),
      );
    }
    unawaited(_load(rewards, initial: true));
  }

  @override
  void didUpdateWidget(covariant OwnedAppearanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.rewards, oldWidget.rewards) ||
        widget.expectedOwnerId != oldWidget.expectedOwnerId) {
      _invalidate();
    }
  }

  Future<void> _load(RewardUseCases rewards, {bool initial = false}) async {
    try {
      final session = await rewards.loadSession();
      if (!mounted || _invalidated) return;
      final owner = _boundOwner ?? widget.expectedOwnerId;
      if ((owner != null && session.ownerId != owner) ||
          !await _ownerMatches(session.ownerId)) {
        _invalidate();
        return;
      }
      if (!mounted || _invalidated) return;
      final initialItem = RewardCatalog.byId(widget.initialItemId ?? '');
      setState(() {
        _boundOwner = session.ownerId;
        _session = session;
        if (initial && initialItem != null && _canUse(initialItem, session)) {
          _preview = initialItem;
        }
      });
    } catch (_) {
      _invalidate();
    }
  }

  Future<bool> _ownerMatches(String ownerId) async {
    if (_scope?.database == null) {
      return (await _rewards!.owners.getOrCreateActiveOwner()).id == ownerId;
    }
    return await _scope?.readActiveOwnerId() == ownerId;
  }

  bool _canUse(RewardCatalogItem item, RewardSession session) =>
      (widget.wallpaper
          ? item.kind == RewardItemKind.wallpaper
          : item.kind == RewardItemKind.headgear ||
                item.kind == RewardItemKind.weapon ||
                item.kind == RewardItemKind.armor ||
                item.kind == RewardItemKind.relic) &&
      (item.id == RewardCatalog.defaultWallpaper.id ||
          session.account.ownedItemIds.contains(item.id));

  String? _currentItemId(RewardCatalogItem item, RewardSession session) =>
      session.account.equippedBySlot[item.slot] ??
      (widget.wallpaper ? RewardCatalog.defaultWallpaper.id : null);

  void _invalidate() {
    if (!mounted || _invalidated) return;
    setState(() {
      _invalidated = true;
      _session = null;
      _preview = null;
      _applied = null;
      _intentKey = null;
      _error = null;
    });
  }

  void _showPreview(RewardCatalogItem item) {
    if (!_current || _busy) return;
    setState(() {
      _preview = item;
      _intentKey = null;
      _error = null;
    });
  }

  void _cancel() {
    setState(() {
      _preview = null;
      _intentKey = null;
      _error = null;
    });
  }

  Future<void> _equip(RewardCatalogItem item) async {
    final session = _session;
    final rewards = _rewards;
    if (!_current ||
        _busy ||
        _preview?.id != item.id ||
        session == null ||
        rewards == null) {
      return;
    }
    if (!_canUse(item, session) || _currentItemId(item, session) == item.id) {
      _cancel();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ownerMatches(session.ownerId)) {
        _invalidate();
        return;
      }
      if (!_current) return;
      final result = await rewards.equip(
        expectedOwnerId: session.ownerId,
        itemId: item.id,
        idempotencyKey: _intentKey ??= 'appearance:${const Uuid().v4()}',
      );
      if (!_current) return;
      if (!await _ownerMatches(session.ownerId)) {
        _invalidate();
        return;
      }
      if (!_current) return;
      setState(() {
        _session = RewardSession(
          ownerId: session.ownerId,
          account: result.account,
        );
        _preview = null;
        _applied = result.account.equippedBySlot[item.slot] == item.id
            ? item
            : null;
        _intentKey = null;
      });
    } on RewardException catch (error) {
      if (error.code == RewardFailureCode.ownerChanged) {
        _invalidate();
      } else if (_current) {
        setState(() => _error = 'ใช้รายการนี้ไม่ได้ กรุณาลองใหม่');
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = 'ยังยืนยันผลไม่ได้ ลองกดใช้อีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOther() async {
    final owner = _session?.ownerId;
    final open = widget.onOpenOther;
    final rewards = _rewards;
    if (!_current ||
        open == null ||
        owner == null ||
        rewards == null ||
        _openingOther) {
      return;
    }
    _openingOther = true;
    try {
      if (!await _ownerMatches(owner)) {
        _invalidate();
        return;
      }
      if (!mounted || !_current) return;
      await open(context, owner);
      if (_current) await _load(rewards);
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดหน้านี้ไม่ได้ กรุณาลองใหม่')),
        );
      }
    } finally {
      _openingOther = false;
    }
  }

  @override
  void dispose() {
    unawaited(_ownerWrites?.cancel());
    unawaited(_appearance?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final preview = _preview;
    final applied = _applied;
    final defaultWallpaper = RewardCatalog.defaultWallpaper;
    final title = switch ((preview, applied, widget.wallpaper)) {
      (final item?, _, true) => 'ลอง${item.name}',
      (final item?, _, false) when item.kind == RewardItemKind.headgear =>
        'ลองสวมหมวก',
      (final item?, _, false) => 'ลองใช้${item.name}',
      (_, final item?, true) => 'ใช้${item.name}แล้ว',
      (_, final item?, false) when item.kind == RewardItemKind.headgear =>
        'สวมหมวกแล้ว',
      (_, final item?, false) => 'ใช้${item.name}แล้ว',
      (_, _, true) => 'พื้นหลังหน้าฝึก',
      _ => 'แต่งตัวละคร',
    };
    return PopScope<void>(
      canPop: !_busy && preview == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _preview != null) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(context, title),
        ),
        body: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: SafeArea(
            child: ListView(
              key: ValueKey((preview?.id, applied?.id)),
              padding: const EdgeInsets.all(20),
              children: [
                if (session == null)
                  Text(
                    _invalidated
                        ? 'เปิดของตกแต่งไม่ได้ กรุณากลับไปเปิดใหม่'
                        : 'กำลังโหลดของตกแต่งที่มี',
                  )
                else if (preview != null) ...[
                  _AppearancePreview(item: preview, account: session.account),
                  const SizedBox(height: 16),
                  if (_error case final message?)
                    Semantics(liveRegion: true, child: Text(message)),
                  if (_currentItemId(preview, session) != preview.id)
                    FilledButton(
                      onPressed: _busy ? null : () => _equip(preview),
                      child: Text(
                        widget.wallpaper
                            ? 'ใช้พื้นหลังนี้'
                            : preview.kind == RewardItemKind.headgear
                            ? 'ใช้หมวกใบนี้'
                            : 'ใช้ของชิ้นนี้',
                      ),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(
                      widget.wallpaper ? 'เก็บพื้นหลังเดิม' : 'ยกเลิก',
                    ),
                  ),
                ] else ...[
                  if (widget.wallpaper) ...[
                    _AppearancePreview(
                      item:
                          RewardCatalog.byId(
                            session.account.equippedBySlot['wallpaper'] ?? '',
                          ) ??
                          defaultWallpaper,
                      account: session.account,
                    ),
                    const SizedBox(height: 8),
                  ] else if (applied != null)
                    _AppearancePreview(item: applied, account: session.account),
                  if (!widget.wallpaper &&
                      !RewardCatalog.items.any(
                        (item) => _canUse(item, session),
                      ))
                    const Text('ยังไม่มีอุปกรณ์แต่งตัวละคร'),
                  if (widget.wallpaper &&
                      applied != null &&
                      applied.id != defaultWallpaper.id)
                    OutlinedButton(
                      onPressed: () => _showPreview(defaultWallpaper),
                      child: const Text('ใช้พื้นหลังมาตรฐาน'),
                    ),
                  for (final item in [
                    if (widget.wallpaper) defaultWallpaper,
                    ...RewardCatalog.items.where(
                      (item) => _canUse(item, session),
                    ),
                  ])
                    if (applied?.id != item.id || widget.wallpaper)
                      ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                          _currentItemId(item, session) == item.id
                              ? item.id == defaultWallpaper.id
                                    ? 'มาตรฐาน · กำลังใช้'
                                    : '${item.name} · กำลังใช้'
                              : item.kind == RewardItemKind.headgear
                              ? 'มีแล้ว · แตะเพื่อลองสวม'
                              : 'มีแล้ว · ดูตัวอย่างก่อนใช้',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showPreview(item),
                      ),
                  if (!widget.wallpaper && applied != null)
                    const Text('กำลังใช้'),
                  if (widget.onOpenOther != null)
                    OutlinedButton(
                      onPressed: _openOther,
                      child: Text(
                        widget.wallpaper ? 'ร้านของตกแต่ง' : 'พื้นหลังหน้าฝึก',
                      ),
                    ),
                ],
                if (preview == null)
                  TextButton(
                    onPressed: () => Navigator.maybePop(context),
                    child: Text(widget.returnLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.item, required this.account});

  final RewardCatalogItem item;
  final RewardAccount account;

  @override
  Widget build(BuildContext context) {
    if (item.kind != RewardItemKind.wallpaper) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                item.kind == RewardItemKind.headgear
                    ? Icons.school_outlined
                    : Icons.diamond_outlined,
                size: 48,
              ),
              Text(item.name, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      );
    }
    final themeId = account.equippedBySlot['theme'];
    final theme = Theme.of(context).brightness == Brightness.dark
        ? M3Theme.darkThemeFor(themeId: themeId, wallpaperId: item.id)
        : M3Theme.lightThemeFor(themeId: themeId, wallpaperId: item.id);
    return Theme(
      data: theme,
      child: Container(
        key: ValueKey('owned-preview-${item.id}'),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('borrow', style: theme.textTheme.headlineSmall),
                const Text('ขอยืม'),
                const SizedBox(height: 8),
                const Text('May I borrow your pen?'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
