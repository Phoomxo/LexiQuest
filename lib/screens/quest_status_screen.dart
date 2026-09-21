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

  void _bindQuest(QuestUseCases? quest) {
    if (identical(quest, _quest)) return;
    _quest?.removeStatusListener(_refreshStatus);
    _quest = quest;
    _quest?.addStatusListener(_refreshStatus);
    _load = quest?.loadStatusForCurrentOwner(limit: 50);
    _load?.ignore();
  }

  void _refreshStatus() {
    if (mounted) _retry();
  }

  @override
  void dispose() {
    _quest?.removeStatusListener(_refreshStatus);
    super.dispose();
  }

  void _retry() {
    final next = _quest?.loadStatusForCurrentOwner(limit: 50);
    next?.ignore();
    setState(() {
      _load = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    return Scaffold(
      appBar: AppBar(title: const Text('ภารกิจการเรียน')),
      body: load == null
          ? const QuestStatusUnavailable()
          : FutureBuilder<List<QuestStatusEntry>>(
              future: load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const QuestStatusLoading();
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return QuestStatusFailure(onRetry: _retry);
                }
                final instances = snapshot.data!;
                if (instances.isEmpty) {
                  return const QuestStatusEmpty();
                }
                return _QuestStatusList(instances: instances);
              },
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('โหลดสถานะภารกิจไม่สำเร็จ'),
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
