import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_import_file_parser.dart';
import '../features/vocabulary/application/vocabulary_import_file_picker.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_import.dart';
import '../runtime/app_dependencies.dart';

class AddMultipleWordsScreen extends StatefulWidget {
  const AddMultipleWordsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.importer,
    this.vocabulary,
    this.filePicker,
    this.pasteTable = false,
    this.expectedOwnerId,
  });

  final String categoryId;
  final String categoryName;
  final ImportVocabulary? importer;
  final VocabularyUseCases? vocabulary;
  final VocabularyImportFilePicker? filePicker;
  final bool pasteTable;
  final String? expectedOwnerId;

  @override
  State<AddMultipleWordsScreen> createState() => _AddMultipleWordsScreenState();
}

class _AddMultipleWordsScreenState extends State<AddMultipleWordsScreen> {
  final _table = TextEditingController();
  AppDependencies? _scope;
  StreamSubscription<void>? _ownerWrites;
  ModalRoute<Object?>? _editDialog;
  bool _scopeCaptured = false;
  bool _invalidated = false;
  VocabularyImportPreview? _preview;
  List<Map<String, String>> _existingRows = const [];
  String? _error;
  bool _working = false;
  bool _cancelled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.expectedOwnerId == null) return;
    final scope = AppDependenciesScope.maybeOf(context);
    if (!_scopeCaptured) {
      _scopeCaptured = true;
      _scope = scope;
      _ownerWrites = scope?.watchLocalOwnerWrites()?.listen(
        (_) => _invalidate(),
        onError: (Object _) => _invalidate(),
      );
    } else if (!identical(scope, _scope)) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    setState(() {
      _invalidated = true;
      _table.clear();
      _preview = null;
      _existingRows = const [];
    });
    if (_editDialog case final route?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  Future<bool> _hasExpectedOwner() async {
    if (!mounted || _invalidated) return false;
    final expected = widget.expectedOwnerId;
    if (expected == null) return true;
    try {
      if (await _scope?.readActiveOwnerId() == expected) {
        return mounted && !_invalidated;
      }
    } catch (_) {
      // An unavailable owner lookup invalidates this draft.
    }
    _invalidate();
    return false;
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_ownerWrites?.cancel());
    _table.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final importer = widget.importer ?? dependencies?.vocabularyImporter;
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    final filePicker =
        widget.filePicker ?? dependencies?.vocabularyImportFilePicker;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _invalidated
              ? 'นำเข้าคำศัพท์'
              : 'นำเข้าคำศัพท์ · ${widget.categoryName}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_invalidated)
            const Text('ผู้ใช้เปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่')
          else ...[
            Text(
              widget.pasteTable
                  ? 'วางข้อความ CSV ที่มีคำศัพท์ คำแปล และชนิดของคำ'
                  : 'เลือกไฟล์ CSV หรือ JSON จากเครื่อง '
                        'ตรวจรายการก่อนยืนยันนำเข้า',
            ),
            const SizedBox(height: 12),
            if (widget.pasteTable) ...[
              TextField(
                key: const ValueKey('paste-import-csv'),
                controller: _table,
                enabled: !_working,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'ข้อความจากตาราง',
                  hintText: 'word,meaning,partOfSpeech',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_preview != null || _error != null) _cancelPreview();
                },
              ),
              OutlinedButton(
                onPressed: _working
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        _pickFile(
                          vocabulary,
                          () async => VocabularyImportFile(
                            name: 'pasted-table.csv',
                            mimeType: 'text/csv',
                            bytes: Uint8List.fromList(utf8.encode(_table.text)),
                          ),
                        );
                      },
                child: const Text('ตรวจคำจากตาราง'),
              ),
            ] else
              OutlinedButton.icon(
                key: const ValueKey('choose-import-file'),
                onPressed: _working || filePicker == null
                    ? null
                    : () => _pickFile(vocabulary, filePicker),
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(preview == null ? 'เลือกไฟล์' : 'เลือกไฟล์ใหม่'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('import-file-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 20),
              Text(
                'ผ่าน ${preview.readyCount} · '
                'ต้องแก้ ${preview.needsEditCount} · '
                'ซ้ำ ${preview.duplicateCount}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final row in preview.rows) _previewRow(row),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('cancel-import-preview'),
                      onPressed: _working ? null : _cancelPreview,
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('confirm-import'),
                      onPressed:
                          _working ||
                              importer == null ||
                              preview.needsEditCount > 0
                          ? null
                          : () => _import(importer),
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'กำลังนำเข้าคำศัพท์',
                              ),
                            )
                          : const Icon(Icons.file_upload_outlined),
                      label: const Text('ยืนยันนำเข้า'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _previewRow(VocabularyImportPreviewRow row) {
    final status = switch (row.status) {
      VocabularyImportPreviewStatus.ready => 'พร้อมนำเข้า',
      VocabularyImportPreviewStatus.needsEdit => 'ต้องแก้ไข',
      VocabularyImportPreviewStatus.duplicate => 'ซ้ำ',
    };
    return Semantics(
      container: true,
      label: 'แถว ${row.rowNumber} สถานะ $status',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(row.word.isEmpty ? 'ยังไม่มีคำศัพท์' : row.word),
        subtitle: Text(
          '${row.meaning.isEmpty ? 'ยังไม่มีความหมาย' : row.meaning} · $status',
        ),
        trailing: IconButton(
          key: ValueKey('edit-import-row-${row.rowNumber}'),
          tooltip: 'แก้ไขแถว ${row.rowNumber}',
          onPressed: _working ? null : () => _editRow(row),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  Future<void> _pickFile(
    VocabularyUseCases? vocabulary,
    VocabularyImportFilePicker filePicker,
  ) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (!await _hasExpectedOwner()) return;
      final file = await filePicker();
      if (file == null) return;
      if (!await _hasExpectedOwner()) return;
      setState(() {
        _preview = null;
        _existingRows = const [];
      });
      final words = vocabulary == null
          ? const <Map<String, String>>[]
          : (await vocabulary
                    .watchWords(
                      widget.categoryId,
                      expectedOwnerId: widget.expectedOwnerId,
                    )
                    .first)
                .map(
                  (word) => {
                    'word': word.spelling,
                    'meaning': word.meaning,
                    'partOfSpeech': word.partOfSpeech,
                  },
                )
                .toList(growable: false);
      final preview = parseVocabularyImportFile(
        fileName: file.name,
        mimeType: file.mimeType,
        bytes: file.bytes,
        existingRows: words,
      );
      if (!await _hasExpectedOwner()) return;
      setState(() {
        _existingRows = words;
        _preview = preview;
      });
    } on VocabularyImportFileFailure catch (error) {
      if (mounted) {
        setState(() {
          _preview = null;
          _existingRows = const [];
          _error = _failureMessage(error.code);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preview = null;
          _existingRows = const [];
          _error = 'อ่านไฟล์ไม่สำเร็จ';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editRow(VocabularyImportPreviewRow row) async {
    if (!await _hasExpectedOwner()) return;
    if (!mounted || _editDialog != null) return;
    var word = row.word;
    var meaning = row.meaning;
    var partOfSpeech = row.partOfSpeech;
    String? wordError;
    String? meaningError;
    String? partOfSpeechError;
    final edited = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        _editDialog = ModalRoute.of(dialogContext);
        if (_invalidated) return const SizedBox.shrink();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final nextWordError = _importFieldError(
                word,
                emptyMessage: 'กรอกคำศัพท์',
                maxLength: maxSpellingLength,
              );
              final nextMeaningError = _importFieldError(
                meaning,
                emptyMessage: 'กรอกความหมาย',
                maxLength: maxMeaningLength,
              );
              final nextPartOfSpeechError = _importFieldError(
                partOfSpeech,
                emptyMessage: 'กรอกชนิดของคำ',
                maxLength: maxPartOfSpeechLength,
              );
              setDialogState(() {
                wordError = nextWordError;
                meaningError = nextMeaningError;
                partOfSpeechError = nextPartOfSpeechError;
              });
              if (nextWordError != null ||
                  nextMeaningError != null ||
                  nextPartOfSpeechError != null) {
                return;
              }
              Navigator.pop(dialogContext, {
                'word': word,
                'meaning': meaning,
                'partOfSpeech': partOfSpeech,
              });
            }

            return AlertDialog(
              title: Text('แก้ไขแถว ${row.rowNumber}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const ValueKey('edit-import-word'),
                      initialValue: word,
                      maxLength: maxSpellingLength,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        word = value;
                        if (wordError != null) {
                          setDialogState(() => wordError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'คำศัพท์',
                        errorText: wordError,
                      ),
                    ),
                    TextFormField(
                      key: const ValueKey('edit-import-meaning'),
                      initialValue: meaning,
                      maxLength: maxMeaningLength,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        meaning = value;
                        if (meaningError != null) {
                          setDialogState(() => meaningError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'ความหมาย',
                        errorText: meaningError,
                      ),
                    ),
                    TextFormField(
                      key: const ValueKey('edit-import-part-of-speech'),
                      initialValue: partOfSpeech,
                      maxLength: maxPartOfSpeechLength,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        partOfSpeech = value;
                        if (partOfSpeechError != null) {
                          setDialogState(() => partOfSpeechError = null);
                        }
                      },
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'ชนิดของคำ',
                        errorText: partOfSpeechError,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  key: const ValueKey('save-import-row'),
                  onPressed: submit,
                  child: const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );
    _editDialog = null;
    if (edited == null || !await _hasExpectedOwner()) return;
    final preview = _preview;
    if (preview == null) return;
    final rows = preview.rows
        .map((candidate) {
          return candidate.rowNumber == row.rowNumber
              ? edited
              : candidate.toMap();
        })
        .toList(growable: false);
    setState(() {
      _preview = VocabularyImportPreview(
        sourceName: preview.sourceName,
        rows: reviewVocabularyImportRows(rows, existingRows: _existingRows),
      );
    });
  }

  void _cancelPreview() {
    setState(() {
      _preview = null;
      _existingRows = const [];
      _error = null;
    });
  }

  Future<void> _import(ImportVocabulary importer) async {
    final preview = _preview;
    if (preview == null || preview.needsEditCount > 0) return;
    setState(() {
      _working = true;
      _cancelled = false;
    });
    try {
      if (!await _hasExpectedOwner()) return;
      final result = await importer(
        categoryId: widget.categoryId,
        rows: preview.rows.map((row) => row.toMap()).toList(growable: false),
        sourceName: preview.sourceName,
        expectedOwnerId: widget.expectedOwnerId,
        isCancelled: () => _cancelled || _invalidated,
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
      if (mounted) setState(() => _working = false);
    }
  }
}

String? _importFieldError(
  String value, {
  required String emptyMessage,
  required int maxLength,
}) {
  final canonical = value.trim();
  if (canonical.isEmpty) return emptyMessage;
  if (canonical.length > maxLength) {
    return 'กรอกข้อมูลไม่เกิน $maxLength ตัวอักษร';
  }
  return null;
}

String _failureMessage(String code) => switch (code) {
  'emptyFile' => 'ไฟล์ว่าง',
  'fileTooLarge' => 'ไฟล์ใหญ่เกิน 1 MB',
  'tooManyRows' => 'ไฟล์มีเกิน 500 รายการ',
  'unsupportedType' => 'รองรับเฉพาะไฟล์ CSV และ JSON',
  'invalidEncoding' => 'ไฟล์ต้องเป็น UTF-8',
  _ => 'รูปแบบไฟล์ไม่ถูกต้อง',
};
