import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/saved_words_use_cases.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import 'saved_words_screen.dart';
import 'source_practice_screen.dart';

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.vocabulary,
    this.importer,
    this.savedWords,
    this.ownerChanges,
    this.languageCode = 'th',
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? importer;
  final SavedWordsUseCases? savedWords;
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
  int _lifecycleGeneration = 0;
  AppDependencies? _dependencies;
  VocabularyUseCases? _vocabulary;
  SavedWordsUseCases? _savedWords;
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

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _visible =>
      mounted &&
      !_invalidated &&
      _foreground &&
      Visibility.of(context) &&
      (_route?.isCurrent == true && _paneVisible ||
          _confirmingDelete && !_dialogInvalidated);
  bool get _mayAct =>
      !_invalidated && (_savedWords == null || _binding?.ready == true);

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
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _vocabulary = vocabulary;
      _savedWords = savedWords;
      _owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (savedWords != null && _owners != null) {
        _binding = SavedWordsViewBinding(
          useCases: savedWords,
          ownerChanges: _owners!,
          visible: () => _visible,
        )..addListener(_changed);
      }
    } else if (!identical(_dependencies, dependencies) ||
        !identical(_vocabulary, vocabulary) ||
        !identical(_savedWords, savedWords)) {
      _invalidateBinding();
    }
    _binding?.syncVisibility();
  }

  @override
  void didUpdateWidget(covariant VocabListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        !identical(oldWidget.vocabulary, widget.vocabulary) ||
        !identical(oldWidget.savedWords, widget.savedWords) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidateBinding();
    }
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final generation = _binding?.generation ?? -1;
    if (generation != _bindingGeneration) {
      _bindingGeneration = generation;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _lifecycleGeneration++;
    }
    _binding?.syncVisibility();
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
    final guardedUnavailable =
        _invalidated ||
        _savedWords != null &&
            (binding == null ||
                binding.blocked ||
                !binding.current && binding.ownerObserved);
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
            : _savedWords != null && binding?.ready != true
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
                            binding != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
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
                                      IconButton(
                                        key: ValueKey(
                                          'vocab-delete:${word.id}',
                                        ),
                                        tooltip: _text(
                                          'ลบคำศัพท์ ${word.spelling}',
                                          'Delete word ${word.spelling}',
                                        ),
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: rowEnabled
                                            ? () => _deleteWord(
                                                context,
                                                useCases,
                                                word,
                                              )
                                            : null,
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
    if (!_mayAct || binding != null && word.ownerId != binding.ownerId) {
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
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _binding?.syncVisibility(),
          );
          return const SizedBox.shrink();
        }
        return AnimatedBuilder(
          animation: binding ?? _searchController,
          builder: (_, _) {
            if (binding != null && !binding.isCurrent(epoch!)) {
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
    if (accepted != true ||
        !mounted ||
        _dialogInvalidated ||
        _lifecycleGeneration != lifecycleGeneration ||
        !_mayAct ||
        binding != null &&
            (!identical(binding, _binding) || !binding.isCurrent(epoch!))) {
      return;
    }
    try {
      await useCases.deleteWord(word.id);
    } on Object {
      if (context.mounted &&
          _mayAct &&
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
