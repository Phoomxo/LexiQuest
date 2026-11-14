import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_import_file_parser.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../services/custom_wordbook_importer.dart';
import '../widgets/adaptive_content_pane.dart';
import 'srs_flashcards_screen.dart';

enum _Step { menu, edit, error, preview, recall, reveal, result }

class WordbookImportScreen extends StatefulWidget {
  final CustomWordbookImporter? importer;
  final String? expectedOwnerId;
  final Future<void> Function()? onSaveToLibrary;
  final Future<void> Function()? onPasteToLibrary;

  const WordbookImportScreen({
    super.key,
    this.importer,
    this.expectedOwnerId,
    this.onSaveToLibrary,
    this.onPasteToLibrary,
  });

  @override
  State<WordbookImportScreen> createState() => _WordbookImportScreenState();
}

class _WordbookImportScreenState extends State<WordbookImportScreen> {
  late final CustomWordbookImporter _importer;
  final TextEditingController _textController = TextEditingController();
  List<Map<String, String>> _parsedWords = [];
  bool _isJsonMode = false;

  AppDependencies? _scope;
  StreamSubscription<void>? _ownerWrites;
  bool _bound = false;
  bool _authorized = false;
  bool _invalidated = false;
  bool _busy = false;
  _Step _step = _Step.menu;
  String _sourceName = '';
  String _draft = '';
  String? _repair;
  String? _error;
  List<VocabularyImportPracticeWord> _words = const [];
  int _cardIndex = 0;

  bool get _production => widget.expectedOwnerId != null;

  bool get _current =>
      mounted &&
      !_invalidated &&
      identical(AppDependenciesScope.maybeOf(context), _scope) &&
      ModalRoute.isCurrentOf(context) == true;

  @override
  void initState() {
    super.initState();
    _importer = widget.importer ?? CustomWordbookImporter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_production) return;
    final scope = AppDependenciesScope.maybeOf(context);
    if (_bound) {
      if (!identical(_scope, scope)) _invalidate();
      return;
    }
    _bound = true;
    _scope = scope;
    _ownerWrites = scope?.watchLocalOwnerWrites()?.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
    unawaited(_initializeOwner());
  }

  @override
  void didUpdateWidget(covariant WordbookImportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId) _invalidate();
  }

  Future<void> _initializeOwner() async {
    final allowed = await _checkOwner();
    if (mounted && allowed && !_invalidated) {
      setState(() => _authorized = true);
    }
  }

  Future<bool> _checkOwner() async {
    if (_invalidated) return false;
    try {
      final owner = await _scope?.readActiveOwnerId();
      if (!mounted || _invalidated) return false;
      if (owner != null &&
          owner == widget.expectedOwnerId &&
          identical(AppDependenciesScope.maybeOf(context), _scope)) {
        return true;
      }
    } catch (_) {
      // Close the draft if the active owner can no longer be verified.
    }
    _invalidate();
    return false;
  }

  void _clearDraft() {
    _step = _Step.menu;
    _sourceName = '';
    _draft = '';
    _repair = null;
    _error = null;
    _words = const [];
    _cardIndex = 0;
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    setState(() {
      _invalidated = true;
      _authorized = false;
      _clearDraft();
    });
  }

  void _openSample() {
    if (!_current || !_authorized || _busy) return;
    setState(() {
      _sourceName = 'ของในกระเป๋า.json';
      _draft =
          '[\n'
          '  {"word":"pencil","meaning":"ดินสอ"},\n'
          '  {"word":"wallet","meaning":"กระเป๋าสตางค์"}\n';
      _step = _Step.edit;
    });
  }

  Future<void> _pickFile() async {
    final pick = _scope?.vocabularyImportFilePicker;
    if (pick == null || !_current || !_authorized || _busy) return;
    setState(() => _busy = true);
    try {
      if (!await _checkOwner() || !_current) return;
      final file = await pick();
      if (file == null || !_current || !await _checkOwner() || !_current) {
        return;
      }
      final draft = readVocabularyImportDraft(
        fileName: file.name,
        bytes: file.bytes,
        mimeType: file.mimeType,
      );
      setState(() {
        _sourceName = file.name;
        _draft = draft;
        _step = _Step.edit;
      });
    } catch (failure) {
      if (_current && await _checkOwner()) {
        _showFileError(
          failure is VocabularyImportFileFailure
              ? failure.code
              : 'pickerFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFileError(String code) {
    if (!_current) return;
    setState(() {
      _error = code;
      _step = _Step.error;
    });
  }

  Future<void> _openLibraryImport(Future<void> Function() open) async {
    if (!_current || !_authorized || _busy) return;
    setState(() => _busy = true);
    try {
      if (await _checkOwner() && _current) await open();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _readDraft() {
    if (!_current || _step != _Step.edit) return;
    FocusScope.of(context).unfocus();
    try {
      final words = parseVocabularyImportPractice(_draft);
      setState(() {
        _words = words;
        _repair = null;
        _step = _Step.preview;
      });
    } on VocabularyImportFileFailure catch (failure) {
      String? repair;
      List<VocabularyImportPracticeWord> recovered = const [];
      if (failure.code == 'malformedJson') {
        final candidate = '${_draft.trimRight()}]';
        try {
          recovered = parseVocabularyImportPractice(candidate);
          repair = candidate;
        } on VocabularyImportFileFailure {
          // Offer this edit only when it restores a valid practice list.
        }
      }
      setState(() {
        _repair = repair;
        _words = recovered;
      });
      _showFileError(failure.code);
    }
  }

  void _goto(_Step step) => setState(() => _step = step);

  void _back() {
    switch (_step) {
      case _Step.menu:
        Navigator.maybePop(context);
      case _Step.error when _sourceName.isNotEmpty:
        _goto(_Step.edit);
      case _Step.edit || _Step.error || _Step.preview:
        setState(_clearDraft);
      case _Step.recall || _Step.result:
        _goto(_Step.preview);
      case _Step.reveal:
        _goto(_Step.recall);
    }
  }

  void _processImport() {
    final rawText = _textController.text.trim();
    if (rawText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาใส่ข้อความคำศัพท์ CSV หรือ JSON')),
      );
      return;
    }

    try {
      final results = _isJsonMode
          ? _importer.parseJson(rawText)
          : _importer.parseCsv(rawText);

      setState(() {
        _parsedWords = results;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('นำเข้าคำศัพท์สำเร็จ ${results.length} คำ!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('รูปแบบไฟล์ไม่ถูกต้อง: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_ownerWrites?.cancel());
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _production ? _practiceScreen(context) : _legacyImport(context);
  }

  Widget _practiceScreen(BuildContext context) {
    final title = switch (_step) {
      _Step.menu => 'นำเข้าชุดคำ',
      _Step.edit => 'ตรวจรายการจากไฟล์',
      _Step.error => 'ยังอ่านไฟล์นี้ไม่ได้',
      _Step.preview => 'พร้อมฝึก ${_words.length} คำ',
      _Step.recall => 'นึกคำแปล',
      _Step.reveal => 'ตรวจคำแปลของคุณ',
      _Step.result when _words.length == 2 => 'ฝึกครบทั้งสองคำแล้ว',
      _Step.result => 'ฝึกครบ ${_words.length} คำแล้ว',
    };
    return PopScope<void>(
      canPop: _step == _Step.menu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.menu) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(context, title),
        ),
        body: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: SafeArea(
            child: ListView(
              key: ValueKey(_step),
              padding: const EdgeInsets.all(20),
              children: _practiceBody(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _practiceBody() {
    if (!_authorized) {
      return [
        if (_invalidated) ...[
          const Text('บัญชีที่ใช้งานเปลี่ยนไป เปิดหน้านี้จากคลังคำอีกครั้ง'),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('กลับคลังคำ'),
          ),
        ] else
          const Text('กำลังตรวจบัญชีที่ใช้งาน'),
      ];
    }
    final theme = Theme.of(context);
    switch (_step) {
      case _Step.menu:
        return [
          if (widget.onSaveToLibrary case final save?)
            OutlinedButton(
              onPressed: _busy ? null : () => _openLibraryImport(save),
              child: const Text('เพิ่มคำจากตารางเข้าคลัง'),
            ),
          if (widget.onPasteToLibrary case final paste?)
            OutlinedButton(
              onPressed: _busy ? null : () => _openLibraryImport(paste),
              child: const Text('วางคำจากตาราง'),
            ),
          FilledButton(
            onPressed: _busy || _scope?.vocabularyImportFilePicker == null
                ? null
                : _pickFile,
            child: const Text('ฝึกจากรายการ JSON'),
          ),
          TextButton(
            onPressed: _busy ? null : _openSample,
            child: const Text('ลองไฟล์ที่รูปแบบผิด'),
          ),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('กลับคลังคำ'),
          ),
        ];
      case _Step.edit:
        return [
          Text(_sourceName),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _draft,
            onChanged: (value) => _draft = value,
            minLines: 4,
            maxLines: 8,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            decoration: const InputDecoration(labelText: 'รายการในไฟล์'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _readDraft,
            child: const Text('อ่านรายการคำ'),
          ),
          TextButton(onPressed: _back, child: const Text('ยกเลิก')),
        ];
      case _Step.error:
        return [
          if (_sourceName.isNotEmpty) Text(_sourceName),
          Semantics(liveRegion: true, child: Text(_errorMessage)),
          const SizedBox(height: 12),
          if (_repair case final repair?)
            FilledButton(
              onPressed: () {
                _draft = repair;
                _goto(_Step.edit);
              },
              child: const Text('เติม ] ในร่าง'),
            )
          else if (_sourceName.isNotEmpty)
            FilledButton(
              onPressed: _back,
              child: const Text('กลับไปแก้รายการ'),
            ),
          TextButton(
            onPressed: () => setState(_clearDraft),
            child: const Text('ยกเลิกการนำเข้า'),
          ),
          if (_repair != null) ...[
            Text('คำที่ยังอยู่ในร่าง', style: theme.textTheme.titleMedium),
            for (final word in _words)
              ListTile(title: Text(word.word), subtitle: Text(word.meaning)),
          ],
        ];
      case _Step.preview:
      case _Step.result:
        final completed = _step == _Step.result;
        return [
          Text(_sourceName),
          const SizedBox(height: 8),
          Text(
            completed ? 'คำที่เปิดทบทวน' : 'ใช้ฝึกในรอบนี้',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: completed
                ? () => Navigator.pop(context)
                : () {
                    if (!_current || _step != _Step.preview) return;
                    setState(() {
                      _cardIndex = 0;
                      _step = _Step.recall;
                    });
                  },
            child: Text(
              completed
                  ? 'กลับคลังคำ'
                  : _words.length == 2
                  ? 'ฝึกสองคำนี้'
                  : 'ฝึกชุดนี้',
            ),
          ),
          TextButton(
            onPressed: _back,
            child: Text(completed ? 'ทบทวนอีกครั้ง' : 'กลับไปเลือกไฟล์'),
          ),
          for (final word in _words)
            ListTile(title: Text(word.word), subtitle: Text(word.meaning)),
        ];
      case _Step.recall:
      case _Step.reveal:
        final reveal = _step == _Step.reveal;
        final word = _words[_cardIndex];
        return [
          Semantics(
            liveRegion: true,
            header: true,
            child: Text('คำที่ ${_cardIndex + 1} จาก ${_words.length}'),
          ),
          const SizedBox(height: 12),
          Text(word.word, style: theme.textTheme.headlineMedium),
          Text(reveal ? word.meaning : 'คำนี้แปลว่าอะไร'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final shownStep = reveal ? _Step.reveal : _Step.recall;
              if (!_current || _step != shownStep) return;
              if (reveal) {
                setState(() {
                  _cardIndex++;
                  _step = _cardIndex == _words.length
                      ? _Step.result
                      : _Step.recall;
                });
              } else {
                _goto(_Step.reveal);
              }
            },
            child: Text(reveal ? 'จำได้แล้ว' : 'เปิดคำแปล'),
          ),
          TextButton(
            onPressed: _back,
            child: Text(reveal ? 'ลองนึกอีกครั้ง' : 'เลิกฝึกรอบนี้'),
          ),
        ];
    }
  }

  String get _errorMessage {
    if (_repair != null) return 'ขาดเครื่องหมาย ] ที่ท้ายรายการ';
    return switch (_error) {
      'unsupportedType' => 'เลือกไฟล์ .json เพื่อฝึกจากไฟล์',
      'emptyFile' => 'ไฟล์นี้ไม่มีรายการคำ',
      'fileTooLarge' => 'ไฟล์นี้มีขนาดเกิน 1 MB',
      'invalidEncoding' => 'บันทึกไฟล์เป็นข้อความ UTF-8 แล้วเลือกใหม่',
      'tooManyRows' => 'แต่ละไฟล์ฝึกได้ไม่เกิน 500 คำ',
      'invalidPracticeList' => 'รายการคำต้องขึ้นต้นด้วย [ และลงท้ายด้วย ]',
      'invalidPracticeRow' => 'แต่ละรายการต้องมีคำศัพท์และคำแปล',
      'malformedJson' => 'ตรวจรูปแบบ JSON แล้วลองอีกครั้ง',
      _ => 'เปิดไฟล์ไม่ได้ ลองเลือกไฟล์อีกครั้ง',
    };
  }

  Widget _legacyImport(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'นำเข้าสมุดคำศัพท์ส่วนตัว (Import Wordbook)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รูปแบบข้อมูล:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ToggleButtons(
                  isSelected: [!_isJsonMode, _isJsonMode],
                  onPressed: (index) {
                    setState(() {
                      _isJsonMode = index == 1;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: Colors.teal,
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('CSV'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('JSON'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isJsonMode
                  ? 'ตัวอย่าง: [{"word": "apple", "translation": "แอปเปิ้ล"}]'
                  : 'ตัวอย่าง CSV: word,translation,example\napple,แอปเปิ้ล,Red apple',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'วางข้อความคำศัพท์ที่นี่...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _processImport,
              icon: const Icon(Icons.file_upload),
              label: const Text('ประมวลผลนำเข้าคำศัพท์'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 20),
            if (_parsedWords.isNotEmpty) ...[
              Text(
                'รายการคำศัพท์ที่นำเข้า (${_parsedWords.length} คำ):',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _parsedWords.length,
                  itemBuilder: (context, index) {
                    final item = _parsedWords[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        item['word'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(item['translation'] ?? ''),
                    );
                  },
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'learning/import-srs',
                      builder: (context) =>
                          SrsFlashcardsScreen(wordList: _parsedWords),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('เริ่มเรียนรู้คำศัพท์ชุดนี้ทันที'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
