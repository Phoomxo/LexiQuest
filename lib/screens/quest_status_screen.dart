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
  Future<List<QuestInstance>>? _load;

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
    _quest = quest;
    _load = quest?.getAllInstancesForCurrentOwner(limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    return Scaffold(
      appBar: AppBar(title: const Text('Quest Status')),
      body: load == null
          ? const QuestStatusUnavailable()
          : FutureBuilder<List<QuestInstance>>(
              future: load,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const QuestStatusFailure();
                }
                if (!snapshot.hasData) {
                  return const QuestStatusLoading();
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
    return const Center(child: Text('No quests yet'));
  }
}

class QuestStatusFailure extends StatelessWidget {
  const QuestStatusFailure({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Quest status could not be loaded'));
  }
}

class QuestStatusUnavailable extends StatelessWidget {
  const QuestStatusUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Quest status is unavailable'));
  }
}

class _QuestStatusList extends StatelessWidget {
  const _QuestStatusList({required this.instances});

  final List<QuestInstance> instances;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: instances.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final instance = instances[index];
        final current = instance.progress.fold<int>(
          0,
          (total, objective) => total + objective.currentCount,
        );
        final target = instance.progress.fold<int>(
          0,
          (total, objective) => total + objective.targetCount,
        );
        return Card(
          child: ListTile(
            leading: Icon(_icon(instance.state)),
            title: Text(_label(instance.state)),
            subtitle: Text('$current / $target'),
          ),
        );
      },
    );
  }

  static String _label(QuestInstanceState state) => switch (state) {
    QuestInstanceState.active => 'Active',
    QuestInstanceState.completed => 'Completed',
    QuestInstanceState.expired => 'Expired',
    QuestInstanceState.abandoned => 'Abandoned',
  };

  static IconData _icon(QuestInstanceState state) => switch (state) {
    QuestInstanceState.active => Icons.play_circle_outline,
    QuestInstanceState.completed => Icons.check_circle_outline,
    QuestInstanceState.expired => Icons.schedule_outlined,
    QuestInstanceState.abandoned => Icons.block_outlined,
  };
}
