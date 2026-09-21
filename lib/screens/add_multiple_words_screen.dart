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

class _AddMultipleWordsScreenState extends State<AddMultipleWordsScreen> {
  final TextEditingController _rowsController = TextEditingController();
  bool _saving = false;
  bool _cancelled = false;
  String? _formOwner;
  bool _ownerBindingStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final importer =
        widget.importer ??
        AppDependenciesScope.maybeOf(context)?.vocabularyImporter;
    if (!_ownerBindingStarted && importer != null) {
      _ownerBindingStarted = true;
      _bindOwner(importer);
    }
  }

  Future<void> _bindOwner(ImportVocabulary importer) async {
    try {
      final owner = await importer.owners.getOrCreateActiveOwner();
      if (mounted) setState(() => _formOwner = owner.id);
    } catch (_) {
      // Local form interaction remains available without optional tool admission.
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
  void dispose() {
    _cancelled = true;
    _rowsController.dispose();
    super.dispose();
  }

  FeatureRegistry? get _features =>
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => ProductionFeatureGate(
    feature: Feature.vocabulary,
    registry: _features,
    builder: _buildContent,
  );

  Widget _buildContent(BuildContext context) {
    final importer =
        widget.importer ??
        AppDependenciesScope.maybeOf(context)?.vocabularyImporter;
    final screen = Scaffold(
      appBar: AppBar(title: Text('นำเข้าคำศัพท์ · ${widget.categoryName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ใส่หนึ่งคำต่อบรรทัดในรูปแบบ\nคำศัพท์,ความหมาย,ชนิดของคำ'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('import-rows-field'),
            controller: _rowsController,
            onChanged: (_) => setState(() {}),
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
            onPressed: _saving || importer == null
                ? null
                : () => _import(importer),
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
    );
    return MenuActionBinding(
      id: 'vocabulary/import-fill',
      label: 'กรอกข้อมูลนำเข้า (ยังไม่บันทึก)',
      ownerId: _formOwner,
      onInvoke: null,
      fields: const {'rows': 4000},
      onForm: _formOwner == null || importer == null
          ? null
          : (values) {
              if (!_admitted || _saving) return {'status': 'busy'};
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
            : (_) {
                if (!_admitted || _saving) return {'status': 'busy'};
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
              : (_) => _import(importer, expectedOwnerId: _formOwner),
          child: screen,
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _import(
    ImportVocabulary importer, {
    String? expectedOwnerId,
  }) async {
    if (!_admitted || _saving) return {'status': 'busy'};
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    bool cancelled() =>
        _cancelled ||
        !_admitted ||
        (expectedOwnerId != null &&
            (registry?.currentOwner() != expectedOwnerId ||
                registry?.snapshot()['revision'] != revision));
    setState(() {
      _saving = true;
      _cancelled = false;
    });
    try {
      final rows = _rows();
      final result = await importer(
        categoryId: widget.categoryId,
        rows: rows,
        sourceName: 'manual-import',
        isCancelled: cancelled,
        expectedOwnerId: expectedOwnerId,
      );
      if (expectedOwnerId != null &&
          !await importer.verifyResult(
            result,
            expectedOwnerId: expectedOwnerId,
            categoryId: widget.categoryId,
          )) {
        return {'status': 'verification_failed'};
      }
      if (!mounted) return {'status': 'cancelled'};
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
        'status': expectedOwnerId == null ? 'invoked' : 'saved',
        'record': {
          'importId': result.importId,
          'accepted': result.accepted,
          'duplicates': result.duplicates,
          'rejected': _failures(result.rejected),
          'rejectedCount': result.rejected.length,
          'rejectedTruncated': result.rejected.length > 20,
        },
      };
    } on VocabularyImportCancelled {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยกเลิกการนำเข้าแล้ว')));
      }
      return {'status': 'cancelled'};
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('นำเข้าคำศัพท์ไม่สำเร็จ')));
      }
      return {'status': 'failed'};
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
