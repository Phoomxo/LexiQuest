import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/saved_words_use_cases.dart';
import '../features/vocabulary/application/word_report_use_cases.dart';
import '../features/vocabulary/domain/word_report.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import '../widgets/word_report_sheet.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import 'saved_words_screen.dart';
import 'source_practice_screen.dart';
import 'word_reports_screen.dart';

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.vocabulary,
    this.importer,
    this.savedWords,
    this.wordReports,
    this.ownerChanges,
    this.languageCode = 'th',
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? importer;
  final SavedWordsUseCases? savedWords;
  final WordReportUseCases? wordReports;
  final Stream<String?>? ownerChanges;
  final String languageCode;

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _retryEpoch = 0;
  int _bindingGeneration = -1;
  int _reportGeneration = -1;
  int _lifecycleGeneration = 0;
  AppDependencies? _dependencies;
  VocabularyUseCases? _vocabulary;
  SavedWordsUseCases? _savedWords;
  WordReportUseCases? _wordReports;
  WordReportOwnerScope? _reportScope;
  Stream<String?>? _owners;
  Stream<List<VocabularyWord>>? _words;
  SavedWordsViewBinding? _binding;
  ModalRoute<dynamic>? _route;
  bool _paneVisible = false;
  bool _foreground = false;
  bool _bound = false;
  bool _invalidated = false;
  bool _confirmingDelete = false;
  bool _dialogInvalidated = false;
  bool _ownedReportOverlay = false;
  bool _reportOverlayInvalidated = false;

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _visible =>
      mounted &&
      !_invalidated &&
      _foreground &&
      Visibility.of(context) &&
      (_route?.isCurrent == true && _paneVisible ||
          _confirmingDelete && !_dialogInvalidated ||
          _ownedReportOverlay && !_reportOverlayInvalidated);
  bool get _mayAct =>
      !_invalidated &&
      (_savedWords == null || _binding?.ready == true) &&
      (_wordReports == null || _reportScope?.current == true);

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _paneVisible = ModalRoute.isCurrentOf(context) == true;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    final savedWords = widget.savedWords ?? dependencies?.savedWords;
    final wordReports = widget.wordReports ?? dependencies?.wordReports;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _vocabulary = vocabulary;
      _savedWords = savedWords;
      _wordReports = wordReports;
      _owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (savedWords != null && _owners != null) {
        _binding = SavedWordsViewBinding(
          useCases: savedWords,
          ownerChanges: _owners!,
          visible: () => _visible,
        )..addListener(_changed);
      }
      if (wordReports != null && _owners != null) {
        _reportScope = WordReportOwnerScope(
          ownerChanges: _owners!,
          visible: () => _visible,
        )..addListener(_changed);
      }
    } else if (!identical(_dependencies, dependencies) ||
        !identical(_vocabulary, vocabulary) ||
        !identical(_savedWords, savedWords) ||
        !identical(_wordReports, wordReports)) {
      _invalidateBinding();
    }
    _binding?.syncVisibility();
    _reportScope?.synchronize();
  }

  @override
  void didUpdateWidget(covariant VocabListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        !identical(oldWidget.vocabulary, widget.vocabulary) ||
        !identical(oldWidget.savedWords, widget.savedWords) ||
        !identical(oldWidget.wordReports, widget.wordReports) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidateBinding();
    }
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final generation = _binding?.generation ?? -1;
    final reportGeneration = _reportScope?.generation ?? -1;
    if (generation != _bindingGeneration ||
        reportGeneration != _reportGeneration) {
      _bindingGeneration = generation;
      _reportGeneration = reportGeneration;
      _words = null;
      _retryEpoch++;
    }
    setState(() {});
  }

  void _invalidateBinding() {
    _invalidated = true;
    _words = null;
    final binding = _binding;
    _binding = null;
    binding?.removeListener(_changed);
    unawaited(binding?.close());
    final reportScope = _reportScope;
    _reportScope = null;
    reportScope?.removeListener(_changed);
    unawaited(reportScope?.close());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _lifecycleGeneration++;
    }
    _binding?.syncVisibility();
    _reportScope?.synchronize();
    _changed();
  }

  @override
  void dispose() {
    _invalidateBinding();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useCases = _vocabulary;
    final importer = widget.importer ?? _dependencies?.vocabularyImporter;
    final learning = _dependencies?.learning;
    final sourcePicker = _dependencies?.sourcePracticeFilePicker;
    final canPracticeSource =
        useCases != null && learning != null && sourcePicker != null;
    final binding = _binding;
    final epoch = binding?.generation;
    final reportScope = _reportScope;
    final reportEpoch = reportScope?.generation;
    final guardedUnavailable =
        _invalidated ||
        _savedWords != null &&
            (binding == null ||
                binding.blocked ||
                !binding.current && binding.ownerObserved) ||
        _wordReports != null &&
            (reportScope == null ||
                reportScope.blocked ||
                !reportScope.current && reportScope.observed);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          guardedUnavailable
              ? _text('คำศัพท์', 'Vocabulary')
              : widget.categoryName,
        ),
      ),
      body: AdaptiveContentPane(
        child: useCases == null || guardedUnavailable
            ? Center(
                child: Text(
                  _text(
                    'รายการนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่',
                    'This list is unavailable. Go back and open it again.',
                  ),
                ),
              )
            : _savedWords != null && binding?.readFailed == true
            ? Center(
                child: OutlinedButton(
                  onPressed: binding!.retryRead,
                  child: Text(
                    _text(
                      'อ่านคำศัพท์ไม่สำเร็จ ลองใหม่',
                      'Could not load words. Retry',
                    ),
                  ),
                ),
              )
            : _savedWords != null && binding?.ready != true ||
                  _wordReports != null && reportScope?.current != true
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SearchBar(
                          controller: _searchController,
                          hintText: _text('ค้นหาคำศัพท์', 'Search words'),
                          leading: const Icon(Icons.search),
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                        ),
                        if (canPracticeSource ||
                            importer != null ||
                            binding != null ||
                            reportScope != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (reportScope != null)
                                OutlinedButton.icon(
                                  key: const ValueKey('word-reports-history'),
                                  onPressed: () => _openReportHistory(
                                    reportScope,
                                    reportEpoch!,
                                  ),
                                  icon: const Icon(Icons.flag_outlined),
                                  label: Text(
                                    _text('รายงานในเครื่อง', 'Local reports'),
                                  ),
                                ),
                              if (binding != null)
                                OutlinedButton.icon(
                                  key: const ValueKey('saved-words'),
                                  onPressed: () => _openSaved(binding, epoch!),
                                  icon: const Icon(Icons.bookmarks_outlined),
                                  label: Text(
                                    _text('คำศัพท์ที่บันทึก', 'Saved words'),
                                  ),
                                ),
                              if (canPracticeSource)
                                OutlinedButton.icon(
                                  key: const ValueKey('source-practice'),
                                  onPressed: () {
                                    if (!_mayAct ||
                                        binding != null &&
                                            !binding.isCurrent(epoch!)) {
                                      return;
                                    }
                                    AppNavigator.pushPage<void>(
                                      context,
                                      AppPage<void>(
                                        name: 'vocabulary/source-practice',
                                        builder: (_) => SourcePracticeScreen(
                                          categoryId: widget.categoryId,
                                          categoryName: widget.categoryName,
                                          vocabulary: useCases,
                                          learning: learning,
                                          filePicker: sourcePicker,
                                          associativeLearning: _dependencies
                                              ?.associativeLearning,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.menu_book_outlined),
                                  label: Text(
                                    _text('ฝึกจากไฟล์', 'Practice from file'),
                                  ),
                                ),
                              if (importer != null)
                                OutlinedButton.icon(
                                  key: const ValueKey('import-words'),
                                  onPressed: () {
                                    if (!_mayAct ||
                                        binding != null &&
                                            !binding.isCurrent(epoch!)) {
                                      return;
                                    }
                                    AppNavigator.pushPage<void>(
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
                                  },
                                  icon: const Icon(Icons.file_upload_outlined),
                                  label: Text(
                                    _text('นำเข้าคำศัพท์', 'Import words'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<VocabularyWord>>(
                      key: ValueKey<int>(_retryEpoch),
                      stream: _words ??= useCases.watchWords(widget.categoryId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _text(
                                      'อ่านคำศัพท์ไม่สำเร็จ',
                                      'Could not load words.',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    _words = null;
                                    _retryEpoch++;
                                  }),
                                  child: Text(_text('ลองใหม่', 'Retry')),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: _text(
                                'กำลังโหลดคำศัพท์',
                                'Loading words',
                              ),
                            ),
                          );
                        }
                        final words = snapshot.data!
                            .where(
                              (word) =>
                                  (binding == null ||
                                      word.ownerId == binding.ownerId) &&
                                  (reportScope == null ||
                                      word.ownerId == reportScope.ownerId) &&
                                  (_query.isEmpty ||
                                      word.normalizedSpelling.contains(
                                        _query,
                                      ) ||
                                      word.normalizedMeaning.contains(_query)),
                            )
                            .toList(growable: false);
                        if (words.isEmpty) {
                          return Center(
                            child: Text(
                              _text(
                                'ยังไม่มีคำศัพท์ในหมวดนี้',
                                'No words in this category yet.',
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: words.length,
                          itemBuilder: (context, index) {
                            final word = words[index];
                            final pending = binding?.pendingFor(word.id);
                            final conflict =
                                binding?.conflicted(word.id) == true;
                            final rowEnabled = pending == null && !conflict;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  title: Text(word.spelling),
                                  subtitle: Text(
                                    '${word.meaning} · ${word.partOfSpeech}',
                                  ),
                                  onTap: rowEnabled
                                      ? () => _openWordEditor(
                                          context,
                                          useCases,
                                          word: word,
                                        )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (binding != null)
                                        IconButton(
                                          key: ValueKey(
                                            'vocab-save:${word.id}',
                                          ),
                                          tooltip:
                                              binding
                                                      .stateFor(word.id)
                                                      ?.isSaved ==
                                                  true
                                              ? _text(
                                                  'นำออกจากที่บันทึก',
                                                  'Remove saved word',
                                                )
                                              : _text(
                                                  'บันทึกคำศัพท์',
                                                  'Save word',
                                                ),
                                          icon: Icon(
                                            binding
                                                        .stateFor(word.id)
                                                        ?.isSaved ==
                                                    true
                                                ? Icons.bookmark
                                                : Icons.bookmark_outline,
                                          ),
                                          onPressed: rowEnabled
                                              ? () => binding.setSaved(
                                                  word.id,
                                                  binding
                                                          .stateFor(word.id)
                                                          ?.isSaved !=
                                                      true,
                                                  epoch!,
                                                )
                                              : null,
                                        ),
                                      PopupMenuButton<String>(
                                        key: ValueKey(
                                          'vocab-word-menu:${word.id}',
                                        ),
                                        tooltip: _text(
                                          'ตัวเลือกคำศัพท์ ${word.spelling}',
                                          'Word options ${word.spelling}',
                                        ),
                                        enabled: rowEnabled && _mayAct,
                                        onOpened: () {
                                          _ownedReportOverlay = true;
                                          _reportOverlayInvalidated = false;
                                        },
                                        onCanceled: _endOwnedReportOverlay,
                                        onSelected: (action) {
                                          final overlayValid =
                                              !_reportOverlayInvalidated;
                                          _endOwnedReportOverlay();
                                          if (!overlayValid ||
                                              !_mayAct ||
                                              binding != null &&
                                                  !binding.isCurrent(epoch!) ||
                                              reportScope != null &&
                                                  !reportScope.isCurrent(
                                                    reportEpoch!,
                                                  )) {
                                            return;
                                          }
                                          if (action == 'report') {
                                            _openReport(word);
                                          } else if (action == 'delete') {
                                            _deleteWord(
                                              context,
                                              useCases,
                                              word,
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          if (_wordReports != null)
                                            PopupMenuItem(
                                              value: 'report',
                                              key: ValueKey(
                                                'vocab-report:${word.id}',
                                              ),
                                              child: _ownedOverlayChild(
                                                Text(
                                                  _text(
                                                    'รายงานคำศัพท์',
                                                    'Report word',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            key: ValueKey(
                                              'vocab-delete:${word.id}',
                                            ),
                                            child: _ownedOverlayChild(
                                              Text(
                                                _text(
                                                  'ลบคำศัพท์',
                                                  'Delete word',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (pending != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: pending.busy
                                        ? const LinearProgressIndicator()
                                        : OutlinedButton(
                                            key: ValueKey(
                                              'vocab-save-retry:${word.id}',
                                            ),
                                            onPressed: () =>
                                                binding!.retry(word.id, epoch!),
                                            child: Text(
                                              _text(
                                                'ยังยืนยันไม่ได้ ลองคำสั่งเดิมอีกครั้ง',
                                                'Unconfirmed. Retry the same change',
                                              ),
                                            ),
                                          ),
                                  ),
                                if (conflict)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: OutlinedButton(
                                      key: ValueKey(
                                        'vocab-save-refresh-conflict:${word.id}',
                                      ),
                                      onPressed: binding!.retryRead,
                                      child: Text(
                                        _text(
                                          'สถานะเปลี่ยนแล้ว โหลดสถานะล่าสุด',
                                          'Saved state changed. Refresh first',
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: useCases == null || !_mayAct
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('add-word'),
              heroTag: 'words-add',
              onPressed: () => _openWordEditor(context, useCases),
              icon: const Icon(Icons.add),
              label: Text(_text('เพิ่มคำศัพท์', 'Add word')),
            ),
    );
  }

  void _openSaved(SavedWordsViewBinding binding, int epoch) {
    if (!binding.isCurrent(epoch) || !binding.ready || !_mayAct) {
      return;
    }
    final owner = binding.ownerId!;
    final ownerGeneration = binding.ownerGeneration;
    final lifecycleGeneration = _lifecycleGeneration;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/saved',
        builder: (_) {
          if (!mounted ||
              _invalidated ||
              !identical(binding, _binding) ||
              binding.ownerGeneration != ownerGeneration ||
              !binding.ownerKnown ||
              binding.blocked ||
              binding.ownerId != owner ||
              _lifecycleGeneration != lifecycleGeneration ||
              !_foreground) {
            return const Scaffold(
              body: Center(
                child: Text('รายการไม่พร้อมใช้งาน / List unavailable'),
              ),
            );
          }
          return SavedWordsScreen(
            expectedOwnerId: owner,
            savedWords: _savedWords,
            learning: _dependencies?.learning,
            ownerChanges: _owners,
            languageCode: widget.languageCode,
          );
        },
      ),
    );
  }

  Widget _ownedOverlayChild(Widget child) => Builder(
    builder: (overlayContext) {
      if (ModalRoute.of(overlayContext)?.isActive == true &&
          ModalRoute.isCurrentOf(overlayContext) != true) {
        _reportOverlayInvalidated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _binding?.syncVisibility();
            _reportScope?.synchronize();
            _changed();
          }
        });
      }
      return _reportOverlayInvalidated ? const SizedBox.shrink() : child;
    },
  );

  void _endOwnedReportOverlay() {
    _ownedReportOverlay = false;
    if (!mounted) {
      return;
    }
    _paneVisible = _route?.isCurrent == true && Visibility.of(context);
    _binding?.syncVisibility();
    _reportScope?.synchronize();
  }

  Future<void> _openReport(VocabularyWord word) async {
    final scope = _reportScope;
    final reports = _wordReports;
    if (!_mayAct ||
        scope == null ||
        reports == null ||
        !scope.current ||
        word.ownerId != scope.ownerId) {
      return;
    }
    final epoch = scope.generation;
    final owner = scope.ownerId!;
    final dependencies = _dependencies;
    final WordReportTarget target;
    try {
      target = WordReportTarget.fromWord(word);
    } on Object {
      return;
    }
    _ownedReportOverlay = true;
    _reportOverlayInvalidated = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ownedOverlayChild(
          !mounted ||
                  _invalidated ||
                  !identical(dependencies, _dependencies) ||
                  !identical(reports, _wordReports) ||
                  !scope.isCurrent(epoch)
              ? const SizedBox.shrink()
              : WordReportSheet(
                  expectedOwnerId: owner,
                  target: target,
                  wordReports: reports,
                  ownerChanges: _owners,
                  languageCode: widget.languageCode,
                ),
        ),
      );
    } finally {
      _endOwnedReportOverlay();
    }
  }

  void _openReportHistory(WordReportOwnerScope scope, int epoch) {
    if (!_mayAct || !scope.isCurrent(epoch)) {
      return;
    }
    final owner = scope.ownerId!;
    final ownerGeneration = scope.ownerGeneration;
    final lifecycleGeneration = _lifecycleGeneration;
    final reports = _wordReports;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/local-reports',
        builder: (_) {
          if (!mounted ||
              _invalidated ||
              !identical(scope, _reportScope) ||
              !scope.known ||
              scope.blocked ||
              scope.ownerId != owner ||
              scope.ownerGeneration != ownerGeneration ||
              !_foreground ||
              lifecycleGeneration != _lifecycleGeneration ||
              !identical(reports, _wordReports)) {
            return const Scaffold(
              body: Center(
                child: Text('รายการไม่พร้อมใช้งาน / List unavailable'),
              ),
            );
          }
          return WordReportsScreen(
            expectedOwnerId: owner,
            wordReports: reports,
            ownerChanges: _owners,
            languageCode: widget.languageCode,
          );
        },
      ),
    );
  }

  void _openWordEditor(
    BuildContext context,
    VocabularyUseCases useCases, {
    VocabularyWord? word,
  }) {
    if (!_mayAct ||
        word != null && _binding != null && word.ownerId != _binding!.ownerId) {
      return;
    }
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
    final binding = _binding;
    final reportScope = _reportScope;
    final reportEpoch = reportScope?.generation;
    if (!_mayAct ||
        binding != null && word.ownerId != binding.ownerId ||
        reportScope != null && word.ownerId != reportScope.ownerId) {
      return;
    }
    final epoch = binding?.generation;
    final lifecycleGeneration = _lifecycleGeneration;
    _confirmingDelete = true;
    _dialogInvalidated = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        if (ModalRoute.of(dialogContext)?.isActive == true &&
            ModalRoute.isCurrentOf(dialogContext) != true) {
          _dialogInvalidated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _binding?.syncVisibility();
              _reportScope?.synchronize();
              _changed();
            }
          });
          return const SizedBox.shrink();
        }
        return AnimatedBuilder(
          animation: binding == null && reportScope == null
              ? _searchController
              : Listenable.merge([binding, reportScope]),
          builder: (_, _) {
            if (binding != null && !binding.isCurrent(epoch!) ||
                reportScope != null && !reportScope.isCurrent(reportEpoch!)) {
              return const SizedBox.shrink();
            }
            return AlertDialog(
              title: Text(_text('ลบคำศัพท์', 'Delete word')),
              content: Text(
                _text(
                  'ลบ “${word.spelling}” หรือไม่',
                  'Delete “${word.spelling}”?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_text('ยกเลิก', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(_text('ลบ', 'Delete')),
                ),
              ],
            );
          },
        );
      },
    );
    _confirmingDelete = false;
    if (!mounted || !context.mounted) {
      return;
    }
    _paneVisible = _route?.isCurrent == true && Visibility.of(context);
    _binding?.syncVisibility();
    _reportScope?.synchronize();
    if (accepted != true ||
        !mounted ||
        _dialogInvalidated ||
        _lifecycleGeneration != lifecycleGeneration ||
        !_mayAct ||
        reportScope != null &&
            (!identical(reportScope, _reportScope) ||
                !reportScope.isCurrent(reportEpoch!)) ||
        binding != null &&
            (!identical(binding, _binding) || !binding.isCurrent(epoch!))) {
      return;
    }
    try {
      await useCases.deleteWord(word.id);
    } on Object {
      if (context.mounted &&
          _mayAct &&
          _lifecycleGeneration == lifecycleGeneration &&
          (reportScope == null || reportScope.isCurrent(reportEpoch!)) &&
          (binding == null || binding.isCurrent(epoch!))) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('ลบคำศัพท์ไม่สำเร็จ', 'Could not delete word.'),
            ),
          ),
        );
      }
    }
  }
}
