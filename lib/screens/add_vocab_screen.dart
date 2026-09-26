import 'dart:async';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/scheduler.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';

class AddWordScreen extends StatefulWidget {
  const AddWordScreen({
    super.key,
    this.featureRegistry,
    required this.categoryId,
    this.vocabulary,
    this.word,
  });

  final String categoryId;
  final VocabularyUseCases? vocabulary;
  final VocabularyWord? word;

  final FeatureRegistry? featureRegistry;

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _wordController;
  late final TextEditingController _meaningController;
  late final TextEditingController _partOfSpeechController;
  String? _cefrLevel;
  bool _saving = false;
  VocabularyWord? _committedWord;
  String? _formOwner;
  VocabularyUseCases? _useCases;
  FeatureRegistry? _registry;
  Listenable? _featureChanges;
  ModalRoute<dynamic>? _route;
  bool _retired = false, _ownerRetired = false, _exited = false;
  bool _foreground = true,
      _tabVisible = true,
      _reading = false,
      _attempted = false;
  bool _choosingCefr = false;
  int _epoch = 0, _controls = 0;
  int? _categoryRevision;
  String? _error;
  Future<void>? _ready;
  List<VocabularyWord>? _beforeAttempt;
  StreamSubscription<Object?>? _ownerChanges;
  StreamSubscription<List<VocabularyCategory>>? _categories;
  StreamSubscription<List<VocabularyWord>>? _words;

  void _render() {
    if (!mounted || _exited) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_exited) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool get _visible =>
      mounted &&
      !_exited &&
      _foreground &&
      _tabVisible &&
      _route?.isCurrent == true;
  bool get _current => _visible && !_retired && !_ownerRetired && _admitted;
  bool get _readCurrent => _visible && !_ownerRetired && _admitted;
  void _retire({bool owner = false}) {
    _retired = true;
    _ownerRetired |= owner;
    _epoch++;
    _controls++;
    _render();
  }

  void _featuresChanged() {
    _retire();
  }

  void _cancelReads() {
    _ownerChanges?.cancel();
    _categories?.cancel();
    _words?.cancel();
    _ownerChanges = null;
    _categories = null;
    _words = null;
  }

  void _bind() {
    final u =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final features =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.features;
    if (identical(u, _useCases) && identical(features, _registry)) return;
    _cancelReads();
    _featureChanges?.removeListener(_featuresChanged);
    _registry = features;
    _featureChanges = features is Listenable ? features as Listenable : null;
    _featureChanges?.addListener(_featuresChanged);
    if (_useCases != null) _retire();
    _useCases = u;
    _ready = _read();
    if (u?.vocabulary case final DriftVocabularyRepository repo) {
      _ownerChanges = repo.database
          .tableUpdates(TableUpdateQuery.onTable(repo.database.localOwners))
          .listen((_) {
            Future<void>.sync(() async {
              await _owner(readOnly: true);
            }).catchError((Object _) {
              _readFailed();
            });
          }, onError: (Object _) => _readFailed());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible || (_route?.isCurrent == false && !_choosingCefr)) _retire();
    if (_route?.isCurrent == true) _choosingCefr = false;
    _tabVisible = visible;
    _bind();
  }

  @override
  void didUpdateWidget(covariant AddWordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        oldWidget.word != widget.word) {
      _retire();
    }
    _bind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _retire();
  }

  void _readFailed() {
    if (!mounted || _exited) return;
    _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
    _controls++;
    _render();
  }

  Future<bool> _owner({bool readOnly = false}) async {
    final epoch = _epoch;
    if (!(readOnly ? _readCurrent : _current) || _useCases == null) {
      return false;
    }
    final owner = await _useCases!.owners.getOrCreateActiveOwner();
    if (!mounted || epoch != _epoch || !(readOnly ? _readCurrent : _current)) {
      return false;
    }
    if ((_formOwner != null && owner.id != _formOwner) ||
        (widget.word != null && widget.word!.ownerId != owner.id)) {
      _retire(owner: true);
      return false;
    }
    _formOwner ??= owner.id;
    return true;
  }

  bool _sameWord(VocabularyWord a, VocabularyWord b) =>
      a.id == b.id &&
      a.ownerId == b.ownerId &&
      a.categoryId == b.categoryId &&
      a.localRevision == b.localRevision &&
      a.spelling == b.spelling &&
      a.meaning == b.meaning &&
      a.partOfSpeech == b.partOfSpeech &&
      a.cefrLevel == b.cefrLevel &&
      a.source == b.source &&
      a.contentRevision == b.contentRevision &&
      !a.isDeleted &&
      !a.isReadOnly;
  bool _categoryMatches(List<VocabularyCategory> rows) => rows.any(
    (c) =>
        c.id == widget.categoryId &&
        c.ownerId == _formOwner &&
        !c.isDeleted &&
        !c.isReadOnly &&
        (_categoryRevision == null || c.localRevision == _categoryRevision),
  );
  Future<bool> _snapshot() async {
    if (!await _owner()) return false;
    final u = _useCases!;
    final categories = await u.vocabulary.watchCategories(_formOwner!).first;
    if (!await _owner()) return false;
    if (!_categoryMatches(categories)) {
      _retire();
      return false;
    }
    _categoryRevision ??= categories
        .firstWhere((c) => c.id == widget.categoryId && c.ownerId == _formOwner)
        .localRevision;
    final words = await u.vocabulary
        .watchWords(_formOwner!, widget.categoryId)
        .first;
    if (!await _owner()) return false;
    if (widget.word != null && !words.any((w) => _sameWord(w, widget.word!))) {
      _retire();
      return false;
    }
    return true;
  }

  Future<void> _read() async {
    if (_reading || !_current || _useCases == null) return;
    _reading = true;
    try {
      if (!await _snapshot()) return;
      _error = null;
      _categories ??= _useCases!.vocabulary.watchCategories(_formOwner!).listen(
        (rows) {
          if (!_saving && !_attempted && !_categoryMatches(rows)) _retire();
        },
        onError: (Object _) => _readFailed(),
      );
      _words ??= _useCases!.vocabulary
          .watchWords(_formOwner!, widget.categoryId)
          .listen((rows) {
            if (!_saving &&
                !_attempted &&
                widget.word != null &&
                !rows.any((w) => _sameWord(w, widget.word!))) {
              _retire();
            }
          }, onError: (Object _) => _readFailed());
    } catch (_) {
      _readFailed();
    } finally {
      _reading = false;
      _render();
    }
  }

  static const _cefrOptions = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _wordController = TextEditingController(text: widget.word?.spelling);
    _meaningController = TextEditingController(text: widget.word?.meaning);
    _partOfSpeechController = TextEditingController(
      text: widget.word?.partOfSpeech,
    );
    _cefrLevel = widget.word?.cefrLevel;
  }

  @override
  void dispose() {
    _exited = true;
    _epoch++;
    _controls++;
    _cancelReads();
    _featureChanges?.removeListener(_featuresChanged);
    WidgetsBinding.instance.removeObserver(this);
    _wordController.dispose();
    _meaningController.dispose();
    _partOfSpeechController.dispose();
    super.dispose();
  }

  FeatureRegistry? get _features => _registry;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => ProductionFeatureGate(
    feature: Feature.vocabulary,
    registry: _features,
    builder: _buildContent,
  );

  Widget _buildContent(BuildContext context) {
    final controls = _controls;
    final useCases = _useCases;
    bool editAllowed() =>
        controls == _controls && _current && !_saving && !_attempted;
    if (_ownerRetired || (_retired && !_attempted)) {
      return Scaffold(
        appBar: AppBar(title: const Text('คำศัพท์')),
        body: const Center(child: Text('บริบทเปลี่ยนแล้ว กรุณาปิดและเปิดใหม่')),
      );
    }
    final screen = PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _exited = true;
          _epoch++;
          _controls++;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.word == null ? 'เพิ่มคำศัพท์' : 'แก้ไขคำศัพท์'),
          leading: Navigator.of(context).canPop()
              ? BackButton(
                  onPressed: () {
                    if (controls != _controls || !_visible) return;
                    _exited = true;
                    _epoch++;
                    _controls++;
                    Navigator.pop(context);
                  },
                )
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_reading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_error != null && _readCurrent)
              TextButton(
                onPressed: _reading || _saving
                    ? null
                    : () {
                        if (controls != _controls || !_readCurrent) return;
                        if (_attempted) {
                          _save(useCases!, controls: controls);
                        } else {
                          _ready = _read();
                        }
                      },
                child: const Text('ลองใหม่'),
              ),
            if (widget.word == null || _formOwner != null) ...[
              TextField(
                key: const ValueKey('word-field'),
                enabled: !_attempted && !_saving,
                controller: _wordController,
                onChanged: (_) {
                  if (editAllowed()) setState(() {});
                },
                textInputAction: TextInputAction.next,
                maxLength: maxSpellingLength,
                decoration: const InputDecoration(
                  labelText: 'คำศัพท์',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('meaning-field'),
                enabled: !_attempted && !_saving,
                controller: _meaningController,
                onChanged: (_) {
                  if (editAllowed()) setState(() {});
                },
                textInputAction: TextInputAction.next,
                maxLength: maxMeaningLength,
                decoration: const InputDecoration(
                  labelText: 'ความหมาย',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('part-of-speech-field'),
                enabled: !_attempted && !_saving,
                controller: _partOfSpeechController,
                onChanged: (_) {
                  if (editAllowed()) setState(() {});
                },
                maxLength: maxPartOfSpeechLength,
                decoration: const InputDecoration(
                  labelText: 'ชนิดของคำ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('cefr-field-${_cefrLevel ?? 'none'}'),
                onTap: () {
                  // DropdownButton invokes onTap after pushing its own PopupRoute.
                  if (controls == _controls &&
                      mounted &&
                      !_retired &&
                      !_attempted &&
                      !_saving &&
                      _admitted) {
                    _choosingCefr = true;
                  }
                },
                initialValue: _cefrLevel,
                decoration: const InputDecoration(
                  labelText: 'ระดับ CEFR (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                ),
                items: _cefrOptions
                    .map(
                      (level) =>
                          DropdownMenuItem(value: level, child: Text(level)),
                    )
                    .toList(),
                onChanged: !_attempted && !_saving
                    ? (value) {
                        if (editAllowed()) setState(() => _cefrLevel = value);
                      }
                    : null,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('save-word'),
              onPressed:
                  _saving ||
                      _attempted ||
                      useCases == null ||
                      !_current ||
                      _error != null
                  ? null
                  : () => _save(useCases, controls: controls),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    return MenuActionBinding(
      id: 'vocabulary/word-fill',
      label: 'กรอกคำศัพท์ (ยังไม่บันทึก)',
      ownerId: _formOwner,
      onInvoke: null,
      fields: const {
        'spelling': maxSpellingLength,
        'meaning': maxMeaningLength,
        'partOfSpeech': maxPartOfSpeechLength,
        'cefrLevel': 2,
      },
      onForm: _formOwner == null || useCases == null
          ? null
          : (values) async {
              if (!editAllowed()) {
                return {'status': 'busy'};
              }
              try {
                if (!await _owner() || !editAllowed()) {
                  return {'status': 'stale'};
                }
              } catch (_) {
                _readFailed();
                return {'status': 'failed'};
              }
              final level = values['cefrLevel']!;
              if (level.isNotEmpty && !_cefrOptions.contains(level)) {
                return {'status': 'invalid'};
              }
              setState(() {
                _wordController.text = values['spelling']!;
                _meaningController.text = values['meaning']!;
                _partOfSpeechController.text = values['partOfSpeech']!;
                _cefrLevel = level.isEmpty ? null : level;
              });
              return {'status': 'filled', 'values': values};
            },
      child: MenuActionBinding(
        revisionKey: (
          _wordController.text,
          _meaningController.text,
          _partOfSpeechController.text,
          _cefrLevel,
        ),
        id: 'vocabulary/word-save',
        label: 'บันทึกคำศัพท์และตรวจผล',
        ownerId: _formOwner,
        onInvoke: null,
        onForm: _formOwner == null || useCases == null
            ? null
            : (_) => _save(
                useCases,
                expectedOwnerId: _formOwner,
                controls: controls,
              ),
        child: screen,
      ),
    );
  }

  Future<Map<String, Object?>> _save(
    VocabularyUseCases useCases, {
    String? expectedOwnerId,
    required int controls,
  }) async {
    if (controls != _controls ||
        _saving ||
        !identical(useCases, _useCases) ||
        (_attempted ? !_readCurrent : !_current)) {
      return {'status': 'stale'};
    }
    final epoch = _epoch;
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    final session = registry?.sessionGeneration;
    bool allowed() =>
        epoch == _epoch &&
        _current &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.snapshot()['revision'] == revision);
    bool verifyAllowed() =>
        epoch == _epoch &&
        _readCurrent &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.sessionGeneration == session);
    setState(() => _saving = true);
    try {
      await _ready;
      if (_committedWord != null) {
        return await _verifySaved(useCases, _committedWord!, verifyAllowed);
      }
      if (_attempted) {
        if (!await _unchanged(verifyAllowed)) {
          return {'status': 'outcome_unknown'};
        }
        _attempted = false;
        _error = null;
        return {
          'status': 'retry_ready',
        }; // A separate explicit Save is required.
      }
      if (!await _snapshot() || !allowed()) return {'status': 'stale'};
      _beforeAttempt = await useCases.vocabulary.listAllWords(_formOwner!);
      if (!await _owner() || !allowed()) return {'status': 'stale'};
      _attempted = true;
      final VocabularyWord saved;
      if (widget.word == null) {
        saved = await useCases.createWord(
          CreateWordCommand(
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: _cefrLevel,
          ),
          expectedOwnerId: _formOwner,
          mutationAllowed: allowed,
          enforceMutationAtCommit: true,
          expectedCategoryRevision: _categoryRevision,
        );
      } else {
        saved = await useCases.updateWord(
          UpdateWordCommand(
            id: widget.word!.id,
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: _cefrLevel,
            source: widget.word!.source,
          ),
          expectedOwnerId: _formOwner,
          mutationAllowed: allowed,
          expectedWord: widget.word,
          expectedCategoryRevision: _categoryRevision,
        );
      }
      _committedWord = saved;
      return await _verifySaved(useCases, saved, verifyAllowed);
    } on InvalidVocabularyFailure catch (e) {
      if (e.field == 'owner') {
        _retire(owner: true);
        return {'status': 'stale'};
      }
      _attempted = false;
      if (allowed()) _message('กรุณากรอกข้อมูลให้ครบและไม่เกินความยาวที่กำหนด');
      return {'status': 'invalid'};
    } on DuplicateVocabularyFailure {
      _attempted = false;
      if (allowed()) _message('มีคำศัพท์และความหมายนี้แล้ว');
      return {'status': 'duplicate'};
    } on CategoryWordLimitFailure {
      _attempted = false;
      if (allowed()) _message('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว');
      return {'status': 'limit'};
    } catch (_) {
      if (_attempted && await _unchanged(verifyAllowed)) _attempted = false;
      if (verifyAllowed()) {
        _error = _attempted
            ? 'ยังยืนยันผลการบันทึกไม่ได้ กรุณาตรวจสอบรายการคำศัพท์ก่อนลองใหม่'
            : 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
      }
      return {'status': _attempted ? 'outcome_unknown' : 'failed'};
    } finally {
      _saving = false;
      _render();
    }
  }

  Future<bool> _unchanged(bool Function() allowed) async {
    try {
      if (_beforeAttempt == null ||
          !await _owner(readOnly: true) ||
          !allowed()) {
        return false;
      }
      final words = await _useCases!.vocabulary.listAllWords(_formOwner!);
      if (!await _owner(readOnly: true) || !allowed()) return false;
      return words.length == _beforeAttempt!.length &&
          words.every((w) => _beforeAttempt!.any((b) => _sameWord(w, b)));
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>> _verifySaved(
    VocabularyUseCases useCases,
    VocabularyWord saved,
    bool Function() allowed,
  ) async {
    try {
      final owner = await useCases.owners.getOrCreateActiveOwner();
      if (!allowed() || owner.id != saved.ownerId) return {'status': 'stale'};
      final records = await useCases.readPinnedByIds([saved.id]);
      // The route or optional session may change while verification is pending.
      // Retain the committed identity until a current request can reconcile it.
      if (!await _owner(readOnly: true) || !allowed()) {
        return {'status': 'stale'};
      }
      final persisted = records
          .where(
            (w) =>
                w.id == saved.id &&
                w.ownerId == saved.ownerId &&
                w.categoryId == saved.categoryId &&
                w.spelling == saved.spelling &&
                w.meaning == saved.meaning &&
                w.partOfSpeech == saved.partOfSpeech &&
                w.cefrLevel == saved.cefrLevel &&
                w.localRevision == saved.localRevision &&
                !w.isDeleted,
          )
          .firstOrNull;
      if (persisted == null) return {'status': 'outcome_unknown'};
      _committedWord = null;
      _attempted = false;
      if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
      return {
        'status': 'saved',
        'record': {
          'wordId': persisted.id,
          'categoryId': persisted.categoryId,
          'spelling': persisted.spelling,
          'meaning': persisted.meaning,
          'partOfSpeech': persisted.partOfSpeech,
          'cefrLevel': persisted.cefrLevel,
          'revision': persisted.localRevision,
        },
      };
    } catch (_) {
      if (allowed()) {
        _error =
            'บันทึกแล้ว แต่ยังตรวจสอบผลไม่ได้ กรุณาปิดแล้วตรวจรายการคำศัพท์';
        _message(_error!);
      }
      return {'status': 'outcome_unknown'};
    }
  }

  void _message(String message) {
    if (!_readCurrent) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
