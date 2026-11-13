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
    this.initialDraft,
    this.expectedOwnerId,
    this.categoryName,
    this.onCreated,
  }) : assert(word == null || initialDraft == null);

  final String categoryId;
  final VocabularyUseCases? vocabulary;
  final VocabularyWord? word;
  final CreateWordCommand? initialDraft;
  final String? expectedOwnerId;
  final String? categoryName;
  final ValueChanged<VocabularyWord>? onCreated;

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  late final TextEditingController _wordController;
  late final TextEditingController _meaningController;
  late final TextEditingController _partOfSpeechController;
  AppDependencies? _writeDependencies;
  bool _writeContextCaptured = false;
  String? _writeOwnerId;
  String? _writeCategoryId;
  CreateWordCommand? _writeDraft;
  VocabularyWord? _writeWord;
  bool _saving = false;
  String? _wordError;
  String? _meaningError;
  String? _partOfSpeechError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(
      text: widget.word?.spelling ?? widget.initialDraft?.spelling,
    );
    _meaningController = TextEditingController(
      text: widget.word?.meaning ?? widget.initialDraft?.meaning,
    );
    _partOfSpeechController = TextEditingController(
      text: widget.word?.partOfSpeech ?? widget.initialDraft?.partOfSpeech,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((widget.initialDraft != null ||
            widget.expectedOwnerId != null ||
            widget.word != null) &&
        !_writeContextCaptured) {
      _writeDependencies = AppDependenciesScope.maybeOf(context);
      _writeContextCaptured = true;
      _writeOwnerId = widget.word?.ownerId ?? widget.expectedOwnerId;
      _writeCategoryId = widget.categoryId;
      _writeDraft = widget.initialDraft;
      _writeWord = widget.word;
    }
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
          title: Text(
            widget.initialDraft != null
                ? 'ตรวจคำจากภาพ'
                : widget.word == null
                ? 'เพิ่มคำศัพท์'
                : 'แก้ไขคำศัพท์',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.categoryName != null) ...[
              Text('เก็บในชุด ${widget.categoryName}'),
              const SizedBox(height: 8),
            ],
            if (widget.initialDraft != null) ...[
              const Text('ผลสแกนยังไม่ยืนยัน ตรวจชื่อและกรอกคำแปลเอง'),
              const SizedBox(height: 16),
            ],
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
    final draft = widget.initialDraft;
    final word = widget.word;
    final expectedOwnerId = word?.ownerId ?? widget.expectedOwnerId;
    final bound = draft != null || word != null || expectedOwnerId != null;
    try {
      VocabularyWord? created;
      if (bound) await _requireWriteContext(useCases, expectedOwnerId);
      if (word == null) {
        created = await useCases.createWord(
          CreateWordCommand(
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: draft?.cefrLevel,
            source: draft?.source ?? 'manual',
          ),
          expectedOwnerId: expectedOwnerId,
        );
      } else {
        await useCases.updateWord(
          UpdateWordCommand(
            id: word.id,
            categoryId: widget.categoryId,
            spelling: _wordController.text,
            meaning: _meaningController.text,
            partOfSpeech: _partOfSpeechController.text,
            cefrLevel: word.cefrLevel,
            source: word.source,
          ),
        );
      }
      if (bound) {
        await _requireWriteContext(useCases, expectedOwnerId);
        if (word == null &&
            (created == null ||
                created.ownerId != expectedOwnerId ||
                created.categoryId != _writeCategoryId)) {
          throw const VocabularyNotFoundFailure();
        }
      }
      if (draft != null) {
        if (mounted) Navigator.pop<VocabularyWord>(context, created);
      } else if (mounted) {
        if (created != null) widget.onCreated?.call(created);
        Navigator.pop(context);
      }
    } on VocabularyNotFoundFailure {
      if (mounted) {
        setState(
          () =>
              _formError = 'บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่',
        );
      }
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

  Future<void> _requireWriteContext(
    VocabularyUseCases useCases,
    String? expectedOwnerId,
  ) async {
    if (!mounted ||
        !_writeContextCaptured ||
        expectedOwnerId == null ||
        !identical(AppDependenciesScope.maybeOf(context), _writeDependencies) ||
        _writeOwnerId != expectedOwnerId ||
        !identical(widget.initialDraft, _writeDraft) ||
        !identical(widget.word, _writeWord) ||
        (widget.expectedOwnerId != null &&
            widget.expectedOwnerId != expectedOwnerId) ||
        widget.categoryId != _writeCategoryId ||
        (_writeDraft != null && _writeDraft!.categoryId != widget.categoryId)) {
      throw const VocabularyNotFoundFailure();
    }
    final dependencies = _writeDependencies;
    final currentVocabulary = dependencies?.vocabulary;
    if (currentVocabulary != null && !identical(currentVocabulary, useCases)) {
      throw const VocabularyNotFoundFailure();
    }
    final owner = await (dependencies?.localOwners ?? useCases.owners)
        .getOrCreateActiveOwner();
    if (!mounted ||
        owner.id != expectedOwnerId ||
        !identical(AppDependenciesScope.maybeOf(context), dependencies) ||
        !identical(widget.initialDraft, _writeDraft) ||
        !identical(widget.word, _writeWord) ||
        widget.categoryId != _writeCategoryId ||
        (widget.expectedOwnerId != null &&
            widget.expectedOwnerId != expectedOwnerId)) {
      throw const VocabularyNotFoundFailure();
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
