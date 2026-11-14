import 'dart:async';

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

typedef _CategoryContext = ({
  AppDependencies? dependencies,
  VocabularyUseCases vocabulary,
  String id,
  String name,
});

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
  bool _savedOnly = false;
  bool _managingBookmark = false;
  AppDependencies? _dependencies;
  bool _dependenciesCaptured = false;
  bool _invalidated = false;
  String? _routeOwnerId;
  StreamSubscription<String?>? _ownerSubscription;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _query = normalizeVocabularyText(widget.initialQuery);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!_dependenciesCaptured) {
      _dependencies = dependencies;
      _dependenciesCaptured = true;
      _watchRouteOwner(dependencies);
    } else if (!identical(_dependencies, dependencies)) {
      _invalidated = true;
    }
  }

  @override
  void didUpdateWidget(covariant VocabListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _dependencies = AppDependenciesScope.maybeOf(context);
      _dependenciesCaptured = true;
      _invalidated = false;
      _watchRouteOwner(_dependencies);
      _addStarted = false;
      _savedOnly = false;
      _searchController.text = widget.initialQuery;
      _query = normalizeVocabularyText(widget.initialQuery);
    } else if (!identical(oldWidget.vocabulary, widget.vocabulary)) {
      _invalidated = true;
    }
  }

  void _watchRouteOwner(AppDependencies? dependencies) {
    unawaited(_ownerSubscription?.cancel());
    _routeOwnerId = null;
    _ownerSubscription = dependencies?.watchActiveOwnerId()?.listen(
      (active) {
        if (!mounted || !identical(dependencies, _dependencies)) return;
        if (_routeOwnerId == null && active != null) {
          _routeOwnerId = active;
        } else if (_routeOwnerId != null && _routeOwnerId != active) {
          setState(() => _invalidated = true);
        }
      },
      onError: (Object _) {
        if (mounted && identical(dependencies, _dependencies)) {
          setState(() => _invalidated = true);
        }
      },
    );
  }

  _CategoryContext? get _currentCategory {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final vocabulary = dependencies == null
        ? widget.vocabulary
        : dependencies.vocabulary;
    if (_invalidated ||
        !_dependenciesCaptured ||
        !identical(_dependencies, dependencies) ||
        vocabulary == null ||
        (dependencies != null &&
            widget.vocabulary != null &&
            !identical(widget.vocabulary, vocabulary))) {
      return null;
    }
    return (
      dependencies: dependencies,
      vocabulary: vocabulary,
      id: widget.categoryId,
      name: widget.categoryName,
    );
  }

  bool _isCurrent(_CategoryContext category) {
    if (!mounted) return false;
    final current = _currentCategory;
    return current != null &&
        identical(current.dependencies, category.dependencies) &&
        identical(current.vocabulary, category.vocabulary) &&
        current.id == category.id &&
        current.name == category.name;
  }

  Future<String?> _currentOwner(
    _CategoryContext category, {
    String? expectedOwnerId,
  }) async {
    if (!_isCurrent(category)) return null;
    try {
      final owner = await category.vocabulary.owners.getOrCreateActiveOwner();
      if (!_isCurrent(category)) return null;
      if (expectedOwnerId == null || owner.id == expectedOwnerId) {
        return owner.id;
      }
    } catch (_) {
      if (!_isCurrent(category)) return null;
    }
    if (mounted) setState(() => _invalidated = true);
    return null;
  }

  Widget _unavailableCategory(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ชุดคำนี้ไม่พร้อมใช้งาน กรุณากลับไปเลือกชุดใหม่'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('กลับไปเลือกชุดคำ'),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    unawaited(_ownerSubscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final category = _currentCategory;
    final useCases = category?.vocabulary;
    final importer = dependencies == null
        ? widget.importer
        : dependencies.vocabularyImporter;
    final progress = category == null ? null : dependencies?.progress;
    final learning = dependencies?.learning;
    final sourcePicker = dependencies?.sourcePracticeFilePicker;
    final features =
        dependencies?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
    if (!identical(useCases, _vocabulary) ||
        _categoryId != category?.id ||
        !identical(_progress, progress)) {
      _vocabulary = useCases;
      _categoryId = category?.id;
      _words = useCases?.watchWords(category!.id);
      _progress = progress;
      _latest = category == null
          ? null
          : _progress?.loadLatestSessionForCategory(category.id);
      _latest?.ignore();
    }
    if (widget.startAdding && !_addStarted && category != null) {
      _addStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrent(category)) {
          _showAddWordOptions(context, category, importer, features);
        }
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
        title: M3Theme.appBarTitle(context, category?.name ?? 'ชุดคำศัพท์'),
      ),
      body: AdaptiveContentPane(
        child: category == null || useCases == null
            ? _unavailableCategory(context)
            : StreamBuilder<List<VocabularyWord>>(
                key: ValueKey((useCases, widget.categoryId)),
                stream: _words,
                builder: (context, snapshot) {
                  final allWords = snapshot.data ?? const <VocabularyWord>[];
                  final words = allWords
                      .where(
                        (word) =>
                            (!_savedOnly || word.isBookmarked) &&
                            (word.normalizedSpelling.contains(_query) ||
                                word.normalizedMeaning.contains(_query)),
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
                              if (snapshot.hasData &&
                                  (_savedOnly || allWords.isNotEmpty)) ...[
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('คำทั้งหมด'),
                                      selected: !_savedOnly,
                                      onSelected: (_) =>
                                          setState(() => _savedOnly = false),
                                    ),
                                    ChoiceChip(
                                      label: const Text('คำที่เก็บไว้'),
                                      selected: _savedOnly,
                                      onSelected: (_) =>
                                          setState(() => _savedOnly = true),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (canPractice) ...[
                                FilledButton.icon(
                                  onPressed:
                                      snapshot.hasError || allWords.isEmpty
                                      ? null
                                      : () async {
                                          if (await _currentOwner(
                                                category,
                                                expectedOwnerId:
                                                    allWords.first.ownerId,
                                              ) ==
                                              null) {
                                            return;
                                          }
                                          if (!context.mounted) return;
                                          await AppNavigator.pushPage<void>(
                                            context,
                                            AppPage<void>(
                                              name: 'learning/category-quiz',
                                              builder: (_) => QuizScreen(
                                                categoryId: category.id,
                                                categoryName: category.name,
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
                                  category,
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
                                      onPressed: () async {
                                        if (await _currentOwner(
                                              category,
                                              expectedOwnerId: allWords.isEmpty
                                                  ? null
                                                  : allWords.first.ownerId,
                                            ) ==
                                            null) {
                                          return;
                                        }
                                        if (!context.mounted) return;
                                        await AppNavigator.pushPage<void>(
                                          context,
                                          AppPage<void>(
                                            name: 'vocabulary/source-practice',
                                            builder: (_) =>
                                                SourcePracticeScreen(
                                                  categoryId: category.id,
                                                  categoryName: category.name,
                                                  vocabulary: useCases,
                                                  learning: learning,
                                                  filePicker: sourcePicker,
                                                  associativeLearning:
                                                      dependencies
                                                          ?.associativeLearning,
                                                ),
                                          ),
                                        );
                                      },
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
                              _savedOnly &&
                                      !allWords.any((word) => word.isBookmarked)
                                  ? 'ยังไม่มีคำที่เก็บไว้'
                                  : allWords.isEmpty
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
                                  category,
                                  word: word,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'จัดการคำนี้ ${word.spelling}',
                                      icon: Icon(
                                        word.isBookmarked
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                      ),
                                      onPressed: _managingBookmark
                                          ? null
                                          : () =>
                                                _manageBookmark(category, word),
                                    ),
                                    IconButton(
                                      tooltip: 'ลบคำศัพท์ ${word.spelling}',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _deleteWord(context, category, word),
                                    ),
                                  ],
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
    if (mounted && _currentCategory != null) {
      setState(() {
        _latest = _progress?.loadLatestSessionForCategory(widget.categoryId);
        _latest?.ignore();
      });
    }
  }

  Future<void> _openLatestResult() async {
    final progress = _progress;
    final category = _currentCategory;
    if (progress == null || category == null || _openingLatest) return;
    final categoryId = category.id;
    setState(() => _openingLatest = true);
    try {
      final entry = await progress.loadLatestSessionForCategory(categoryId);
      if (!mounted) return;
      if (!_isCurrent(category) ||
          !identical(
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
            expectedOwnerId: entry.ownerId,
            categoryName: entry.categoryName ?? category.name,
            mistakes: entry.mistakes,
            returnLabel: 'กลับไปที่ชุดคำ',
            showOriginalHistory: true,
            originalAnswers: entry.originalAnswers,
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
    _CategoryContext category,
    ImportVocabulary? importer,
    FieldFeatureRegistry features,
  ) async {
    final ownerId = await _currentOwner(category);
    if (ownerId == null || !context.mounted) return;
    var chosen = false;
    final method = await showModalBottomSheet<_AddWordMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        AppDependenciesScope.maybeOf(sheetContext);
        void choose(_AddWordMethod method) {
          if (!sheetContext.mounted || chosen) return;
          chosen = true;
          Navigator.pop(sheetContext, _isCurrent(category) ? method : null);
        }

        if (!_isCurrent(category)) {
          return SafeArea(child: _unavailableCategory(sheetContext));
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'เพิ่มคำใน ${category.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('พิมพ์คำศัพท์'),
                  onTap: () => choose(_AddWordMethod.manual),
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
                    onTap: () => choose(_AddWordMethod.camera),
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
                      : () => choose(_AddWordMethod.file),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || method == null) return;
    if (await _currentOwner(category, expectedOwnerId: ownerId) == null ||
        !context.mounted) {
      return;
    }
    final currentImporter = category.dependencies == null
        ? widget.importer
        : category.dependencies?.vocabularyImporter;
    if (!identical(importer, currentImporter)) return;
    switch (method) {
      case _AddWordMethod.manual:
        await _openWordEditor(context, category, expectedOwnerId: ownerId);
        return;
      case _AddWordMethod.camera:
        await AppNavigator.pushPage<VocabularyWord>(
          context,
          AppPage<VocabularyWord>(
            name: 'vocabulary/camera',
            builder: (_) => ObjectScannerScreen(
              targetCategoryId: category.id,
              targetCategoryName: category.name,
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
              categoryId: category.id,
              categoryName: category.name,
              importer: importer,
              vocabulary: category.vocabulary,
            ),
          ),
        );
        return;
    }
  }

  Future<void> _openWordEditor(
    BuildContext context,
    _CategoryContext category, {
    VocabularyWord? word,
    String? expectedOwnerId,
  }) async {
    if (word != null && word.categoryId != category.id) return;
    final ownerId = await _currentOwner(
      category,
      expectedOwnerId: expectedOwnerId ?? word?.ownerId,
    );
    if (ownerId == null || !context.mounted) return;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: word == null ? 'vocabulary/add' : 'vocabulary/edit',
        builder: (_) => AddWordScreen(
          categoryId: category.id,
          categoryName: category.name,
          vocabulary: category.vocabulary,
          expectedOwnerId: ownerId,
          word: word,
        ),
      ),
    );
  }

  Future<void> _manageBookmark(
    _CategoryContext category,
    VocabularyWord word,
  ) async {
    if (_managingBookmark ||
        !_isCurrent(category) ||
        word.categoryId != category.id) {
      return;
    }
    setState(() => _managingBookmark = true);
    final save = !word.isBookmarked;
    try {
      final owner = await _currentOwner(
        category,
        expectedOwnerId: word.ownerId,
      );
      if (owner == null || !mounted || !_isCurrent(category)) return;
      final activeOwners = category.dependencies?.watchActiveOwnerId()?.map(
        (id) => id == owner,
      );
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => StreamBuilder<bool>(
          stream: activeOwners,
          initialData: activeOwners == null,
          builder: (sheetContext, snapshot) {
            final sameScope = identical(
              AppDependenciesScope.maybeOf(sheetContext),
              category.dependencies,
            );
            if (!sameScope || !_isCurrent(category) || snapshot.data != true) {
              return const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('รายการเก็บคำยังไม่พร้อมใช้งาน'),
                ),
              );
            }
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      word.spelling,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    Text(word.meaning),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (!sheetContext.mounted ||
                            await _currentOwner(
                                  category,
                                  expectedOwnerId: owner,
                                ) ==
                                null ||
                            !sheetContext.mounted ||
                            ModalRoute.of(sheetContext)?.isCurrent != true) {
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                      },
                      child: Text(
                        save
                            ? 'เก็บไว้อ่านอีกครั้ง'
                            : 'นำออกจากรายการคำที่เก็บไว้',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (confirmed != true ||
          await _currentOwner(category, expectedOwnerId: owner) == null) {
        return;
      }
      await category.vocabulary.setBookmarked(
        expectedOwnerId: owner,
        wordId: word.id,
        bookmarked: save,
      );
      if (save && _isCurrent(category)) {
        setState(() {
          _searchController.clear();
          _query = '';
          _savedOnly = true;
        });
      }
    } catch (_) {
      if (await _currentOwner(category, expectedOwnerId: word.ownerId) !=
              null &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนรายการคำที่เก็บไว้ไม่สำเร็จ')),
        );
      }
    } finally {
      if (mounted) setState(() => _managingBookmark = false);
    }
  }

  Future<void> _deleteWord(
    BuildContext context,
    _CategoryContext category,
    VocabularyWord word,
  ) async {
    if (word.categoryId != category.id ||
        await _currentOwner(category, expectedOwnerId: word.ownerId) == null ||
        !context.mounted) {
      return;
    }
    var chosen = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppDependenciesScope.maybeOf(dialogContext);
        void choose(bool accepted) {
          if (!dialogContext.mounted || chosen) return;
          chosen = true;
          Navigator.pop(dialogContext, accepted && _isCurrent(category));
        }

        if (!_isCurrent(category)) {
          return AlertDialog(
            title: const Text('ชุดคำนี้ไม่พร้อมใช้งาน'),
            actions: [
              TextButton(
                onPressed: () => choose(false),
                child: const Text('กลับ'),
              ),
            ],
          );
        }
        return AlertDialog(
          title: const Text('ลบคำศัพท์'),
          content: Text('ลบ “${word.spelling}” หรือไม่'),
          actions: [
            TextButton(
              onPressed: () => choose(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => choose(true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );
    if (accepted != true) return;
    try {
      if (await _currentOwner(category, expectedOwnerId: word.ownerId) ==
          null) {
        return;
      }
      await category.vocabulary.deleteWord(word.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบคำศัพท์ไม่สำเร็จ')));
      }
    }
  }
}
