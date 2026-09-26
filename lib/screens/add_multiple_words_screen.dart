import 'dart:async';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/scheduler.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/domain/vocabulary_import.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';

class AddMultipleWordsScreen extends StatefulWidget {
  const AddMultipleWordsScreen({
    super.key,
    this.featureRegistry,
    required this.categoryId,
    required this.categoryName,
    this.importer,
  });

  final String categoryId;
  final String categoryName;
  final ImportVocabulary? importer;

  final FeatureRegistry? featureRegistry;

  @override
  State<AddMultipleWordsScreen> createState() => _AddMultipleWordsScreenState();
}

class _AddMultipleWordsScreenState extends State<AddMultipleWordsScreen>
    with WidgetsBindingObserver {
  final _rowsController = TextEditingController();
  ImportVocabulary? _importer;
  VocabularyUseCases? _vocabulary;
  FeatureRegistry? _features;
  Listenable? _featureChanges;
  ModalRoute<dynamic>? _route;
  StreamSubscription<Object?>? _ownerChanges;
  StreamSubscription<List<VocabularyCategory>>? _categories;
  bool _saving = false,
      _reading = false,
      _retired = false,
      _ownerRetired = false,
      _exited = false;
  bool _foreground = true, _tabVisible = true, _attempted = false;
  int _epoch = 0, _controls = 0;
  int? _categoryRevision;
  String? _formOwner, _error;
  Future<void>? _ready;
  PreparedVocabularyImport? _prepared;
  VocabularyImportResult? _committedResult;
  List<VocabularyWord>? _beforeAttempt;
  bool get _visible =>
      mounted &&
      !_exited &&
      _foreground &&
      _tabVisible &&
      _route?.isCurrent == true;
  bool get _readCurrent =>
      _visible &&
      !_ownerRetired &&
      _features?.isEnabled(Feature.vocabulary) == true;
  bool get _current => _readCurrent && !_retired;
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

  void _retire({bool owner = false}) {
    _retired = true;
    _ownerRetired |= owner;
    _epoch++;
    _controls++;
    _render();
  }

  void _featuresChanged() => _retire();
  void _readFailed() {
    if (!mounted || _exited) return;
    _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
    _controls++;
    _render();
  }

  void _bind() {
    final deps = AppDependenciesScope.maybeOf(context);
    final importer = widget.importer ?? deps?.vocabularyImporter;
    final vocabulary = deps?.vocabulary;
    final features = widget.featureRegistry ?? deps?.features;
    if (identical(importer, _importer) &&
        identical(vocabulary, _vocabulary) &&
        identical(features, _features)) {
      return;
    }
    _ownerChanges?.cancel();
    _categories?.cancel();
    _categories = null;
    _featureChanges?.removeListener(_featuresChanged);
    if (_importer != null) _retire(owner: true);
    _importer = importer;
    _vocabulary = vocabulary;
    _features = features;
    _featureChanges = features is Listenable ? features as Listenable : null;
    _featureChanges?.addListener(_featuresChanged);
    _ready = _read();
    if (vocabulary?.vocabulary case final DriftVocabularyRepository repo) {
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = WidgetsBinding.instance.lifecycleState;
    _foreground = s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _tabVisible = TickerMode.valuesOf(context).enabled;
    if (!_tabVisible || _route?.isCurrent == false) _retire();
    _bind();
  }

  @override
  void didUpdateWidget(covariant AddMultipleWordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        oldWidget.categoryName != widget.categoryName) {
      _retire(owner: true);
    }
    _bind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed;
    _retire();
  }

  @override
  void dispose() {
    _exited = true;
    _epoch++;
    _controls++;
    _ownerChanges?.cancel();
    _categories?.cancel();
    _featureChanges?.removeListener(_featuresChanged);
    WidgetsBinding.instance.removeObserver(this);
    _rowsController.dispose();
    super.dispose();
  }

  Future<bool> _owner({bool readOnly = false}) async {
    final epoch = _epoch;
    final importer = _importer;
    if (!(readOnly ? _readCurrent : _current) || importer == null) return false;
    final owner = await importer.owners.getOrCreateActiveOwner();
    if (epoch != _epoch || !(readOnly ? _readCurrent : _current)) return false;
    if (_formOwner != null && owner.id != _formOwner) {
      _retire(owner: true);
      return false;
    }
    _formOwner ??= owner.id;
    return true;
  }

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
    final vocabulary = _vocabulary;
    if (vocabulary == null) {
      throw StateError('vocabulary source unavailable');
    }
    final rows = await vocabulary.vocabulary.watchCategories(_formOwner!).first;
    if (!await _owner()) return false;
    if (!_categoryMatches(rows)) {
      _retire();
      return false;
    }
    _categoryRevision ??= rows
        .firstWhere((c) => c.id == widget.categoryId && c.ownerId == _formOwner)
        .localRevision;
    return true;
  }

  Future<void> _read() async {
    if (_reading || !_current || _importer == null) return;
    _reading = true;
    try {
      if (!await _snapshot()) return;
      _error = null;
      _categories ??= _vocabulary!.vocabulary
          .watchCategories(_formOwner!)
          .listen((rows) {
            if (!_categoryMatches(rows)) _retire();
          }, onError: (Object _) => _readFailed());
    } catch (_) {
      _readFailed();
    } finally {
      _reading = false;
      _render();
    }
  }

  List<Map<String, String>> _rows() => [
    for (final line in _rowsController.text.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) _parseLine(line),
  ];

  Map<String, String> _parseLine(String line) {
    final columns = line.split(',');
    return {
      'word': columns.isNotEmpty ? columns[0] : '',
      'meaning': columns.length > 1 ? columns[1] : '',
      'partOfSpeech': columns.length > 2 ? columns[2] : '',
    };
  }

  List<Map<String, Object>> _failures(
    List<VocabularyImportRowFailure> failures,
  ) => [
    for (final failure in failures.take(20))
      {'rowNumber': failure.rowNumber, 'code': failure.code},
  ];

  @override
  Widget build(BuildContext context) => ProductionFeatureGate(
    feature: Feature.vocabulary,
    registry: _features,
    builder: _buildContent,
  );
  Widget _buildContent(BuildContext context) {
    final controls = _controls;
    final importer = _importer;
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
          title: Text('นำเข้าคำศัพท์ · ${widget.categoryName}'),
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
                          _import(importer!, controls: controls);
                        } else {
                          _ready = _read();
                        }
                      },
                child: const Text('ลองใหม่'),
              ),
            const Text(
              'ใส่หนึ่งคำต่อบรรทัดในรูปแบบ\nคำศัพท์,ความหมาย,ชนิดของคำ',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('import-rows-field'),
              controller: _rowsController,
              enabled: !_saving && !_attempted,
              onChanged: (_) {
                if (editAllowed()) setState(() {});
              },
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                hintText: 'station,สถานี,noun\ntravel,เดินทาง,verb',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('import-words'),
              onPressed:
                  _saving ||
                      _attempted ||
                      importer == null ||
                      !_current ||
                      _error != null
                  ? null
                  : () => _import(importer, controls: controls),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload_outlined),
              label: const Text('นำเข้า'),
            ),
          ],
        ),
      ),
    );
    Future<bool> editAdmission() async {
      if (!editAllowed()) return false;
      try {
        return await _snapshot() && editAllowed();
      } catch (_) {
        _readFailed();
        return false;
      }
    }

    return MenuActionBinding(
      id: 'vocabulary/import-fill',
      label: 'กรอกข้อมูลนำเข้า (ยังไม่บันทึก)',
      ownerId: _formOwner,
      onInvoke: null,
      fields: const {'rows': 4000},
      onForm: _formOwner == null || importer == null
          ? null
          : (values) async {
              if (!await editAdmission()) return {'status': 'busy'};
              setState(() => _rowsController.text = values['rows']!);
              return {'status': 'filled', 'totalRows': _rows().length};
            },
      child: MenuActionBinding(
        id: 'vocabulary/import-preview',
        label: 'ตรวจรูปแบบแถวก่อนนำเข้า',
        ownerId: _formOwner,
        onInvoke: null,
        onForm: _formOwner == null || importer == null
            ? null
            : (_) async {
                if (!await editAdmission()) return {'status': 'busy'};
                final rows = _rows();
                final rejected = importer.previewRows(rows);
                return {
                  'status': 'previewed',
                  'totalRows': rows.length,
                  'validRows': rows.length - rejected.length,
                  'databaseChecked': false,
                  'rejected': _failures(rejected),
                  'rejectedCount': rejected.length,
                  'rejectedTruncated': rejected.length > 20,
                };
              },
        child: MenuActionBinding(
          id: 'vocabulary/import-save',
          label: 'นำเข้าและตรวจผลบันทึก',
          revisionKey: _rowsController.text,
          ownerId: _formOwner,
          onInvoke: null,
          onForm: _formOwner == null || importer == null
              ? null
              : (_) => _import(
                  importer,
                  expectedOwnerId: _formOwner,
                  controls: controls,
                ),
          child: screen,
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _import(
    ImportVocabulary importer, {
    String? expectedOwnerId,
    required int controls,
  }) async {
    if (controls != _controls ||
        _saving ||
        !identical(importer, _importer) ||
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
      if (_attempted) return await _reconcile(importer, verifyAllowed);
      if (!await _snapshot() || !allowed()) return {'status': 'stale'};
      _beforeAttempt = await _vocabulary!.vocabulary.listAllWords(_formOwner!);
      if (!await _owner() || !allowed()) return {'status': 'stale'};
      final rows = _rows();
      _attempted = true;
      final result = await importer(
        categoryId: widget.categoryId,
        rows: rows,
        sourceName: 'manual-import',
        isCancelled: () => !allowed(),
        expectedOwnerId: _formOwner,
        expectedCategoryRevision: _categoryRevision,
        onPrepared: (value) => _prepared = value,
      );
      _committedResult = result;
      return await _verifySaved(importer, result, verifyAllowed);
    } on VocabularyImportCancelled {
      if (verifyAllowed()) {
        try {
          if (!await _owner(readOnly: true)) return {'status': 'stale'};
          _error = 'บริบทการนำเข้าเปลี่ยนแล้ว กรุณาตรวจสอบก่อนลองใหม่';
        } catch (_) {
          if (verifyAllowed()) _readFailed();
        }
      }
      return {'status': 'stale'};
    } catch (_) {
      if (verifyAllowed()) {
        _error = _attempted
            ? 'ยังยืนยันผลการนำเข้าไม่ได้ กรุณาตรวจสอบก่อนลองใหม่'
            : 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
      }
      return {'status': _attempted ? 'outcome_unknown' : 'failed'};
    } finally {
      _saving = false;
      _render();
    }
  }

  Future<Map<String, Object?>> _reconcile(
    ImportVocabulary importer,
    bool Function() allowed,
  ) async {
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    if (_committedResult != null) {
      return _verifySaved(importer, _committedResult!, allowed);
    }
    final prepared = _prepared;
    if (prepared == null) return {'status': 'outcome_unknown'};
    final result = await importer.repository.readResult(
      importId: prepared.importId,
      ownerId: prepared.ownerId,
      categoryId: prepared.categoryId,
    );
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    if (result != null) {
      _committedResult = result;
      return _verifySaved(importer, result, allowed);
    }
    final words = await _vocabulary!.vocabulary.listAllWords(_formOwner!);
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    final unchanged =
        _beforeAttempt != null &&
        words.length == _beforeAttempt!.length &&
        words.every(
          (w) => _beforeAttempt!.any(
            (b) =>
                b.id == w.id &&
                b.ownerId == w.ownerId &&
                b.categoryId == w.categoryId &&
                b.localRevision == w.localRevision &&
                b.spelling == w.spelling &&
                b.meaning == w.meaning &&
                b.partOfSpeech == w.partOfSpeech &&
                b.isDeleted == w.isDeleted,
          ),
        );
    if (!unchanged || !await _snapshot() || !allowed()) {
      return {'status': 'outcome_unknown'};
    }
    _attempted = false;
    _prepared = null;
    _error = null;
    return {'status': 'retry_ready'};
  }

  Future<Map<String, Object?>> _verifySaved(
    ImportVocabulary importer,
    VocabularyImportResult result,
    bool Function() allowed,
  ) async {
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    _error = 'บันทึกแล้ว แต่ยังตรวจสอบผลไม่ได้ กรุณาลองใหม่เพื่อตรวจสอบผลเดิม';
    if (!await importer.verifyResult(
      result,
      expectedOwnerId: _formOwner!,
      categoryId: widget.categoryId,
    )) {
      return {'status': 'outcome_unknown'};
    }
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    _committedResult = null;
    _prepared = null;
    _attempted = false;
    _error = null;
    return _complete(result, 'saved');
  }

  Map<String, Object?> _complete(VocabularyImportResult result, String status) {
    if (!_readCurrent) return {'status': 'stale'};
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'เพิ่ม ${result.accepted} · ซ้ำ ${result.duplicates} · '
          'ไม่ผ่าน ${result.rejected.length}',
        ),
      ),
    );
    if (Navigator.of(context).canPop()) Navigator.pop(context);
    return {
      'status': status,
      'record': {
        'importId': result.importId,
        'accepted': result.accepted,
        'duplicates': result.duplicates,
        'rejected': _failures(result.rejected),
        'rejectedCount': result.rejected.length,
        'rejectedTruncated': result.rejected.length > 20,
      },
    };
  }
}
