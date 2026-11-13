import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import '../navigation/app_routes.dart';
import 'object_scanner_screen.dart';
import 'quiz_screen.dart';
import 'score_screen.dart';
import 'source_practice_screen.dart';

enum _AddWordMethod { manual, camera, file }

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.vocabulary,
    this.importer,
    this.startAdding = false,
    this.initialQuery = '',
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? importer;
  final bool startAdding;
  final String initialQuery;

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  late final TextEditingController _searchController;
  late String _query;
  VocabularyUseCases? _vocabulary;
  String? _categoryId;
  Stream<List<VocabularyWord>>? _words;
  ProgressUseCases? _progress;
  Future<SessionHistoryEntry?>? _latest;
  bool _addStarted = false;
  bool _openingLatest = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _query = normalizeVocabularyText(widget.initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final useCases = widget.vocabulary ?? dependencies?.vocabulary;
    final importer = widget.importer ?? dependencies?.vocabularyImporter;
    final learning = dependencies?.learning;
    final sourcePicker = dependencies?.sourcePracticeFilePicker;
    final features =
        dependencies?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
    if (!identical(useCases, _vocabulary) ||
        _categoryId != widget.categoryId ||
        !identical(_progress, dependencies?.progress)) {
      _vocabulary = useCases;
      _categoryId = widget.categoryId;
      _words = useCases?.watchWords(widget.categoryId);
      _progress = dependencies?.progress;
      _latest = _progress?.loadLatestSessionForCategory(widget.categoryId);
      _latest?.ignore();
    }
    if (widget.startAdding && !_addStarted && useCases != null) {
      _addStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddWordOptions(context, useCases, importer, features);
      });
    }
    final canPracticeSource =
        useCases != null &&
        learning != null &&
        sourcePicker != null &&
        features.isVisible(FieldFeature.reading);
    final canPractice =
        learning != null && features.isVisible(FieldFeature.quiz);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, widget.categoryName),
      ),
      body: AdaptiveContentPane(
        child: useCases == null
            ? const Center(child: Text('ฐานข้อมูลในเครื่องไม่พร้อมใช้งาน'))
            : StreamBuilder<List<VocabularyWord>>(
                key: ValueKey((useCases, widget.categoryId)),
                stream: _words,
                builder: (context, snapshot) {
                  final allWords = snapshot.data ?? const <VocabularyWord>[];
                  final words = allWords
                      .where(
                        (word) =>
                            word.normalizedSpelling.contains(_query) ||
                            word.normalizedMeaning.contains(_query),
                      )
                      .toList(growable: false);
                  return CustomScrollView(
                    key: PageStorageKey(
                      'vocabulary-words:${widget.categoryId}',
                    ),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SearchBar(
                                controller: _searchController,
                                hintText: 'ค้นหาคำศัพท์',
                                elevation: const WidgetStatePropertyAll(0),
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                                leading: const Icon(Icons.search),
                                onChanged: (value) => setState(
                                  () => _query = normalizeVocabularyText(value),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (canPractice) ...[
                                FilledButton.icon(
                                  onPressed:
                                      snapshot.hasError || allWords.isEmpty
                                      ? null
                                      : () async {
                                          await AppNavigator.pushPage<void>(
                                            context,
                                            AppPage<void>(
                                              name: 'learning/category-quiz',
                                              builder: (_) => QuizScreen(
                                                categoryId: widget.categoryId,
                                                categoryName:
                                                    widget.categoryName,
                                                learning: learning,
                                              ),
                                            ),
                                          );
                                          _refreshLatest();
                                        },
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('ฝึกจากชุดนี้'),
                                ),
                                if (!snapshot.hasError &&
                                    snapshot.hasData &&
                                    allWords.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'เพิ่มคำอย่างน้อย 1 คำก่อนเริ่มฝึก',
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                              OutlinedButton.icon(
                                key: const ValueKey('add-word'),
                                onPressed: () => _showAddWordOptions(
                                  context,
                                  useCases,
                                  importer,
                                  features,
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('เพิ่มคำ'),
                              ),
                              if (_latest != null &&
                                  features.isVisible(FieldFeature.mastery))
                                FutureBuilder<SessionHistoryEntry?>(
                                  key: ValueKey((_progress, widget.categoryId)),
                                  future: _latest,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState !=
                                        ConnectionState.done) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: LinearProgressIndicator(
                                          semanticsLabel:
                                              'กำลังอ่านผลล่าสุดของชุดนี้',
                                        ),
                                      );
                                    }
                                    if (snapshot.hasError) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Semantics(
                                            liveRegion: true,
                                            child: const Text(
                                              'อ่านผลล่าสุดไม่สำเร็จ',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _refreshLatest,
                                            child: const Text(
                                              'ลองอ่านผลอีกครั้ง',
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    final entry = snapshot.data;
                                    if (entry == null) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'ยังไม่มีผลการฝึกที่บันทึกสำหรับชุดนี้',
                                        ),
                                      );
                                    }
                                    final summary = entry.summary;
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'ผลล่าสุด · ${summary.score}% · ตอบถูก ${summary.correctCount} จาก ${summary.correctCount + summary.wrongCount}',
                                          ),
                                          TextButton.icon(
                                            onPressed: _openingLatest
                                                ? null
                                                : _openLatestResult,
                                            icon: const Icon(Icons.history),
                                            label: const Text('ดูผลล่าสุด'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              if (canPracticeSource) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  children: [
                                    TextButton.icon(
                                      key: const ValueKey('source-practice'),
                                      onPressed: () =>
                                          AppNavigator.pushPage<void>(
                                            context,
                                            AppPage<void>(
                                              name:
                                                  'vocabulary/source-practice',
                                              builder: (_) =>
                                                  SourcePracticeScreen(
                                                    categoryId:
                                                        widget.categoryId,
                                                    categoryName:
                                                        widget.categoryName,
                                                    vocabulary: useCases,
                                                    learning: learning,
                                                    filePicker: sourcePicker,
                                                    associativeLearning:
                                                        dependencies
                                                            ?.associativeLearning,
                                                  ),
                                            ),
                                          ),
                                      icon: const Icon(
                                        Icons.menu_book_outlined,
                                      ),
                                      label: const Text('ฝึกจากไฟล์'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (snapshot.hasError)
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: const Text('อ่านคำศัพท์ไม่สำเร็จ'),
                              ),
                              TextButton(
                                onPressed: () => setState(
                                  () => _words = useCases.watchWords(
                                    widget.categoryId,
                                  ),
                                ),
                                child: const Text('ลองใหม่'),
                              ),
                            ],
                          ),
                        )
                      else if (!snapshot.hasData)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'กำลังโหลดคำศัพท์',
                            ),
                          ),
                        )
                      else if (words.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              allWords.isEmpty
                                  ? 'ยังไม่มีคำศัพท์ในหมวดนี้'
                                  : 'ไม่พบคำศัพท์ที่ค้นหา',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          sliver: SliverList.builder(
                            itemCount: words.length,
                            itemBuilder: (context, index) {
                              final word = words[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                title: Text(word.spelling),
                                subtitle: Text(
                                  '${word.meaning} · ${word.partOfSpeech}',
                                ),
                                onTap: () => _openWordEditor(
                                  context,
                                  useCases,
                                  word: word,
                                ),
                                trailing: IconButton(
                                  tooltip: 'ลบคำศัพท์ ${word.spelling}',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _deleteWord(context, useCases, word),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  void _refreshLatest() {
    if (mounted) {
      setState(() {
        _latest = _progress?.loadLatestSessionForCategory(widget.categoryId);
        _latest?.ignore();
      });
    }
  }

  Future<void> _openLatestResult() async {
    final progress = _progress;
    final categoryId = widget.categoryId;
    if (progress == null || _openingLatest) return;
    setState(() => _openingLatest = true);
    try {
      final entry = await progress.loadLatestSessionForCategory(categoryId);
      if (!mounted) return;
      if (!identical(
            progress,
            AppDependenciesScope.maybeOf(context)?.progress,
          ) ||
          widget.categoryId != categoryId ||
          (entry != null && entry.categoryId != categoryId)) {
        throw StateError('latest result context changed');
      }
      if (entry == null) {
        _refreshLatest();
        return;
      }
      final summary = entry.summary;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/category-latest-score',
          builder: (_) => ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
            sessionId: summary.id,
            categoryName: entry.categoryName ?? widget.categoryName,
            mistakes: entry.mistakes,
            returnLabel: 'กลับไปที่ชุดคำ',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อ่านผลล่าสุดไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingLatest = false);
    }
  }

  Future<void> _showAddWordOptions(
    BuildContext context,
    VocabularyUseCases useCases,
    ImportVocabulary? importer,
    FieldFeatureRegistry features,
  ) async {
    final method = await showModalBottomSheet<_AddWordMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'เพิ่มคำใน ${widget.categoryName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('พิมพ์คำศัพท์'),
                onTap: () => Navigator.pop(sheetContext, _AddWordMethod.manual),
              ),
              if (features.isVisible(FieldFeature.objectScanner))
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('ถ่ายภาพ'),
                  subtitle:
                      features.stateOf(FieldFeature.objectScanner) ==
                          FieldFeatureState.limited
                      ? const Text('อนุญาตกล้องและเตรียมโมเดลก่อนถ่าย')
                      : null,
                  onTap: () =>
                      Navigator.pop(sheetContext, _AddWordMethod.camera),
                ),
              ListTile(
                key: const ValueKey('import-words'),
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('นำเข้าจากไฟล์'),
                subtitle: Text(
                  importer == null
                      ? 'ยังไม่พร้อมนำเข้าในขณะนี้'
                      : 'เลือกไฟล์ CSV หรือ JSON แล้วตรวจรายการ',
                ),
                enabled: importer != null,
                onTap: importer == null
                    ? null
                    : () => Navigator.pop(sheetContext, _AddWordMethod.file),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (method) {
      case _AddWordMethod.manual:
        _openWordEditor(context, useCases);
        return;
      case _AddWordMethod.camera:
        await AppNavigator.pushPage<VocabularyWord>(
          context,
          AppPage<VocabularyWord>(
            name: 'vocabulary/camera',
            builder: (_) => ObjectScannerScreen(
              targetCategoryId: widget.categoryId,
              targetCategoryName: widget.categoryName,
            ),
          ),
        );
        return;
      case _AddWordMethod.file:
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'vocabulary/import',
            builder: (_) => AddMultipleWordsScreen(
              categoryId: widget.categoryId,
              categoryName: widget.categoryName,
              importer: importer,
              vocabulary: useCases,
            ),
          ),
        );
        return;
      case null:
        return;
    }
  }

  void _openWordEditor(
    BuildContext context,
    VocabularyUseCases useCases, {
    VocabularyWord? word,
  }) {
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: word == null ? 'vocabulary/add' : 'vocabulary/edit',
        builder: (_) => AddWordScreen(
          categoryId: widget.categoryId,
          vocabulary: useCases,
          word: word,
        ),
      ),
    );
  }

  Future<void> _deleteWord(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyWord word,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบคำศัพท์'),
        content: Text('ลบ “${word.spelling}” หรือไม่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await useCases.deleteWord(word.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบคำศัพท์ไม่สำเร็จ')));
      }
    }
  }
}
