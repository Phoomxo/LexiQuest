import 'package:flutter/material.dart';

import '../features/achievements/application/achievement_share_card_use_cases.dart';
import '../features/achievements/data/file_selector_share_card_store.dart';
import '../features/achievements/presentation/achievement_share_card.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/learning_summary_card.dart';

typedef AchievementProgressLoader = Future<ProgressSnapshot> Function();

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    this.loader,
    this.shareCards,
    this.onOpenQuests,
    this.onOpenShop,
  });

  final AchievementProgressLoader? loader;
  final AchievementShareCardUseCases? shareCards;
  final VoidCallback? onOpenQuests;
  final VoidCallback? onOpenShop;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  static final _defaultShareCards = AchievementShareCardUseCases(
    store: const FileSelectorShareCardStore(),
  );

  Future<ProgressSnapshot>? _load;
  AchievementProgressLoader? _activeLoader;
  var _loadGeneration = 0;
  var _wasActive = false;
  final Set<String> _busyShareKeys = <String>{};
  _AchievementShareStatus? _shareStatus;
  AchievementShareCardArtifact? _savedArtifact;

  AchievementShareCardUseCases get _shareCards =>
      widget.shareCards ?? _defaultShareCards;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    if (!isActive || (_wasActive && _load != null && loader == _activeLoader)) {
      _wasActive = isActive;
      return;
    }
    _startLoad();
    _wasActive = true;
  }

  @override
  void didUpdateWidget(covariant AchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loader == oldWidget.loader &&
        identical(widget.shareCards, oldWidget.shareCards)) {
      return;
    }
    final isActive = TickerMode.valuesOf(context).enabled;
    _wasActive = isActive;
    if (isActive) _startLoad();
  }

  void _startLoad() {
    _loadGeneration += 1;
    _busyShareKeys.clear();
    _shareStatus = null;
    _savedArtifact = null;
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    _activeLoader = loader;
    _load = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : loader();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('รางวัล')),
      body: Column(
        children: [
          if (widget.onOpenQuests != null || widget.onOpenShop != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.onOpenQuests != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('rewards-open-quests'),
                      onPressed: widget.onOpenQuests,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('ภารกิจการเรียน'),
                    ),
                  if (widget.onOpenQuests != null && widget.onOpenShop != null)
                    const SizedBox(height: 12),
                  if (widget.onOpenShop != null)
                    OutlinedButton.icon(
                      key: const ValueKey('rewards-open-shop'),
                      onPressed: widget.onOpenShop,
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('ร้านค้ารางวัล'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<ProgressSnapshot>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้',
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(() {
                            _startLoad();
                            _load?.ignore();
                          }),
                          child: const Text('ลองใหม่'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final progress = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    LearningSummaryCard(
                      icon: Icons.toll_outlined,
                      title: 'คะแนนสะสม',
                      value: '${progress.totalXp}',
                      caption: 'หลักฐานคำตอบ ${progress.sampleSize} รายการ',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ความสำเร็จ',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (progress.achievements.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            'ยังไม่มีความสำเร็จที่ปลดล็อก\nจำนวนหลักฐาน: ${progress.sampleSize}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      for (final achievement in progress.achievements)
                        Card(
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(
                                  Icons.workspace_premium_outlined,
                                ),
                                title: Text(_title(achievement.id)),
                                subtitle: Text(
                                  'ปลดล็อกเมื่อ ${_date(achievement.unlockedAtUtc)}',
                                ),
                                trailing: _shareCards.canShare(achievement)
                                    ? _shareAction(progress, achievement)
                                    : Text(_date(achievement.unlockedAtUtc)),
                              ),
                              ExpansionTile(
                                title: const Text('รายละเอียดความสำเร็จ'),
                                key: ValueKey(
                                  'achievement-details/${achievement.id}',
                                ),
                                children: [
                                  Text(
                                    'รหัส ${achievement.id} · หลักฐาน ${achievement.sourceEventId} · นิยาม v${achievement.definitionVersion}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ExpansionTile(
                      title: const Text('รายละเอียดคะแนน'),
                      children: [
                        Text('อัลกอริทึม v${progress.algorithmVersion}'),
                      ],
                    ),
                    if (_shareStatus != null) ...[
                      const SizedBox(height: 12),
                      _shareStatusMessage(),
                    ],
                    if (_savedArtifact case final artifact?) ...[
                      const SizedBox(height: 12),
                      AchievementShareCard(artifact: artifact),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _title(String id) => switch (id) {
    'first_answer' => 'บันทึกคำตอบครั้งแรก',
    'first_correct' => 'ตอบถูกครั้งแรก',
    'first_session' => 'เรียนจบเซสชันแรก',
    'perfect_session' => 'ตอบถูกครบทั้งเซสชัน',
    'ten_correct' => 'ตอบถูกครบ 10 ครั้ง',
    _ => 'ความสำเร็จที่บันทึกไว้',
  };

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  Widget _shareAction(ProgressSnapshot progress, AchievementEvidence unlock) {
    final key = _shareKey(unlock);
    final busy = _busyShareKeys.contains(key);
    final title = _title(unlock.id);
    final generation = _loadGeneration;
    final shares = _shareCards;
    final onPressed = busy
        ? null
        : () {
            if (!_isCurrentShare(generation, shares)) return;
            _confirmShare(progress, unlock);
          };
    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      label: 'บันทึกการ์ดความสำเร็จ: $title',
      excludeSemantics: true,
      onTap: onPressed,
      child: IconButton(
        key: ValueKey<String>('achievement-share/${unlock.id}'),
        tooltip: 'บันทึกการ์ดความสำเร็จ',
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share_outlined),
      ),
    );
  }

  Future<void> _confirmShare(
    ProgressSnapshot progress,
    AchievementEvidence unlock,
  ) async {
    final key = _shareKey(unlock);
    if (_busyShareKeys.contains(key)) return;
    final loadGeneration = _loadGeneration;
    final shares = _shareCards;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('บันทึกการ์ดความสำเร็จนี้?'),
        content: Text(_title(unlock.id)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          Semantics(
            button: true,
            label: 'ยืนยันการเลือกตำแหน่งบันทึกการ์ดความสำเร็จ',
            child: FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('เลือกตำแหน่งบันทึก'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrentShare(loadGeneration, shares)) {
      return;
    }
    await _share(progress, unlock);
  }

  Future<void> _share(
    ProgressSnapshot progress,
    AchievementEvidence unlock,
  ) async {
    final key = _shareKey(unlock);
    if (_busyShareKeys.contains(key)) return;
    final generation = _loadGeneration;
    final shares = _shareCards;
    final scope = _load;
    setState(() {
      _busyShareKeys.add(key);
      _shareStatus = null;
    });
    try {
      final result = await shares.share(
        progress: progress,
        scope: scope,
        achievementId: unlock.id,
        definitionVersion: unlock.definitionVersion,
        confirmed: true,
      );
      if (!_isCurrentShare(generation, shares)) return;
      setState(() {
        _busyShareKeys.remove(key);
        switch (result.status) {
          case AchievementShareCardStatus.saved:
            _shareStatus = _AchievementShareStatus.saved;
            _savedArtifact = result.artifact;
          case AchievementShareCardStatus.cancelled:
            _shareStatus = _AchievementShareStatus.cancelled;
        }
      });
    } catch (_) {
      if (!_isCurrentShare(generation, shares)) return;
      setState(() {
        _busyShareKeys.remove(key);
        _shareStatus = _AchievementShareStatus.failed;
      });
    }
  }

  bool _isCurrentShare(int generation, AchievementShareCardUseCases shares) =>
      mounted &&
      _wasActive &&
      generation == _loadGeneration &&
      identical(shares, _shareCards);

  Widget _shareStatusMessage() {
    final status = _shareStatus!;
    final message = switch (status) {
      _AchievementShareStatus.saved => 'บันทึกการ์ดความสำเร็จแล้ว',
      _AchievementShareStatus.cancelled => 'ยกเลิกการเลือกตำแหน่งบันทึก',
      _AchievementShareStatus.failed => 'ไม่สามารถบันทึกการ์ดความสำเร็จได้',
    };
    return Semantics(
      liveRegion: true,
      label: 'สถานะการ์ดความสำเร็จ: $message',
      child: Row(
        children: <Widget>[
          Expanded(child: Text(message)),
          if (status != _AchievementShareStatus.saved)
            TextButton(
              onPressed: () => setState(() => _shareStatus = null),
              child: const Text('ลองอีกครั้ง'),
            ),
        ],
      ),
    );
  }

  String _shareKey(AchievementEvidence unlock) =>
      '${unlock.id}:${unlock.definitionVersion}:'
      '${unlock.unlockedAtUtc.millisecondsSinceEpoch}';
}

enum _AchievementShareStatus { saved, cancelled, failed }
