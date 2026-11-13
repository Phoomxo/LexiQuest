import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';
import 'vocab_list_screen.dart';

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
  VocabularyUseCases? _vocabulary;
  Stream<List<VocabularyCategorySummary>>? _categories;
  Stream<List<VocabularyWord>>? _matches;
  bool _choosingDestination = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  VocabularyUseCases? _useCases(BuildContext context) =>
      widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;

  @override
  Widget build(BuildContext context) {
    final useCases = _useCases(context);
    if (!identical(useCases, _vocabulary)) {
      _vocabulary = useCases;
      _categories = useCases?.watchLibrary();
      _matches = useCases?.searchWords(_query);
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
            ? 160
            : M3Theme.appBarToolbarHeight(context),
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
          if (useCases != null)
            TextButton.icon(
              key: const ValueKey('library-add-word'),
              onPressed: _choosingDestination
                  ? null
                  : () => _chooseDestination(context, useCases),
              icon: const Icon(Icons.add),
              label: Text(_choosingDestination ? 'กำลังเปิด…' : 'เพิ่มคำ'),
            ),
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
        child: useCases == null
            ? const _LocalDataUnavailable()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: SearchBar(
                      key: const ValueKey('category-search'),
                      controller: _searchController,
                      hintText: 'ค้นหาคำในคลัง',
                      elevation: const WidgetStatePropertyAll(0),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      leading: const Icon(Icons.search),
                      onChanged: (value) => setState(() {
                        _query = normalizeVocabularyText(value);
                        _matches = useCases.searchWords(_query);
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _query.isEmpty ? 'ชุดคำของฉัน' : 'ผลการค้นหา',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextButton.icon(
                          key: const ValueKey('add-category'),
                          onPressed: () => _showAddCategory(context, useCases),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('เพิ่มชุด'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<VocabularyCategorySummary>>(
                      key: ValueKey((useCases, 'library')),
                      stream: _categories,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _FailureState(
                            onRetry: () => setState(
                              () => _categories = useCases.watchLibrary(),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'กำลังโหลดหมวดหมู่',
                            ),
                          );
                        }
                        if (snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text(
                              'ยังไม่มีหมวดหมู่\nเพิ่มหมวดหมู่เพื่อเริ่มเก็บคำศัพท์',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        final summaries = snapshot.requireData;
                        final categories = summaries
                            .where(
                              (entry) => entry.category.normalizedName.contains(
                                _query,
                              ),
                            )
                            .toList(growable: false);
                        if (_query.isEmpty) {
                          return _libraryList(context, useCases, categories);
                        }
                        return StreamBuilder<List<VocabularyWord>>(
                          key: ValueKey((useCases, _query)),
                          stream: _matches,
                          builder: (context, matches) {
                            if (matches.hasError) {
                              return _FailureState(
                                onRetry: () => setState(
                                  () => _matches = useCases.searchWords(_query),
                                ),
                              );
                            }
                            if (!matches.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  semanticsLabel: 'กำลังค้นหาคำในคลัง',
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
                              return const Center(
                                child: Text('ไม่พบคำหรือชุดที่ค้นหา'),
                              );
                            }
                            return ListView(
                              key: PageStorageKey('library-search:$_query'),
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                              children: [
                                for (final summary in categories)
                                  _categoryTile(context, useCases, summary),
                                for (final word in words)
                                  ListTile(
                                    title: Text(word.spelling),
                                    subtitle: Text(byId[word.categoryId]!.name),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openCategory(
                                      context,
                                      useCases,
                                      byId[word.categoryId]!,
                                      initialQuery: word.spelling,
                                    ),
                                  ),
                                if (words.length == 50)
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text(
                                      'แสดง 50 คำแรก พิมพ์เพิ่มเพื่อค้นหาให้แคบลง',
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
    );
  }

  Widget _libraryList(
    BuildContext context,
    VocabularyUseCases useCases,
    List<VocabularyCategorySummary> summaries,
  ) => ListView.separated(
    key: const PageStorageKey('vocabulary-categories'),
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        category.name,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${summary.wordCount} คำ${summary.previewSpellings.isEmpty ? '' : ' · ${summary.previewSpellings.join(' · ')}'}',
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
  }) => AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: 'vocabulary/category',
      builder: (_) => VocabListScreen(
        categoryId: category.id,
        categoryName: category.name,
        vocabulary: useCases,
        startAdding: startAdding,
        initialQuery: initialQuery,
      ),
    ),
  );

  Future<void> _chooseDestination(
    BuildContext context,
    VocabularyUseCases useCases,
  ) async {
    if (_choosingDestination) return;
    setState(() => _choosingDestination = true);
    try {
      final owner = await useCases.owners.getOrCreateActiveOwner();
      final categories = await useCases.watchCategories().first;
      if (!context.mounted) return;
      await _requireDestinationContext(useCases, owner.id);
      if (!context.mounted) return;
      final category = await showModalBottomSheet<VocabularyCategory>(
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
                Text(
                  'เลือกชุดที่จะเพิ่มคำ',
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
        ),
      );
      if (category != null && context.mounted) {
        await _requireDestinationContext(useCases, owner.id);
        if (!context.mounted) return;
        if (category.ownerId != owner.id) {
          throw StateError('destination owner changed');
        }
        await _openCategory(context, useCases, category, startAdding: true);
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
    try {
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
