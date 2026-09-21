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

class _AddWordScreenState extends State<AddWordScreen> {
  late final TextEditingController _wordController;
  late final TextEditingController _meaningController;
  late final TextEditingController _partOfSpeechController;
  String? _cefrLevel;
  bool _saving = false;
  String? _formOwner;
  bool _ownerBindingStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    if (!_ownerBindingStarted && useCases != null) {
      _ownerBindingStarted = true;
      _bindLocalOwner(useCases);
    }
  }

  Future<void> _bindLocalOwner(VocabularyUseCases useCases) async {
    try {
      final owner = await useCases.owners.getOrCreateActiveOwner();
      if (mounted) {
        setState(() => _formOwner = widget.word?.ownerId ?? owner.id);
      }
    } catch (_) {
      // Preparing optional tool admission must not gate the native form.
    }
  }

  static const _cefrOptions = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word?.spelling);
    _meaningController = TextEditingController(text: widget.word?.meaning);
    _partOfSpeechController = TextEditingController(
      text: widget.word?.partOfSpeech,
    );
    _cefrLevel = widget.word?.cefrLevel;
  }

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
    _partOfSpeechController.dispose();
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
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final screen = Scaffold(
      appBar: AppBar(
        title: Text(widget.word == null ? 'เพิ่มคำศัพท์' : 'แก้ไขคำศัพท์'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('word-field'),
            controller: _wordController,
            onChanged: (_) => setState(() {}),
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
            controller: _meaningController,
            onChanged: (_) => setState(() {}),
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
            controller: _partOfSpeechController,
            onChanged: (_) => setState(() {}),
            maxLength: maxPartOfSpeechLength,
            decoration: const InputDecoration(
              labelText: 'ชนิดของคำ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('cefr-field-${_cefrLevel ?? 'none'}'),
            initialValue: _cefrLevel,
            decoration: const InputDecoration(
              labelText: 'ระดับ CEFR (ไม่บังคับ)',
              border: OutlineInputBorder(),
            ),
            items: _cefrOptions
                .map(
                  (level) => DropdownMenuItem(value: level, child: Text(level)),
                )
                .toList(),
            onChanged: (value) => setState(() => _cefrLevel = value),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('save-word'),
            onPressed: _saving || useCases == null
                ? null
                : () => _save(useCases),
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
          : (values) {
              if (!_admitted || _saving) return {'status': 'busy'};
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
            : (_) => _save(useCases, expectedOwnerId: _formOwner),
        child: screen,
      ),
    );
  }

  Future<Map<String, Object?>> _save(
    VocabularyUseCases useCases, {
    String? expectedOwnerId,
  }) async {
    if (!_admitted || _saving) return {'status': 'busy'};
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    bool allowed() =>
        _admitted &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.snapshot()['revision'] == revision);
    setState(() => _saving = true);
    try {
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
          expectedOwnerId: expectedOwnerId,
          mutationAllowed: allowed,
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
          expectedOwnerId: expectedOwnerId,
          mutationAllowed: allowed,
        );
      }
      final records = await useCases.readPinnedByIds([saved.id]);
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
                !w.isDeleted,
          )
          .firstOrNull;
      if (persisted == null) return {'status': 'verification_failed'};
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
    } on InvalidVocabularyFailure {
      _message('กรุณากรอกข้อมูลให้ครบและไม่เกินความยาวที่กำหนด');
      return {'status': 'invalid'};
    } on DuplicateVocabularyFailure {
      _message('มีคำศัพท์และความหมายนี้แล้ว');
      return {'status': 'duplicate'};
    } on CategoryWordLimitFailure {
      _message('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว');
      return {'status': 'limit'};
    } catch (_) {
      _message('บันทึกคำศัพท์ไม่สำเร็จ');
      return {'status': 'failed'};
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
