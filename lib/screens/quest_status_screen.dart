import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/quest/application/quest_use_cases.dart';
import '../features/quest/domain/quest_models.dart';
import '../runtime/app_dependencies.dart';

/// Read-only, bounded projection of the current owner's durable quest state.
class QuestStatusScreen extends StatefulWidget {
  const QuestStatusScreen({super.key, this.quest});

  final QuestUseCases? quest;

  @override
  State<QuestStatusScreen> createState() => _QuestStatusScreenState();
}

class _QuestStatusScreenState extends State<QuestStatusScreen> {
  QuestUseCases? _quest;
  Future<List<QuestStatusEntry>>? _load;
  var _generation = 0;
  var _active = false;
  var _pending = false;
  var _refreshQueued = false;
  var _routeExited = false;

  bool get _visible =>
      !_routeExited &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  bool _current(int generation) =>
      mounted && !_routeExited && generation == _generation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindQuest(widget.quest ?? AppDependenciesScope.maybeOf(context)?.quest);
  }

  @override
  void didUpdateWidget(QuestStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindQuest(widget.quest ?? AppDependenciesScope.maybeOf(context)?.quest);
  }

  void _retireRead() {
    _generation++;
    _load = null;
    _pending = false;
    _refreshQueued = false;
  }

  void _bindQuest(QuestUseCases? quest) {
    final changed = !identical(quest, _quest);
    if (changed) {
      _quest?.removeStatusListener(_refreshStatus);
      _quest = quest;
      if (!_routeExited) _quest?.addStatusListener(_refreshStatus);
    }
    final active = _visible;
    if (changed || active != _active) {
      _retireRead();
      _active = active;
      if (active) _startRead();
    }
  }

  void _startRead() {
    final quest = _quest;
    if (quest == null) return;
    final generation = ++_generation;
    _pending = true;
    _refreshQueued = false;
    _load = Future<List<QuestStatusEntry>>.sync(
      () => quest.loadStatusForCurrentOwner(limit: 50),
    );
    // Attach immediately: a retry may fail before FutureBuilder's next frame.
    _load!.then<void>(
      (_) => _readFinished(generation),
      onError: (Object _, StackTrace __) => _readFinished(generation),
    );
  }

  void _readFinished(int generation) {
    if (!_current(generation)) return;
    _pending = false;
    // Keep one trailing read for durable notifications received while pending.
    // Retired reads cannot start work on a replacement authority or hidden page.
    if (_refreshQueued && _visible) setState(_startRead);
  }

  void _refreshStatus() {
    if (!mounted || _routeExited) return;
    if (!_visible || _pending) {
      _refreshQueued = true;
      return;
    }
    setState(_startRead);
  }

  void _retry(int generation) {
    if (!_current(generation) || !_active || _pending || !_visible) return;
    setState(_startRead);
  }

  void _exit() {
    _routeExited = true;
    _quest?.removeStatusListener(_refreshStatus);
    _retireRead();
  }

  @override
  void dispose() {
    _exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    final generation = _generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_routeExited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ภารกิจการเรียน')),
        body: !_active || _routeExited
            ? const SizedBox.shrink()
            : load == null
            ? const QuestStatusUnavailable()
            : FutureBuilder<List<QuestStatusEntry>>(
                key: ValueKey(generation),
                future: load,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const QuestStatusLoading();
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return QuestStatusFailure(
                      onRetry: () => _retry(generation),
                    );
                  }
                  final instances = snapshot.data!;
                  if (instances.isEmpty) {
                    return const QuestStatusEmpty();
                  }
                  return _QuestStatusList(instances: instances);
                },
              ),
      ),
    );
  }
}

class QuestStatusLoading extends StatelessWidget {
  const QuestStatusLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class QuestStatusEmpty extends StatelessWidget {
  const QuestStatusEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('ยังไม่มีภารกิจ'));
  }
}

class QuestStatusFailure extends StatelessWidget {
  const QuestStatusFailure({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: const Text('โหลดสถานะภารกิจไม่สำเร็จ'),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('ลองใหม่')),
            ],
          ],
        ),
      ),
    );
  }
}

class QuestStatusUnavailable extends StatelessWidget {
  const QuestStatusUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('สถานะภารกิจยังไม่พร้อมใช้งาน'));
  }
}

class _QuestStatusList extends StatelessWidget {
  const _QuestStatusList({required this.instances});

  final List<QuestStatusEntry> instances;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: instances.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = instances[index];
        final instance = entry.instance;
        final definition = entry.definition;
        final translated = switch ((
          instance.questId,
          instance.catalogVersion,
        )) {
          ('daily-correct-5-v1', 1) => 'ฝึกคำศัพท์ประจำวัน',
          ('weekly-correct-20-v1', 1) => 'ฝึกคำศัพท์ประจำสัปดาห์',
          _ => null,
        };
        return MenuActionBinding(
          id: 'quests/status/$index',
          label: 'Quest status item ${index + 1}',
          ownerId: instance.ownerId,
          onInvoke: null,
          readValue: jsonEncode({
            'state': instance.state.name,
            'definitionAvailable': definition != null,
            'catalogVersion': instance.catalogVersion,
            if (definition != null) ...{
              'title': String.fromCharCodes(
                (translated ?? definition.title).runes.take(60),
              ),
              'titleTruncated':
                  (translated ?? definition.title).runes.length > 60,
              'conditionalXp': definition.reward.xpAmount,
            },
            'rewardMeaning': 'conditional-not-earned-balance',
            'progress': [
              for (final progress in instance.progress.take(4))
                {
                  'current': progress.currentCount,
                  'target': progress.targetCount,
                },
            ],
            'progressTruncated': instance.progress.length > 4,
          }),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    definition == null
                        ? 'รายละเอียดภารกิจฉบับนี้ยังไม่พร้อม'
                        : translated ?? definition.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(_icon(instance.state)),
                      const SizedBox(width: 8),
                      Text(_label(instance.state)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (definition == null)
                    const Text(
                      'ยังอ่านเป้าหมายของรุ่นที่ได้รับไม่ได้ ลองเปิดหน้านี้ใหม่ภายหลัง ความคืบหน้าที่บันทึกไว้ยังอยู่',
                    )
                  else ...[
                    Text(
                      translated == null
                          ? definition.description
                          : instance.questId == 'daily-correct-5-v1'
                          ? 'ตอบคำถามคำศัพท์ให้ถูกตามเป้าหมายประจำวัน'
                          : 'ตอบคำถามคำศัพท์ให้ถูกตามเป้าหมายประจำสัปดาห์',
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final progress in instance.progress) ...[
                    Text(
                      '${definition == null
                          ? 'ความคืบหน้าที่บันทึกไว้'
                          : translated != null
                          ? 'คำตอบถูก'
                          : definition.objectives.firstWhere((objective) => objective.objectiveId == progress.objectiveId).description}: ${progress.currentCount} จาก ${progress.targetCount}',
                    ),
                    const SizedBox(height: 8),
                  ],
                  ExpansionTile(
                    key: ValueKey('quest-details/${instance.instanceId}'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('รายละเอียดภารกิจ'),
                    children: [
                      Text(
                        'รหัสภารกิจ ${instance.questId} · รุ่น ${instance.catalogVersion}',
                      ),
                      Text('ได้รับเมื่อ ${instance.assignedAtUtc.toLocal()}'),
                      if (definition != null) ...[
                        Text(definition.title),
                        Text(definition.description),
                        Text(
                          'รางวัลตามเงื่อนไข ${definition.reward.xpAmount} XP — ไม่ใช่ยอดที่ได้รับแล้ว',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _label(QuestInstanceState state) => switch (state) {
    QuestInstanceState.active => 'กำลังทำ',
    QuestInstanceState.completed => 'สำเร็จแล้ว',
    QuestInstanceState.expired => 'ทำได้ในครั้งถัดไป',
    QuestInstanceState.abandoned => 'พักไว้',
  };

  static IconData _icon(QuestInstanceState state) => switch (state) {
    QuestInstanceState.active => Icons.play_circle_outline,
    QuestInstanceState.completed => Icons.check_circle_outline,
    QuestInstanceState.expired => Icons.schedule_outlined,
    QuestInstanceState.abandoned => Icons.block_outlined,
  };
}
