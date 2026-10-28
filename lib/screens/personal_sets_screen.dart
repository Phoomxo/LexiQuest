import '../features/ai_tutor/presentation/menu_action_binding.dart';
import '../features/media_practice/presentation/speaking_scenario_screen.dart';
import '../features/voice/presentation/audio_lesson_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../features/identity/application/owner_generation.dart';
import '../features/learning_packs/application/personal_set_activities.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/context_practice_use_cases.dart';
import '../features/learning/domain/context_practice.dart';
import '../features/learning/presentation/context_practice_screen.dart';
import '../features/learning/presentation/written_practice_screen.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import 'quiz_screen.dart';
import '../features/learning_packs/application/personal_sets_use_cases.dart';
import '../features/learning_packs/data/packaged_sense_crosswalk.dart';
import '../features/learning_packs/domain/personal_sets.dart';
import '../features/learning_packs/domain/content_quality_policy.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../features/learning_packs/domain/sense_crosswalk.dart';
import '../features/learning_packs/domain/sense_crosswalk_repository.dart';
import '../features/vocabulary/data/packaged_starter_catalog.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature.dart';
import '../navigation/app_routes.dart';

Future<void> openPersonalSets(BuildContext context) =>
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'study-planning/personal-sets',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.studyPlanning,
          registry: AppDependenciesScope.maybeOf(context)?.features,
          builder: (_) => const PersonalSetsScreen(),
        ),
      ),
    );

class PersonalSetsScreen extends StatefulWidget {
  const PersonalSetsScreen({super.key, this.useCases});
  final PersonalSetsUseCases? useCases;
  @override
  State<PersonalSetsScreen> createState() => _PersonalSetsScreenState();
}

class _PersonalSetsScreenState extends State<PersonalSetsScreen> {
  PersonalSetsUseCases? _app;
  OwnerGenerationToken? _owner;
  StreamSubscription<bool>? _ownerWatch;
  Listenable? _featureChanges;
  List<PersonalSetRevision> _sets = [];
  List<SenseRef> _candidates = [];
  final _title = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <SenseRef>{};
  PersonalSetRevision? _editing, _detail, _pending;
  bool _busy = true, _editor = false, _preview = false;
  String? _error;
  String? _launchOperation;
  final _import = TextEditingController();
  bool _backup = false;
  String? _exported, _backupStatus;
  static final _starterPin = SenseCrosswalkPin.fromJson({
    'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
    'revision': 1,
    'artifactHash': PackagedSenseCrosswalk.artifactHash,
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final changes = features is Listenable ? features as Listenable : null;
    if (!identical(changes, _featureChanges)) {
      _featureChanges?.removeListener(_featuresChanged);
      _featureChanges = changes;
      _featureChanges?.addListener(_featuresChanged);
    }
    final app =
        widget.useCases ?? AppDependenciesScope.maybeOf(context)?.personalSets;
    if (!identical(_app, app)) {
      _clearPrivate();
      _app = app;
      if (app != null) _load();
    } else if (app == null) {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_featuresChanged);
    unawaited(_ownerWatch?.cancel());
    _title.dispose();
    _search.dispose();
    _scroll.dispose();
    _import.dispose();
    super.dispose();
  }

  void _featuresChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() => _work(() async {
    _clearPrivate();
    final owner = await _app!.begin();
    final sets = await _app!.list(owner);
    if (!mounted) return;
    _owner = owner;
    _sets = sets;
    _ownerWatch = _app!
        .watchOwnerCurrent(owner)
        .listen(
          (current) {
            if (mounted && identical(_owner, owner) && !current) {
              setState(() {
                _clearPrivate();
                _error = 'บัญชีเปลี่ยนแล้ว โปรดเปิดชุดคำใหม่';
              });
            }
          },
          onError: (Object _) {
            if (mounted && identical(_owner, owner)) setState(_clearPrivate);
          },
        );
  });

  void _clearPrivate() {
    unawaited(_ownerWatch?.cancel());
    _ownerWatch = null;
    _owner = null;
    _launchOperation = null;
    _sets = [];
    _candidates = [];
    _selected.clear();
    _title.clear();
    _search.clear();
    _import.clear();
    _exported = null;
    _backupStatus = null;
    _editing = _detail = _pending = null;
    _editor = _preview = _backup = false;
  }

  Future<void> _work(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on Object catch (error) {
      _error =
          error is ContentQualityFailure || error is VocabularyNotFoundFailure
          ? 'เนื้อหารุ่นเดิมไม่พร้อมใช้งาน ชุดคำที่บันทึกไว้ยังอยู่ แต่ยังแก้ไขหรือเริ่มกิจกรรมไม่ได้'
          : 'ทำรายการไม่ได้ บัญชีหรือเนื้อหาอาจเปลี่ยน โปรดกลับไปเปิดชุดคำใหม่';
      final owner = _owner;
      if (owner != null) {
        try {
          await _app!.ownerGeneration.requireCurrentAsync(owner);
        } on Object {
          if (mounted) _clearPrivate();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([PersonalSetRevision? revision]) => _work(() async {
    final crosswalk = await _app!.candidates(
      _owner!,
      revision?.crosswalkPin ?? _starterPin,
    );
    _candidates = crosswalk.entries.map((e) => e.ref).toList();
    _editing = revision;
    _detail = null;
    _pending = null;
    _selected
      ..clear()
      ..addAll(revision?.members ?? []);
    _title.text = revision?.title ?? '';
    _search.text = revision?.filterSnapshot['query'] ?? '';
    _editor = true;
    _preview = false;
  });

  void _makePreview() {
    try {
      _pending = PersonalSetRevision.create(
        setId: _editing?.setId ?? const Uuid().v4(),
        operationId: const Uuid().v4(),
        expectedPriorRevision: _editing?.revision ?? 0,
        createdAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        title: _title.text.trim(),
        crosswalkPin: _editing?.crosswalkPin ?? _starterPin,
        members: _selected.toList(),
        filterSnapshot:
            {
              ...?_editing?.filterSnapshot,
              if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(),
            }..removeWhere(
              (key, _) => key == 'query' && _search.text.trim().isEmpty,
            ),
      );
      setState(() {
        _preview = true;
        _error = null;
      });
    } on FormatException {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      setState(() => _error = 'ใส่ชื่อชุดคำและเลือกอย่างน้อยหนึ่งความหมาย');
    }
  }

  Future<void> _save() => _work(() async {
    await _app!.save(_owner!, _pending!);
    _sets = await _app!.list(_owner!);
    _editor = false;
    _preview = false;
    _detail = null;
    _pending = null;
  });

  Future<void> _archive() => _work(() async {
    final old = _detail!;
    _pending ??= PersonalSetRevision.create(
      setId: old.setId,
      operationId: const Uuid().v4(),
      expectedPriorRevision: old.revision,
      createdAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      title: old.title,
      crosswalkPin: old.crosswalkPin,
      members: old.members,
      archived: true,
      filterSnapshot: old.filterSnapshot,
    );
    await _app!.save(_owner!, _pending!);
    _sets = await _app!.list(_owner!);
    _detail = null;
    _pending = null;
  });

  Future<void> _exportBackup() => _work(() async {
    final archive = await _app!.exportArchive(_owner!);
    _exported = jsonEncode(archive.toJson());
  });

  Future<void> _restoreBackup() => _work(() async {
    try {
      if (_import.text.length > 16 * 1024 * 1024) {
        throw const FormatException('Too large');
      }
      final envelope = Map<String, Object?>.from(
        jsonDecode(_import.text) as Map,
      );
      await _app!.restoreArchive(_owner!, envelope);
      _sets = await _app!.list(_owner!);
      _backupStatus = 'กู้คืนชุดคำแล้ว';
    } on Object {
      await _app!.ownerGeneration.requireCurrentAsync(_owner!);
      _backupStatus =
          'นำเข้าไม่ได้: ตรวจบัญชี รุ่นข้อมูล และข้อมูลซ้ำที่ขัดกัน ข้อมูลเดิมไม่เปลี่ยน';
    }
  });

  Future<void> _launchActivity({
    ClozeInputMode? contextInput,
    bool resumeContext = false,
  }) => _work(() async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final activities = dependencies?.personalSetActivities;
    if (activities == null || !identical(activities.sets, _app)) {
      throw StateError('Activity unavailable');
    }
    final owner = _owner!;
    final saved = _detail;
    final contextual = contextInput != null || resumeContext;
    PersonalSetActivityLaunch? launch;
    UnifiedLessonShellLease? destination;
    var destinationOwnsSession = false;
    try {
      // Check composition before creating any durable session.
      final factory = dependencies?.createLessonController;
      final registration = dependencies?.lessonModes?.resolve(
        contextual ? LessonMode.cloze : LessonMode.meaningQuiz,
      );
      if (factory == null ||
          (contextual
              ? registration?.adapter is! ClozeModeAdapter
              : registration?.adapter is! MeaningQuizModeAdapter) ||
          dependencies?.currentActivityEvidence == null ||
          !identical(dependencies?.learning, activities.learning)) {
        throw StateError('Canonical quiz destination unavailable');
      }
      launch = resumeContext
          ? await ContextPracticeUseCases(activities).resume(owner)
          : await activities.start(
              owner,
              setId: saved!.setId,
              revision: saved.revision,
              operationId: _launchOperation ??= const Uuid().v4(),
              contextInput: contextInput,
            );
      if (launch == null) {
        _error = 'ไม่มีกิจกรรมบริบทที่ค้างอยู่';
        return;
      }
      await _app!.ownerGeneration.requireCurrentAsync(owner);
      final accepted = launch;
      destination = UnifiedLessonShellLease(
        controller: factory(
          contextual
              ? const ContextPracticeModeAdapter()
              : registration!.adapter,
        ),
        learning: activities.learning,
        nowUtc: () => DateTime.now().toUtc(),
        contrastiveFeedback: dependencies?.contrastiveFeedback,
        builder: (_) => contextual
            ? ContextPracticeScreen(
                launch: accepted,
                learning: activities.learning,
                evidence: dependencies!.currentActivityEvidence!,
              )
            : QuizScreen(
                learning: activities.learning,
                evidenceAdapter: dependencies!.currentActivityEvidence,
                modeAdapter: registration!.adapter as MeaningQuizModeAdapter,
                attachedSession: accepted.session,
              ),
      );
      if (!destination.usesLearningAuthority(activities.learning)) {
        throw StateError('Activity authority mismatch');
      }
      destinationOwnsSession = true;
      await destination.attach(
        accepted.session,
        ownerId: owner.ownerId,
        expectedContent: accepted.items,
      );
      await _app!.ownerGeneration.requireCurrentAsync(owner);
      if (!mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: contextual
              ? 'learning/context'
              : 'study-planning/personal-sets/activity',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: dependencies?.features,
            builder: (_) => ProductionFeatureGate(
              feature: Feature.quiz,
              registry: dependencies?.features,
              builder: (_) => _PersonalSetLesson(
                lease: destination!,
                sets: activities.sets,
                owner: owner,
              ),
            ),
          ),
        ),
      );
    } finally {
      if (launch != null && !destinationOwnsSession) {
        await activities.learning.abandonSession(
          ownerId: owner.ownerId,
          sessionId: launch.session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
      }
      await destination?.retire();
      if (launch != null) _launchOperation = null;
    }
  });

  String _label(SenseRef ref) {
    for (final word in PackagedStarterCatalog.words) {
      if (word.id == ref.wordId &&
          ref.senseKey == 'starter-object-v1' &&
          ref.senseRevision == 1 &&
          word.artifactHash == ref.lexicalArtifactHash &&
          ref.corpusManifestHash == PackagedSenseCrosswalk.corpusManifestHash) {
        return '${word.key} — ${word.meaning}';
      }
    }
    return 'ความหมายเดิมที่ยังไม่มีตัวแสดงผล';
  }

  bool get _contextCurrent {
    final owner = _owner;
    final app = _app;
    if (owner == null || app == null) return false;
    try {
      app.ownerGeneration.requireCurrent(owner);
      return true;
    } on Object {
      return false;
    }
  }

  Map<String, Object?> _setSummary(PersonalSetRevision set) => {
    'title': set.title,
    'revision': set.revision,
    'memberCount': set.members.length,
    'archived': set.archived,
  };

  Widget _contextBinding(
    String suffix,
    Map<String, Object?> value,
    Widget child,
  ) => MenuActionBinding(
    id: 'study-planning/personal-sets/$suffix',
    label: 'Personal set context',
    ownerId: _owner?.ownerId,
    readValue: _contextCurrent ? jsonEncode(value) : null,
    onInvoke: null,
    child: child,
  );

  Map<String, Object?> _assistanceContext() {
    final state = _busy
        ? 'processing'
        : _error != null
        ? 'unconfirmed'
        : _backup
        ? 'backup'
        : _preview
        ? 'preview'
        : _editor
        ? 'draft'
        : _detail != null
        ? 'detail'
        : 'list';
    final disclose = !_busy && _error == null && !_backup;
    return {
      'state': state,
      'purpose': 'personal-content-organization-not-learning-completion',
      'manualSaveRequired': true,
      'entryScope': 'mounted-list-rows-only',
      if (disclose) ...{
        'savedSetCount': _sets.length,
        'draft': _preview && _pending != null
            ? _setSummary(_pending!)
            : _editor
            ? {'title': _title.text.trim(), 'memberCount': _selected.length}
            : null,
        'lastConfirmed': (_editor || _preview) && _editing != null
            ? _setSummary(_editing!)
            : _detail != null
            ? _setSummary(_detail!)
            : null,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final revision = _preview ? _pending : _detail;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final activities = dependencies?.personalSetActivities;
    final activityReady =
        activities != null &&
        identical(activities.sets, _app) &&
        activities.isAvailable() &&
        dependencies?.createLessonController != null &&
        dependencies?.currentActivityEvidence != null;
    final screen = Scaffold(
      appBar: AppBar(title: const Text('ชุดคำส่วนตัว')),
      body: SafeArea(
        child: _app == null
            ? const Center(child: Text('ชุดคำส่วนตัวยังไม่พร้อมใช้งาน'))
            : _busy
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Semantics(liveRegion: true, child: Text(_error!)),
                  if (_owner != null && activities?.canPracticeContext == true)
                    OutlinedButton(
                      onPressed: () => _launchActivity(resumeContext: true),
                      child: const Text('กลับสู่กิจกรรมบริบทที่ค้างอยู่'),
                    ),
                  if (_owner == null) ...[
                    FilledButton(
                      onPressed: _load,
                      child: const Text('เปิดชุดคำใหม่'),
                    ),
                  ] else if (_backup) ...[
                    const Text(
                      'สำรองเฉพาะชุดคำส่วนตัวของบัญชีนี้ รวมประวัติทุกรุ่น ไม่รวมผลการเรียนหรือฐานข้อมูลทั้งแอป ใช้ข้อมูลสำรองชุดคำจากหน้านี้เท่านั้น',
                    ),
                    const Text(
                      'นำเข้าข้อมูลเดิมซ้ำได้ แต่ข้อมูลที่ขัดกันหรือรุ่นที่ไม่รองรับจะไม่ถูกเขียนทับ เนื้อหาบางรุ่นอาจยังเปิดกิจกรรมไม่ได้',
                    ),
                    OutlinedButton(
                      onPressed: _exportBackup,
                      child: const Text('แสดงข้อมูลสำรอง'),
                    ),
                    if (_exported != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _exported!,
                            key: const ValueKey('set-backup-json'),
                          ),
                        ),
                      ),
                    TextField(
                      key: const ValueKey('set-import-json'),
                      controller: _import,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'วางข้อมูลสำรองชุดคำ',
                      ),
                    ),
                    FilledButton(
                      onPressed: _restoreBackup,
                      child: const Text('กู้คืนชุดคำ'),
                    ),
                    if (_backupStatus != null)
                      Semantics(liveRegion: true, child: Text(_backupStatus!)),
                    TextButton(
                      onPressed: () => setState(() {
                        _backup = false;
                        _exported = null;
                        _import.clear();
                        _backupStatus = null;
                      }),
                      child: const Text('กลับไปชุดคำ'),
                    ),
                  ] else if (revision != null) ...[
                    Text(
                      revision.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'รุ่น ${revision.revision} • ความหมายที่เลือก: ${revision.members.length}',
                    ),
                    for (final ref in revision.members)
                      ListTile(title: Text(_label(ref))),
                    if (_preview) ...[
                      FilledButton(
                        onPressed: _save,
                        child: const Text('บันทึกชุดคำ'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _preview = false),
                        child: const Text('กลับไปแก้ไข'),
                      ),
                    ] else ...[
                      if (dependencies?.audioLessons?.isAvailable() == true)
                        OutlinedButton(
                          onPressed: () {
                            final owner = _owner;
                            final app = dependencies?.audioLessons;
                            if (owner == null || app == null) return;
                            AppNavigator.pushPage<void>(
                              context,
                              AppPage<void>(
                                name: 'learning/audio-lesson',
                                builder: (_) => AudioLessonScreen(
                                  useCases: app,
                                  owner: owner,
                                  set: revision,
                                ),
                              ),
                            );
                          },
                          child: const Text('Audio lesson · บทเรียนเสียง'),
                        ),
                      if (dependencies?.speakingScenarios?.isAvailable() ==
                              true &&
                          dependencies?.speechPractice != null)
                        OutlinedButton(
                          onPressed: () {
                            final owner = _owner;
                            final app = dependencies?.speakingScenarios;
                            final speech = dependencies?.speechPractice;
                            if (owner == null || app == null || speech == null) {
                              return;
                            }
                            AppNavigator.pushPage<void>(
                              context,
                              AppPage<void>(
                                name: 'learning/speaking-scenario',
                                builder: (_) => SpeakingScenarioScreen(
                                  useCases: app,
                                  speech: speech,
                                  owner: owner,
                                  set: revision,
                                ),
                              ),
                            );
                          },
                          child: const Text('Speak in a scenario · ฝึกพูด'),
                        ),
                      if (dependencies?.writtenPractice?.isAvailable() == true)
                        OutlinedButton(
                          onPressed: () {
                            final owner = _owner;
                            final app = dependencies?.writtenPractice;
                            if (owner == null || app == null) return;
                            AppNavigator.pushPage<void>(
                              context,
                              AppPage<void>(
                                name: 'learning/written-practice',
                                builder: (_) => WrittenPracticeScreen(
                                  useCases: app,
                                  owner: owner,
                                  set: revision,
                                ),
                              ),
                            );
                          },
                          child: const Text('Use the word · เขียนประโยค'),
                        ),
                      FilledButton(
                        onPressed: activityReady
                            ? () => _launchActivity()
                            : null,
                        child: const Text('เริ่มแบบทดสอบความหมาย'),
                      ),
                      if (activities?.canPracticeContext == true &&
                          activityReady &&
                          revision.members.every(
                            (m) =>
                                const ContextPracticeInventory().find(
                                  m.wordId,
                                ) !=
                                null,
                          )) ...[
                        OutlinedButton(
                          onPressed: () => _launchActivity(
                            contextInput: ClozeInputMode.selected,
                          ),
                          child: const Text('ฝึกบริบท · เลือกคำที่สับสน'),
                        ),
                        OutlinedButton(
                          onPressed: () => _launchActivity(
                            contextInput: ClozeInputMode.typed,
                          ),
                          child: const Text('ฝึกบริบท · พิมพ์คำที่ใช้ร่วมกัน'),
                        ),
                      ] else
                        const Text(
                          'กิจกรรมบริบทยังไม่พร้อม: ต้องเปิดใช้งานและมีบริบทพร้อมเหตุผลที่ตรวจทานครบทุกคำ',
                        ),
                      if (!activityReady)
                        const Text('แบบทดสอบยังไม่พร้อมใช้งาน'),
                      const Text(
                        'เริ่มจากรุ่นที่บันทึกนี้ ระบบจะตรวจความพร้อมของเนื้อหาอีกครั้ง',
                      ),
                      OutlinedButton(
                        onPressed: () => _edit(revision),
                        child: const Text('แก้ไข'),
                      ),
                      OutlinedButton(
                        onPressed: _archive,
                        child: const Text('เก็บเข้าคลัง'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _detail = null),
                        child: const Text('กลับไปชุดคำ'),
                      ),
                    ],
                  ] else if (_editor) ...[
                    TextField(
                      key: const ValueKey('set-title'),
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'ชื่อชุดคำ'),
                    ),
                    const Text(
                      'เลือกความหมายจากคำเริ่มต้น 12 รายการ คำศัพท์เพิ่มเติมยังใช้เก็บคะแนนไม่ได้',
                    ),
                    TextField(
                      key: const ValueKey('set-search'),
                      controller: _search,
                      maxLength: 120,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาความหมาย',
                      ),
                    ),
                    FilledButton(
                      onPressed: _makePreview,
                      child: const Text('ดูตัวอย่าง'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _editor = false),
                      child: const Text('ยกเลิก'),
                    ),
                    for (final ref in _candidates.where(
                      (ref) => _label(ref).toLowerCase().contains(
                        _search.text.trim().toLowerCase(),
                      ),
                    ))
                      CheckboxListTile(
                        title: Text(_label(ref)),
                        value: _selected.contains(ref),
                        onChanged: (value) => setState(() {
                          value == true
                              ? _selected.add(ref)
                              : _selected.remove(ref);
                        }),
                      ),
                  ] else ...[
                    FilledButton(
                      onPressed: () => _edit(),
                      child: const Text('สร้างชุดคำ'),
                    ),
                    if (_sets.isEmpty) const Text('ยังไม่มีชุดคำส่วนตัว'),
                    OutlinedButton(
                      onPressed: () => setState(() => _backup = true),
                      child: const Text('สำรองและกู้คืนชุดคำ'),
                    ),
                    for (final set in _sets)
                      _contextBinding(
                        'item/${set.setId}',
                        _setSummary(set),
                        ListTile(
                          title: Text(set.title),
                          subtitle: Text(
                            'รุ่น ${set.revision} • ${set.members.length} ความหมาย',
                          ),
                          onTap: () => _work(() async {
                            _detail = await _app!.read(
                              _owner!,
                              setId: set.setId,
                              revision: set.revision,
                            );
                            _pending = null;
                          }),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
    return _contextBinding('context', _assistanceContext(), screen);
  }
}

/// Owns the accepted destination even when its Navigator is removed wholesale
/// or a live feature gate removes the child without completing push().
class _PersonalSetLesson extends StatefulWidget {
  const _PersonalSetLesson({
    required this.lease,
    required this.sets,
    required this.owner,
  });
  final UnifiedLessonShellLease lease;
  final PersonalSetsUseCases sets;
  final OwnerGenerationToken owner;
  @override
  State<_PersonalSetLesson> createState() => _PersonalSetLessonState();
}

class _PersonalSetLessonState extends State<_PersonalSetLesson> {
  StreamSubscription<bool>? _ownerWatch;
  bool _current = true;
  @override
  void initState() {
    super.initState();
    _ownerWatch = widget.sets
        .watchOwnerCurrent(widget.owner)
        .listen(
          (current) {
            if (!current && mounted && _current) {
              setState(() => _current = false);
              _retire();
            }
          },
          onError: (Object _) {
            if (mounted) setState(() => _current = false);
            _retire();
          },
        );
  }

  @override
  Widget build(BuildContext context) => _current
      ? widget.lease.shell
      : Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมสิ้นสุด')),
          body: const Center(
            child: Text('บัญชีเปลี่ยนแล้ว กิจกรรมนี้สิ้นสุดแล้ว'),
          ),
        );
  @override
  void dispose() {
    unawaited(_ownerWatch?.cancel());
    _retire();
    super.dispose();
  }

  void _retire() {
    unawaited(
      widget.lease.retire().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'personal set activity',
              context: ErrorDescription('retiring an accepted lesson'),
            ),
          );
        },
      ),
    );
  }
}
