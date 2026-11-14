import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_models.dart' show CefrLevel;
import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';
import 'add_multiple_words_screen.dart';
import 'vocab_list_screen.dart';
import 'wordbook_import_screen.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.vocabulary, this.onOpenMenu});

  final VocabularyUseCases? vocabulary;
  final VoidCallback? onOpenMenu;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _cefrLevel;
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _ownerSubscription;
  String? _ownerId;
  bool _waitingForOwner = false;
  Object _libraryContext = Object();
  VocabularyUseCases? _vocabulary;
  Stream<List<VocabularyCategorySummary>>? _categories;
  Stream<List<VocabularyWord>>? _matches;
  bool _choosingDestination = false;
  bool _hadScope = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    _ownerId = null;
    _vocabulary = null;
    _cefrLevel = null;
    _libraryContext = Object();
    unawaited(_ownerSubscription?.cancel());
    final ownerChanges = dependencies?.watchActiveOwnerId();
    _waitingForOwner = ownerChanges != null;
    _ownerSubscription = ownerChanges?.listen(
      (ownerId) => _changeOwner(dependencies, ownerId),
      onError: (Object _) => _changeOwner(dependencies, null),
    );
  }

  void _changeOwner(AppDependencies? dependencies, String? ownerId) {
    if (!mounted || !identical(_dependencies, dependencies)) return;
    final alreadyWatching = !_waitingForOwner;
    setState(() {
      _waitingForOwner = false;
      _ownerId = ownerId;
      _vocabulary = null;
      _cefrLevel = null;
      _libraryContext = Object();
      if (alreadyWatching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_ownerSubscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  VocabularyUseCases? _useCases(BuildContext context) {
    final scope = AppDependenciesScope.maybeOf(context);
    if (scope != null) {
      _hadScope = true;
      return scope.vocabulary;
    }
    return _hadScope ? null : widget.vocabulary;
  }

  bool _isCurrent(VocabularyUseCases useCases) =>
      mounted && identical(_useCases(context), useCases);

  Stream<List<VocabularyWord>> _searchWords(VocabularyUseCases useCases) =>
      useCases.searchWords(
        _query,
        cefrLevel: _cefrLevel,
        expectedOwnerId: _ownerId,
      );

  @override
  Widget build(BuildContext context) {
    final scopedVocabulary = _useCases(context);
    final useCases = _ownerSubscription != null && _ownerId == null
        ? null
        : scopedVocabulary;
    if (!identical(useCases, _vocabulary)) {
      _vocabulary = useCases;
      _cefrLevel = null;
      _libraryContext = Object();
      _categories = useCases?.watchLibrary(expectedOwnerId: _ownerId);
      _matches = useCases == null ? null : _searchWords(useCases);
    }
    final libraryContext = _libraryContext;
    final ownerId = _ownerId;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final addWord = useCases == null
        ? null
        : FilledButton.icon(
            key: const ValueKey('library-add-word'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 48),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            onPressed: _choosingDestination
                ? null
                : () => _chooseDestination(context, useCases),
            icon: const Icon(Icons.add),
            label: Text(_choosingDestination ? 'กำลังเปิด…' : 'เพิ่มคำ'),
          );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.rootAppBarToolbarHeight(context),
        centerTitle: false,
        titleSpacing: 24,
        title: Text(
          'คลังคำศัพท์',
          maxLines: 2,
          softWrap: true,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!largeText && addWord != null)
            Padding(padding: const EdgeInsets.only(right: 8), child: addWord),
          if (widget.onOpenMenu != null)
            IconButton(
              key: const ValueKey<String>('shell-drawer-button'),
              tooltip: 'เปิดเมนูเพิ่มเติม',
              onPressed: widget.onOpenMenu,
              icon: const Icon(Icons.menu),
            ),
        ],
      ),
      body: AdaptiveContentPane(
        child: _waitingForOwner
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังโหลดคลังคำศัพท์',
                ),
              )
            : useCases == null
            ? const _LocalDataUnavailable()
            : CustomScrollView(
                key: const PageStorageKey('vocabulary-categories'),
                slivers: [
                  if (largeText && addWord != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: addWord,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: SearchBar(
                        key: const ValueKey('category-search'),
                        controller: _searchController,
                        hintText: 'ค้นหาคำในคลัง',
                        elevation: const WidgetStatePropertyAll(0),
                        surfaceTintColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        backgroundColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.surface,
                        ),
                        constraints: const BoxConstraints(minHeight: 58),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        leading: const Icon(Icons.search),
                        onChanged: (value) {
                          if (!identical(libraryContext, _libraryContext) ||
                              !_isCurrent(useCases)) {
                            return;
                          }
                          setState(() {
                            _query = normalizeVocabularyText(value);
                            _matches = _searchWords(useCases);
                          });
                        },
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('library-level-filter'),
                            onPressed: () =>
                                _chooseLevel(context, useCases, libraryContext),
                            icon: const Icon(Icons.filter_list),
                            label: Text(
                              _cefrLevel == null
                                  ? 'เลือกระดับภาษา'
                                  : 'เลือกระดับภาษา · $_cefrLevel',
                            ),
                          ),
                          if (_cefrLevel != null)
                            TextButton(
                              onPressed: () =>
                                  _setLevel(useCases, libraryContext, null),
                              child: const Text('ล้างตัวกรอง'),
                            ),
                          if (ownerId != null)
                            OutlinedButton.icon(
                              onPressed: () => AppNavigator.pushPage<void>(
                                context,
                                AppPage<void>(
                                  name: 'vocabulary/import',
                                  builder: (importContext) =>
                                      WordbookImportScreen(
                                        expectedOwnerId: ownerId,
                                        onSaveToLibrary: () =>
                                            _chooseDestination(
                                              importContext,
                                              useCases,
                                              forImport: true,
                                              expectedOwnerId: ownerId,
                                            ),
                                        onPasteToLibrary: () =>
                                            _chooseDestination(
                                              importContext,
                                              useCases,
                                              forImport: true,
                                              pasteTable: true,
                                              expectedOwnerId: ownerId,
                                            ),
                                      ),
                                ),
                              ),
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('นำเข้าชุดคำ'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _query.isEmpty ? 'ชุดคำของฉัน' : 'ผลการค้นหา',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton.icon(
                            key: const ValueKey('add-category'),
                            onPressed: () =>
                                _showAddCategory(context, useCases),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            style: TextButton.styleFrom(
                              textStyle: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            label: const Text('เพิ่มชุด'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    sliver: StreamBuilder<List<VocabularyCategorySummary>>(
                      key: ValueKey(libraryContext),
                      stream: _categories,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return SliverFillRemaining(
                            hasScrollBody: false,
                            child: _FailureState(
                              onRetry: () {
                                if (!identical(
                                      libraryContext,
                                      _libraryContext,
                                    ) ||
                                    !_isCurrent(useCases)) {
                                  return;
                                }
                                setState(
                                  () => _categories = useCases.watchLibrary(
                                    expectedOwnerId: _ownerId,
                                  ),
                                );
                              },
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: 'กำลังโหลดหมวดหมู่',
                              ),
                            ),
                          );
                        }
                        final level = _cefrLevel;
                        if (snapshot.requireData.isEmpty && level == null) {
                          return const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'ยังไม่มีหมวดหมู่\nเพิ่มหมวดหมู่เพื่อเริ่มเก็บคำศัพท์',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        final summaries = snapshot.requireData
                            .where(
                              (entry) =>
                                  level == null ||
                                  entry.cefrLevels.contains(level),
                            )
                            .toList(growable: false);
                        final categories = summaries
                            .where(
                              (entry) => entry.category.normalizedName.contains(
                                _query,
                              ),
                            )
                            .toList(growable: false);
                        if (level != null && _query.isEmpty) {
                          return SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    'ระดับภาษา · $level · พบ ${summaries.length} ชุด',
                                  ),
                                ),
                              ),
                              if (summaries.isEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Text('ไม่พบชุดที่มีคำระดับ $level'),
                                  ),
                                )
                              else
                                _libraryList(context, useCases, categories),
                            ],
                          );
                        }
                        if (_query.isEmpty) {
                          return _libraryList(context, useCases, categories);
                        }
                        return StreamBuilder<List<VocabularyWord>>(
                          key: ValueKey((useCases, _query, level)),
                          stream: _matches,
                          builder: (context, matches) {
                            if (matches.hasError) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: _FailureState(
                                  onRetry: () {
                                    if (!identical(
                                          libraryContext,
                                          _libraryContext,
                                        ) ||
                                        !_isCurrent(useCases)) {
                                      return;
                                    }
                                    setState(
                                      () => _matches = _searchWords(useCases),
                                    );
                                  },
                                ),
                              );
                            }
                            if (!matches.hasData) {
                              return const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    semanticsLabel: 'กำลังค้นหาคำในคลัง',
                                  ),
                                ),
                              );
                            }
                            final byId = {
                              for (final summary in summaries)
                                summary.category.id: summary.category,
                            };
                            final words = matches.requireData
                                .where(
                                  (word) => byId.containsKey(word.categoryId),
                                )
                                .toList(growable: false);
                            if (words.isEmpty && categories.isEmpty) {
                              return const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text('ไม่พบคำหรือชุดที่ค้นหา'),
                                ),
                              );
                            }
                            return SliverList.builder(
                              itemCount:
                                  categories.length +
                                  words.length +
                                  (words.length == 50 ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index < categories.length) {
                                  return _categoryTile(
                                    context,
                                    useCases,
                                    categories[index],
                                  );
                                }
                                final wordIndex = index - categories.length;
                                if (wordIndex == words.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text(
                                      'แสดง 50 คำแรก พิมพ์เพิ่มเพื่อค้นหาให้แคบลง',
                                    ),
                                  );
                                }
                                final word = words[wordIndex];
                                return ListTile(
                                  title: Text(word.spelling),
                                  subtitle: Text(byId[word.categoryId]!.name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openCategory(
                                    context,
                                    useCases,
                                    byId[word.categoryId]!,
                                    initialQuery: word.spelling,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _chooseLevel(
    BuildContext context,
    VocabularyUseCases useCases,
    Object libraryContext,
  ) async {
    if (!identical(libraryContext, _libraryContext) || !_isCurrent(useCases)) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('ระดับภาษา')),
            for (final level in CefrLevel.values)
              if (level != CefrLevel.unknown)
                ListTile(
                  title: Text(level.name.toUpperCase()),
                  selected: _cefrLevel == level.name.toUpperCase(),
                  onTap: () =>
                      Navigator.pop(sheetContext, level.name.toUpperCase()),
                ),
          ],
        ),
      ),
    );
    if (selected != null) _setLevel(useCases, libraryContext, selected);
  }

  void _setLevel(
    VocabularyUseCases useCases,
    Object libraryContext,
    String? level,
  ) {
    if (!identical(libraryContext, _libraryContext) ||
        !_isCurrent(useCases) ||
        _cefrLevel == level) {
      return;
    }
    setState(() {
      _cefrLevel = level;
      _matches = _searchWords(useCases);
    });
  }

  Widget _libraryList(
    BuildContext context,
    VocabularyUseCases useCases,
    List<VocabularyCategorySummary> summaries,
  ) => SliverList.separated(
    itemCount: summaries.length,
    separatorBuilder: (_, _) => const Divider(),
    itemBuilder: (context, index) =>
        _categoryTile(context, useCases, summaries[index]),
  );

  Widget _categoryTile(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategorySummary summary,
  ) {
    final category = summary.category;
    return ListTile(
      minTileHeight: 98,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        category.name,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${summary.wordCount} คำ${summary.previewSpellings.isEmpty ? '' : ' · ${summary.previewSpellings.join(' · ')}'}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'ตัวเลือกชุด ${category.name}',
            onSelected: (_) => _confirmDelete(context, useCases, category),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('ลบชุดคำศัพท์')),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _openCategory(context, useCases, category),
    );
  }

  Future<void> _openCategory(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategory category, {
    bool startAdding = false,
    String initialQuery = '',
  }) async {
    if (!_isCurrent(useCases) ||
        (_ownerSubscription != null && _ownerId != category.ownerId)) {
      return;
    }
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/category',
        builder: (_) => VocabListScreen(
          categoryId: category.id,
          categoryName: category.name,
          expectedOwnerId: category.ownerId,
          vocabulary: useCases,
          startAdding: startAdding,
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  Future<void> _chooseDestination(
    BuildContext context,
    VocabularyUseCases useCases, {
    bool forImport = false,
    bool pasteTable = false,
    String? expectedOwnerId,
  }) async {
    if (_choosingDestination || !_isCurrent(useCases)) return;
    final libraryContext = _libraryContext;
    setState(() => _choosingDestination = true);
    try {
      if (expectedOwnerId != null) {
        final activeOwner = await _dependencies?.readActiveOwnerId();
        if (activeOwner != expectedOwnerId || !_isCurrent(useCases)) return;
      }
      final owner = await useCases.owners.getOrCreateActiveOwner();
      if (expectedOwnerId != null && expectedOwnerId != owner.id) return;
      final categories = await useCases
          .watchCategories(expectedOwnerId: owner.id)
          .first;
      if (!context.mounted) return;
      await _requireDestinationContext(useCases, owner.id);
      if (!context.mounted) return;
      if (forImport &&
          (!identical(libraryContext, _libraryContext) ||
              ModalRoute.isCurrentOf(context) != true)) {
        return;
      }
      final importOwnerWrites = forImport
          ? _dependencies?.watchLocalOwnerWrites()
          : null;
      final category = await showModalBottomSheet<VocabularyCategory>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StreamBuilder<void>(
          stream: importOwnerWrites,
          builder: (context, ownerWrites) {
            if (ownerWrites.connectionState == ConnectionState.active ||
                ownerWrites.hasError ||
                (forImport &&
                    (!identical(libraryContext, _libraryContext) ||
                        owner.id != _ownerId))) {
              return SafeArea(
                child: ListTile(
                  title: const Text(
                    'ผู้ใช้เปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่',
                  ),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              );
            }
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      forImport
                          ? 'เลือกชุดที่จะนำเข้าคำ'
                          : 'เลือกชุดที่จะเพิ่มคำ',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final category in categories)
                      ListTile(
                        title: Text(category.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheetContext, category),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        final created = await _showAddCategory(
                          sheetContext,
                          useCases,
                          expectedOwnerId: owner.id,
                        );
                        if (sheetContext.mounted && created != null) {
                          Navigator.pop(sheetContext, created);
                        }
                      },
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('สร้างชุดคำศัพท์ใหม่'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (category != null && context.mounted) {
        await _requireDestinationContext(useCases, owner.id);
        if (!context.mounted) return;
        if (forImport &&
            (!identical(libraryContext, _libraryContext) ||
                ModalRoute.isCurrentOf(context) != true)) {
          return;
        }
        if (category.ownerId != owner.id) {
          throw StateError('destination owner changed');
        }
        if (forImport) {
          await AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: 'vocabulary/import/save',
              builder: (_) => AddMultipleWordsScreen(
                categoryId: category.id,
                categoryName: category.name,
                vocabulary: useCases,
                pasteTable: pasteTable,
                expectedOwnerId: owner.id,
              ),
            ),
          );
        } else {
          await _openCategory(context, useCases, category, startAdding: true);
        }
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'อ่านชุดคำไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _choosingDestination = false);
    }
  }

  Future<void> _requireDestinationContext(
    VocabularyUseCases useCases,
    String ownerId,
  ) async {
    if (!mounted || !identical(_useCases(context), useCases)) {
      throw StateError('vocabulary scope changed');
    }
    final owner = await useCases.owners.getOrCreateActiveOwner();
    if (!mounted ||
        !identical(_useCases(context), useCases) ||
        owner.id != ownerId) {
      throw StateError('vocabulary owner changed');
    }
  }

  Future<VocabularyCategory?> _showAddCategory(
    BuildContext context,
    VocabularyUseCases useCases, {
    String? expectedOwnerId,
  }) async {
    var name = '';
    var busy = false;
    String? error;
    late final String ownerId;
    try {
      ownerId =
          expectedOwnerId ??
          (await useCases.owners.getOrCreateActiveOwner()).id;
      await _requireDestinationContext(useCases, ownerId);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'บัญชีเปลี่ยนแล้ว กรุณาเลือกชุดใหม่');
      }
      return null;
    }
    if (!context.mounted) return null;
    return showDialog<VocabularyCategory>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            if (busy) return;
            if (name.trim().isEmpty) {
              setDialogState(() => error = 'กรอกชื่อหมวดหมู่');
              return;
            }
            setDialogState(() {
              busy = true;
              error = null;
            });
            try {
              await _requireDestinationContext(useCases, ownerId);
              final created = await useCases.createCategory(
                name,
                expectedOwnerId: ownerId,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, created);
            } on InvalidVocabularyFailure {
              if (dialogContext.mounted) {
                setDialogState(
                  () => error = 'กรอกชื่อหมวดหมู่ไม่เกิน 80 ตัวอักษร',
                );
              }
            } on DuplicateVocabularyFailure {
              if (dialogContext.mounted) {
                setDialogState(() => error = 'มีหมวดหมู่นี้แล้ว');
              }
            } catch (_) {
              if (dialogContext.mounted) {
                setDialogState(() => error = 'บันทึกหมวดหมู่ไม่สำเร็จ');
              }
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => busy = false);
              }
            }
          }

          return PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('เพิ่มหมวดหมู่'),
              content: TextField(
                key: const ValueKey('category-name-field'),
                autofocus: true,
                enabled: !busy,
                maxLength: maxCategoryNameLength,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'ชื่อหมวดหมู่',
                  errorText: error,
                ),
                onChanged: (value) {
                  name = value;
                  if (error != null) setDialogState(() => error = null);
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  key: const ValueKey('save-category'),
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'กำลังบันทึก…' : 'บันทึก'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategory category,
  ) async {
    try {
      await _requireDestinationContext(useCases, category.ownerId);
      if (!context.mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ลบหมวดหมู่'),
          content: Text('ลบ “${category.name}” และซ่อนคำศัพท์ในหมวดนี้หรือไม่'),
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
      await _requireDestinationContext(useCases, category.ownerId);
      await useCases.deleteCategory(category.id);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'ลบหมวดหมู่ไม่สำเร็จ');
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LocalDataUnavailable extends StatelessWidget {
  const _LocalDataUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'เปิดฐานข้อมูลในเครื่องไม่สำเร็จ\nกรุณาปิดและเปิดแอปใหม่',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(liveRegion: true, child: Text('อ่านหมวดหมู่ไม่สำเร็จ')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
