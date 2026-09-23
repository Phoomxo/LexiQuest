import 'dart:convert';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/learning_packs/application/learning_pack_use_cases.dart';
import '../features/learning_packs/domain/learning_pack.dart';
import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature.dart';
import 'learning_pack_detail_screen.dart';
import 'personal_sets_screen.dart';

/// Read-only catalog child of [StudyPlanningHubScreen].
final class LearningPackCatalogScreen extends StatefulWidget {
  const LearningPackCatalogScreen({super.key, this.useCases});

  final StudyPlanningUseCases? useCases;

  @override
  State<LearningPackCatalogScreen> createState() =>
      _LearningPackCatalogScreenState();
}

final class _LearningPackCatalogScreenState
    extends State<LearningPackCatalogScreen> {
  late Future<LearningPackCatalog> _catalog;
  final _search = TextEditingController();
  String? _level;
  String? _topic;
  String? _skill;
  String? _goal;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog =
        (widget.useCases ??
                AppDependenciesScope.of(context).studyPlanning ??
                (throw StateError('StudyPlanningUseCases is unavailable')))
            .listPacks(LearningPackFilter());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'ชุดคำส่วนตัว',
            onPressed: () => openPersonalSets(context),
            icon: const Icon(Icons.collections_bookmark_outlined),
          ),
        ],
        title: Text(
          NavigationGlossary.require('study-planning/catalog').fullThaiLabel,
        ),
      ),
      body: FutureBuilder<LearningPackCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('ยังไม่พร้อมแสดงชุดบทเรียนที่ผ่านการตรวจสอบ'),
              ),
            );
          }
          final packs = snapshot.requireData.packs;
          if (packs.isEmpty) {
            return _catalogContext(
              catalogCount: 0,
              matchingCount: 0,
              child: const Center(
                child: Text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'),
              ),
            );
          }
          final query = _search.text.trim().toLowerCase();
          final levels = packs.map((pack) => pack.cefrLevel).toSet().toList()
            ..sort();
          final topics = packs.map((pack) => pack.topic).toSet().toList()
            ..sort();
          final skills = packs.map((pack) => pack.skill).toSet().toList()
            ..sort();
          final goals = packs.map((pack) => pack.goal).toSet().toList()..sort();
          final visible = packs
              .where(
                (pack) =>
                    (_level == null || pack.cefrLevel == _level) &&
                    (_topic == null || pack.topic == _topic) &&
                    (_skill == null || pack.skill == _skill) &&
                    (_goal == null || pack.goal == _goal) &&
                    '${pack.title} ${pack.cefrLevel} ${pack.topic} ${pack.skill} ${pack.goal}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
          return _catalogContext(
            catalogCount: packs.length,
            matchingCount: visible.length,
            child: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: ListView(
                    padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                    ),
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'ค้นหาชุดบทเรียน',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'ล้างการค้นหา',
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  onPressed: () => setState(_search.clear),
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final level in levels)
                            FilterChip(
                              label: Text(level),
                              selected: _level == level,
                              onSelected: (selected) => setState(
                                () => _level = selected ? level : null,
                              ),
                            ),
                          for (final skill in skills)
                            FilterChip(
                              label: Text(skill),
                              selected: _skill == skill,
                              onSelected: (selected) => setState(
                                () => _skill = selected ? skill : null,
                              ),
                            ),
                          for (final goal in goals)
                            FilterChip(
                              label: Text(goal),
                              selected: _goal == goal,
                              onSelected: (selected) => setState(
                                () => _goal = selected ? goal : null,
                              ),
                            ),
                          for (final topic in topics)
                            FilterChip(
                              label: Text(topic),
                              selected: _topic == topic,
                              onSelected: (selected) => setState(
                                () => _topic = selected ? topic : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        Text(
                          query.isEmpty
                              ? 'ไม่พบชุดบทเรียนที่ตรงกับตัวกรอง'
                              : 'ไม่พบชุดบทเรียนที่ตรงกับการค้นหา',
                        )
                      else
                        for (var index = 0; index < visible.length; index++)
                          _PackTile(pack: visible[index], contextIndex: index),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _catalogContext({
    required int catalogCount,
    required int matchingCount,
    required Widget child,
  }) => MenuActionBinding(
    id: 'study-planning/catalog-summary',
    label: 'ชุดบทเรียนและผลการกรองที่แสดง',
    onInvoke: null,
    readValue: jsonEncode({
      'catalogCount': catalogCount,
      'matchingCount': matchingCount,
      'state': catalogCount == 0
          ? 'empty-catalog'
          : matchingCount == 0
          ? 'no-matches'
          : 'matches',
      'searchActive': _search.text.trim().isNotEmpty,
      'filtersActive': [
        _level,
        _topic,
        _skill,
        _goal,
      ].whereType<String>().length,
      'interpretation':
          'Catalog metadata and matching results, not-learner-proficiency. A pack level describes content, not the learner. No enrollment or learning completion is implied.',
    }),
    child: child,
  );
}

final class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack, required this.contextIndex});

  final LearningPackSummary pack;
  final int contextIndex;

  void _open(BuildContext context) {
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'study-planning/catalog/detail',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.studyPlanning,
          registry: AppDependenciesScope.maybeOf(context)?.features,
          builder: (_) => LearningPackDetailScreen(
            packId: pack.packId,
            revision: pack.revision,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Five fields stay within the transport budget even if every rune needs
    // six-character JSON escaping. Native labels retain the full metadata.
    String bounded(String value) => String.fromCharCodes(value.runes.take(20));
    final texts = [
      pack.title,
      pack.cefrLevel,
      pack.topic,
      pack.skill,
      pack.goal,
    ];
    return MenuActionBinding(
      id: 'study-planning/catalog-pack/$contextIndex',
      label: 'ข้อมูลชุดบทเรียนที่แสดง',
      onInvoke: null,
      readValue: jsonEncode({
        'title': bounded(pack.title),
        'revision': pack.revision,
        'level': bounded(pack.cefrLevel),
        'topic': bounded(pack.topic),
        'skill': bounded(pack.skill),
        'goal': bounded(pack.goal),
        'textTruncated': texts.any((value) => value.runes.length > 20),
        'interpretation':
            'Content metadata, not learner achievement. Learner opens the pack with the original control.',
      }),
      child: Semantics(
        button: true,
        label:
            '${pack.title}, ${pack.cefrLevel}, ${pack.topic}, รุ่น '
            '${pack.revision}',
        onTap: () => _open(context),
        child: ExcludeSemantics(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            key: ValueKey<String>(
              'learning-pack/open/${pack.packId}/${pack.revision}',
            ),
            onTap: () => _open(context),
            title: Text(pack.title),
            subtitle: Text(
              '${pack.cefrLevel} · ${pack.topic} · ${pack.skill} · '
              '${pack.goal} · รุ่น ${pack.revision}',
            ),
          ),
        ),
      ),
    );
  }
}
