import 'dart:async';
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
    extends State<LearningPackCatalogScreen>
    with WidgetsBindingObserver {
  Future<LearningPackCatalog>? _catalog;
  final _search = TextEditingController();
  String? _level;
  String? _topic;
  String? _skill;
  String? _goal;

  StudyPlanningUseCases? _useCases;
  AppDependencies? _dependencies;
  StreamSubscription<({String ownerId, String? firebaseUid})?>? _owners;
  int _epoch = 0;
  int _generation = 0;
  int _display = 0;
  bool _active = false;
  bool _pending = false;
  bool _opening = false;
  bool _exited = false;
  bool _foreground = true;
  bool _ownerReady = false;
  String? _ownerId;

  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _bind();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(LearningPackCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final dependencies = widget.useCases == null
        ? AppDependenciesScope.maybeOf(context)
        : null;
    final useCases = widget.useCases ?? dependencies?.studyPlanning;
    final active = _visible;
    final changed =
        !identical(dependencies, _dependencies) ||
        !identical(useCases, _useCases);
    _dependencies = dependencies;
    _useCases = useCases;
    if (changed || active != _active) {
      _active = active;
      _retire();
      _observe();
      if (active && useCases == null) _read();
    }
  }

  void _retire() {
    _generation++;
    _display++;
    _catalog = null;
    _pending = false;
  }

  bool _current(int generation) =>
      mounted && !_exited && generation == _generation;
  bool _allowed(int display) =>
      mounted &&
      !_exited &&
      display == _display &&
      _active &&
      _visible &&
      !_opening;

  void _observe() {
    final epoch = ++_epoch;
    _owners?.cancel().ignore();
    _owners = null;
    _ownerReady = false;
    _ownerId = null;
    if (!_active || _useCases == null) return;
    _pending = true;
    // Observe through the selected use cases, including standalone instances.
    _owners = _useCases!.progress.watchProfileOwner().listen(
      (owner) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = true;
          _ownerId = owner?.ownerId;
          if (_active) _read();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = false;
          _ownerId = null;
          _catalog = Future<LearningPackCatalog>.error(error, stack);
          _catalog!.ignore();
        });
      },
    );
  }

  void _read() {
    _retire();
    final generation = _generation;
    final useCases = _useCases;
    final ownerId = _ownerId;
    _pending = true;
    _catalog = Future<LearningPackCatalog>.sync(() async {
      if (useCases == null || !_ownerReady || ownerId == null) {
        throw StateError('StudyPlanningUseCases is unavailable');
      }
      final catalog = await useCases.listPacks(LearningPackFilter());
      final current = await useCases.progress.owners.getOrCreateActiveOwner();
      if (catalog.progress.ownerId != ownerId || current.id != ownerId) {
        throw StateError('Catalog owner changed');
      }
      return catalog;
    });
    // Observe immediately, before FutureBuilder attaches on a retry frame.
    _catalog!.then<void>(
      (_) {
        if (_current(generation)) _pending = false;
      },
      onError: (Object _, StackTrace __) {
        if (_current(generation)) _pending = false;
      },
    );
  }

  void _retry(int display) {
    if (!_allowed(display) || _pending) return;
    setState(() {
      if (_useCases != null && !_ownerReady) {
        _retire();
        _observe();
      } else {
        _read();
      }
    });
  }

  void _change(int display, VoidCallback change) {
    if (!_allowed(display)) return;
    setState(change);
  }

  Future<void> _open(int display, String name, WidgetBuilder child) async {
    if (!_allowed(display)) return;
    _opening = true;
    _display++;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'study-planning/$name',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            builder: child,
          ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted && !_exited) setState(() {});
    }
  }

  void _exit() {
    _exited = true;
    _epoch++;
    _owners?.cancel().ignore();
    _owners = null;
    _retire();
  }

  @override
  void dispose() {
    _exit();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = ++_display;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'ชุดคำส่วนตัว',
              onPressed: () => _open(
                display,
                'personal-sets',
                (_) => const PersonalSetsScreen(),
              ),
              icon: const Icon(Icons.collections_bookmark_outlined),
            ),
          ],
          title: Text(
            NavigationGlossary.require('study-planning/catalog').fullThaiLabel,
          ),
        ),
        body: !_active || _exited
            ? const SizedBox.shrink()
            : FutureBuilder<LearningPackCatalog>(
                key: ValueKey(_generation),
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              header: true,
                              child: const Text(
                                'ยังไม่พร้อมแสดงชุดบทเรียนที่ผ่านการตรวจสอบ',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _retry(display),
                              icon: const Icon(Icons.refresh),
                              label: const Text('ลองอีกครั้ง'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final packs = snapshot.requireData.packs;
                  final ownerId = snapshot.requireData.progress.ownerId;
                  if (packs.isEmpty) {
                    return _catalogContext(
                      ownerId: ownerId,
                      catalogCount: 0,
                      matchingCount: 0,
                      child: const Center(
                        child: Text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'),
                      ),
                    );
                  }
                  final query = _search.text.trim().toLowerCase();
                  final levels =
                      packs.map((pack) => pack.cefrLevel).toSet().toList()
                        ..sort();
                  final topics =
                      packs.map((pack) => pack.topic).toSet().toList()..sort();
                  final skills =
                      packs.map((pack) => pack.skill).toSet().toList()..sort();
                  final goals = packs.map((pack) => pack.goal).toSet().toList()
                    ..sort();
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
                    ownerId: ownerId,
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
                                onChanged: (_) => _change(display, () {}),
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
                                          onPressed: () =>
                                              _change(display, _search.clear),
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
                                      onSelected: (selected) => _change(
                                        display,
                                        () => _level = selected ? level : null,
                                      ),
                                    ),
                                  for (final skill in skills)
                                    FilterChip(
                                      label: Text(skill),
                                      selected: _skill == skill,
                                      onSelected: (selected) => _change(
                                        display,
                                        () => _skill = selected ? skill : null,
                                      ),
                                    ),
                                  for (final goal in goals)
                                    FilterChip(
                                      label: Text(goal),
                                      selected: _goal == goal,
                                      onSelected: (selected) => _change(
                                        display,
                                        () => _goal = selected ? goal : null,
                                      ),
                                    ),
                                  for (final topic in topics)
                                    FilterChip(
                                      label: Text(topic),
                                      selected: _topic == topic,
                                      onSelected: (selected) => _change(
                                        display,
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
                                for (
                                  var index = 0;
                                  index < visible.length;
                                  index++
                                )
                                  _PackTile(
                                    pack: visible[index],
                                    contextIndex: index,
                                    ownerId: ownerId,
                                    onOpen: () {
                                      final pack = visible[index];
                                      _open(
                                        display,
                                        'catalog/detail',
                                        (_) => LearningPackDetailScreen(
                                          packId: pack.packId,
                                          revision: pack.revision,
                                        ),
                                      );
                                    },
                                  ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _catalogContext({
    required String? ownerId,
    required int catalogCount,
    required int matchingCount,
    required Widget child,
  }) => MenuActionBinding(
    ownerId: ownerId,
    id: 'study-planning/catalog-summary',
    label: 'ชุดบทเรียนและผลการกรองที่แสดง',
    onInvoke: null,
    readValue: ownerId == null
        ? null
        : jsonEncode({
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
  const _PackTile({
    required this.pack,
    required this.contextIndex,
    required this.ownerId,
    required this.onOpen,
  });

  final LearningPackSummary pack;
  final int contextIndex;
  final String? ownerId;

  final VoidCallback onOpen;

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
      ownerId: ownerId,
      id: 'study-planning/catalog-pack/$contextIndex',
      label: 'ข้อมูลชุดบทเรียนที่แสดง',
      onInvoke: null,
      readValue: ownerId == null
          ? null
          : jsonEncode({
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
        onTap: onOpen,
        child: ExcludeSemantics(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            key: ValueKey<String>(
              'learning-pack/open/${pack.packId}/${pack.revision}',
            ),
            onTap: onOpen,
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
