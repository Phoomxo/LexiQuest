import 'package:flutter/material.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';

class AddWordScreen extends StatefulWidget {
  const AddWordScreen({
    super.key,
    required this.categoryId,
    this.vocabulary,
    this.word,
  });

  final String categoryId;
  final VocabularyUseCases? vocabulary;
  final VocabularyWord? word;

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  late final TextEditingController _wordController;
  late final TextEditingController _meaningController;
  late final TextEditingController _partOfSpeechController;
  String? _cefrLevel;
  bool _saving = false;

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

  @override
  Widget build(BuildContext context) {
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.word == null ? 'เพิ่มคำศัพท์' : 'แก้ไขคำศัพท์'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('word-field'),
            controller: _wordController,
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
            maxLength: maxPartOfSpeechLength,
            decoration: const InputDecoration(
              labelText: 'ชนิดของคำ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('cefr-field'),
            initialValue: _cefrLevel,
            decoration: const InputDecoration(
              labelText: 'ระดับ CEFR (ไม่บังคับ)',
              border: OutlineInputBorder(),
            ),
            items: _cefrOptions
                .map(
                  (level) => DropdownMenuItem(
                    value: level,
                    child: Text(level),
                  ),
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
  }

  Future<void> _save(VocabularyUseCases useCases) async {
    setState(() => _saving = true);
    try {
      if (widget.word == null) {
        await useCases.createWord(
          CreateWordCommand(
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: _cefrLevel,
          ),
        );
      } else {
        await useCases.updateWord(
          UpdateWordCommand(
            id: widget.word!.id,
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: _cefrLevel,
            source: widget.word!.source,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on InvalidVocabularyFailure {
      _message('กรุณากรอกข้อมูลให้ครบและไม่เกินความยาวที่กำหนด');
    } on DuplicateVocabularyFailure {
      _message('มีคำศัพท์และความหมายนี้แล้ว');
    } on CategoryWordLimitFailure {
      _message('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว');
    } catch (_) {
      _message('บันทึกคำศัพท์ไม่สำเร็จ');
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
