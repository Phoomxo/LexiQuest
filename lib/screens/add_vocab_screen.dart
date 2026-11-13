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
  bool _saving = false;
  String? _wordError;
  String? _meaningError;
  String? _partOfSpeechError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word?.spelling);
    _meaningController = TextEditingController(text: widget.word?.meaning);
    _partOfSpeechController = TextEditingController(
      text: widget.word?.partOfSpeech,
    );
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
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.word == null ? 'เพิ่มคำศัพท์' : 'แก้ไขคำศัพท์'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('word-field'),
              controller: _wordController,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              maxLength: maxSpellingLength,
              decoration: InputDecoration(
                labelText: 'คำศัพท์',
                border: const OutlineInputBorder(),
                errorText: _wordError,
              ),
              onChanged: (_) {
                if (_wordError != null || _formError != null) {
                  setState(() {
                    _wordError = null;
                    _formError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('meaning-field'),
              controller: _meaningController,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              maxLength: maxMeaningLength,
              decoration: InputDecoration(
                labelText: 'ความหมาย',
                border: const OutlineInputBorder(),
                errorText: _meaningError,
              ),
              onChanged: (_) {
                if (_meaningError != null || _formError != null) {
                  setState(() {
                    _meaningError = null;
                    _formError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('part-of-speech-field'),
              controller: _partOfSpeechController,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              maxLength: maxPartOfSpeechLength,
              decoration: InputDecoration(
                labelText: 'ชนิดของคำ',
                border: const OutlineInputBorder(),
                errorText: _partOfSpeechError,
              ),
              onChanged: (_) {
                if (_partOfSpeechError != null || _formError != null) {
                  setState(() {
                    _partOfSpeechError = null;
                    _formError = null;
                  });
                }
              },
              onSubmitted: (_) {
                if (!_saving && useCases != null) _save(useCases);
              },
            ),
            if (_formError case final error?) ...[
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('word-form-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('save-word'),
              onPressed: _saving || useCases == null
                  ? null
                  : () => _save(useCases),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'กำลังบันทึกคำศัพท์',
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'กำลังบันทึก…' : 'บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(VocabularyUseCases useCases) async {
    if (_saving) return;
    final wordError = _requiredError(_wordController.text, 'กรอกคำศัพท์');
    final meaningError = _requiredError(
      _meaningController.text,
      'กรอกความหมาย',
    );
    final partOfSpeechError = _requiredError(
      _partOfSpeechController.text,
      'กรอกชนิดของคำ',
    );
    setState(() {
      _wordError = wordError;
      _meaningError = meaningError;
      _partOfSpeechError = partOfSpeechError;
      _formError = null;
    });
    if (wordError != null ||
        meaningError != null ||
        partOfSpeechError != null) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.word == null) {
        await useCases.createWord(
          CreateWordCommand(
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
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
            cefrLevel: widget.word!.cefrLevel,
            source: widget.word!.source,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on InvalidVocabularyFailure catch (error) {
      if (mounted) _showInvalidField(error.field);
    } on DuplicateVocabularyFailure {
      if (mounted) setState(() => _formError = 'มีคำศัพท์และความหมายนี้แล้ว');
    } on CategoryWordLimitFailure {
      if (mounted) {
        setState(() => _formError = 'หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว');
      }
    } catch (_) {
      if (mounted) setState(() => _formError = 'บันทึกคำศัพท์ไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredError(String value, String message) =>
      value.trim().isEmpty ? message : null;

  void _showInvalidField(String field) {
    setState(() {
      switch (field) {
        case 'spelling':
          _wordError = 'กรอกคำศัพท์ไม่เกิน $maxSpellingLength ตัวอักษร';
        case 'meaning':
          _meaningError = 'กรอกความหมายไม่เกิน $maxMeaningLength ตัวอักษร';
        case 'partOfSpeech':
          _partOfSpeechError =
              'กรอกชนิดของคำไม่เกิน $maxPartOfSpeechLength ตัวอักษร';
        default:
          _formError = 'ตรวจสอบข้อมูลคำศัพท์แล้วลองใหม่';
      }
    });
  }
}
