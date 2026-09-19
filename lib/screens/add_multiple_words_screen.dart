import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text('นำเข้าคำศัพท์ · ${widget.categoryName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ใส่หนึ่งคำต่อบรรทัดในรูปแบบ\nคำศัพท์,ความหมาย,ชนิดของคำ'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('import-rows-field'),
            controller: _rowsController,
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
  }

  Future<void> _import(ImportVocabulary importer) async {
    if (!_admitted || _saving) return;
    setState(() {
      _saving = true;
      _cancelled = false;
    });
    try {
      final rows = <Map<String, String>>[];
      for (final line in _rowsController.text.split(RegExp(r'\r?\n'))) {
        if (line.trim().isEmpty) continue;
        final columns = line.split(',');
        rows.add({
          'word': columns.isNotEmpty ? columns[0] : '',
          'meaning': columns.length > 1 ? columns[1] : '',
          'partOfSpeech': columns.length > 2 ? columns[2] : '',
        });
      }
      final result = await importer(
        categoryId: widget.categoryId,
        rows: rows,
        sourceName: 'manual-import',
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'เพิ่ม ${result.accepted} · ซ้ำ ${result.duplicates} · '
            'ไม่ผ่าน ${result.rejected.length}',
          ),
        ),
      );
      Navigator.pop(context);
    } on VocabularyImportCancelled {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยกเลิกการนำเข้าแล้ว')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('นำเข้าคำศัพท์ไม่สำเร็จ')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
