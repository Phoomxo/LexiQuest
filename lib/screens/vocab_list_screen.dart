import 'vocabulary_browse_lifetime.dart';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/packaged_starter_identity.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import '../navigation/app_routes.dart';
import '../widgets/cefr_practice_example.dart';

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({
    super.key,
    this.featureRegistry,
    required this.categoryId,
    required this.categoryName,
    this.vocabulary,
    this.importer,
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? importer;

  final FeatureRegistry? featureRegistry;

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen>
    with WidgetsBindingObserver, VocabularyBrowseLifetime<VocabListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  VocabularyUseCases? _vocabulary;
  VocabularyBrowseRead<VocabularyWord>? _words;
  FeatureRegistry? _boundFeatures;
  String? _boundCategory;
  String? _displayOwner;

  void _bind() {
    final next =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final features = _features;
    if (!identical(features, _boundFeatures)) browseGeneration++;
    _boundFeatures = features;
    bindBrowseFeatures(features);
    if (identical(next, _vocabulary) && _boundCategory == widget.categoryId)
      return;
    browseGeneration++;
    _words?.dispose();
    _query = '';
    _searchController.clear();
    _displayOwner = null;
    _boundCategory = widget.categoryId;
    _vocabulary = next;
    final category = widget.categoryId;
    _words = next == null
        ? null
        : VocabularyBrowseRead(
            next,
            (owner) => next.vocabulary.watchWords(owner, category),
            categoryId: category,
          );
    _words?.addListener(_readChanged);
  }

  void _readChanged() {
    final owner = _words?.ownerId;
    if (owner != null && _displayOwner != null && owner != _displayOwner) {
      _query = '';
      _searchController.clear();
      browseGeneration++;
    }
    _displayOwner = owner;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(VocabListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.importer, widget.importer)) browseGeneration++;
    _bind();
  }

  bool _current(int generation, int revision) =>
      browseCurrent(generation) &&
      !browseOpening &&
      _admitted &&
      _words?.revision == revision;

  void _retry(int generation, int revision) {
    if (!_current(generation, revision) || _words!.pending) return;
    _words!.refresh();
  }

  Future<void> _openRoute(
    int generation,
    int revision,
    AppPage<void> page,
  ) async {
    if (!_current(generation, revision)) return;
    final read = _words!;
    browseOpening = true;
    try {
      if (!await read.admit() ||
          !browseCurrent(generation) ||
          read.revision != revision ||
          !_admitted)
        return;
      await AppNavigator.pushPage<void>(context, page);
    } finally {
      browseOpening = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _words?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  FeatureRegistry? get _features =>
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) browseExit();
    },
    child: ProductionFeatureGate(
      feature: Feature.vocabulary,
      registry: _features,
      builder: (context) => _words == null
          ? _buildContent(context)
          : ListenableBuilder(
              listenable: _words!,
              builder: (context, _) => _buildContent(context),
            ),
    ),
  );

  Widget _buildContent(BuildContext context) {
    final useCases = _vocabulary;
    final generation = browseGeneration;
    final revision = _words?.revision ?? 0;
    final importer =
        widget.importer ??
        AppDependenciesScope.maybeOf(context)?.vocabularyImporter;
    final isReadOnlyCategory = PackagedStarterIdentity.isReservedCategoryId(
      widget.categoryId,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _words?.available == false ? 'คลังคำศัพท์' : widget.categoryName,
        ),
      ),
      body: useCases == null
          ? const Center(child: Text('ฐานข้อมูลในเครื่องไม่พร้อมใช้งาน'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'ค้นหาคำศัพท์',
                    leading: const Icon(Icons.search),
                    onChanged: (value) {
                      if (!_current(generation, revision)) return;
                      setState(() => _query = value.trim().toLowerCase());
                    },
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final read = _words!;
                      if (read.failed) {
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('อ่านคำศัพท์ไม่สำเร็จ'),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => _retry(generation, revision),
                                  child: const Text('ลองใหม่'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (!read.available)
                        return const Center(
                          child: Text('หมวดหมู่นี้ไม่พร้อมใช้งาน'),
                        );
                      if (read.data == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final words = read.data!
                          .where(
                            (word) =>
                                _query.isEmpty ||
                                word.normalizedSpelling.contains(_query) ||
                                word.normalizedMeaning.contains(_query),
                          )
                          .toList();
                      if (words.isEmpty) {
                        return Center(
                          child: Text(
                            read.data!.isEmpty
                                ? 'ยังไม่มีคำศัพท์ในหมวดนี้'
                                : 'ไม่พบคำศัพท์ที่ตรงกับคำค้น',
                          ),
                        );
                      }
                      return ListView.builder(
                        // Leave the final row clear of both stacked actions.
                        padding: EdgeInsets.only(
                          bottom: isReadOnlyCategory
                              ? 16
                              : importer == null
                              ? 96
                              : 160,
                        ),
                        itemCount: words.length,
                        itemBuilder: (context, index) {
                          final word = words[index];
                          final isReadOnly =
                              isReadOnlyCategory || word.isReadOnly;
                          return MenuActionBinding(
                            key: ValueKey(word.id),
                            ownerId: word.isReadOnly ? null : word.ownerId,
                            id: 'vocabulary/word/$index/edit',
                            label: 'แก้ไขคำ ${word.spelling}',
                            onInvoke: isReadOnly
                                ? null
                                : () => _openWordEditor(
                                    context,
                                    generation,
                                    revision,
                                    word: word,
                                  ),
                            child: ListTile(
                              title: Text(word.spelling),
                              subtitle: Text(
                                '${word.meaning} · ${word.partOfSpeech}',
                              ),
                              onTap: isReadOnly
                                  ? null
                                  : () => _openWordEditor(
                                      context,
                                      generation,
                                      revision,
                                      word: word,
                                    ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (word.cefrLevel != null)
                                    MenuActionBinding(
                                      id: 'vocabulary/word/$index/examples',
                                      ownerId: word.isReadOnly
                                          ? null
                                          : word.ownerId,
                                      label: 'ดูตัวอย่างคำ ${word.spelling}',
                                      onInvoke: () => _openExamples(
                                        context,
                                        word,
                                        generation,
                                        revision,
                                      ),
                                      child: IconButton(
                                        tooltip: 'ดูตัวอย่างการใช้',
                                        icon: const Icon(
                                          Icons.menu_book_outlined,
                                        ),
                                        onPressed: () => _openExamples(
                                          context,
                                          word,
                                          generation,
                                          revision,
                                        ),
                                      ),
                                    ),
                                  if (!isReadOnly)
                                    MenuActionBinding(
                                      id: 'vocabulary/word/$index/delete',
                                      ownerId: word.ownerId,
                                      label:
                                          'ลบคำ ${word.spelling} — ${word.meaning}',
                                      onInvoke: () =>
                                          _deleteWord(context, useCases, word),
                                      child: IconButton(
                                        tooltip: 'ลบคำศัพท์',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteWord(
                                          context,
                                          useCases,
                                          word,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton:
          useCases == null || isReadOnlyCategory || _words?.available != true
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (importer != null)
                  MenuActionBinding(
                    id: 'vocabulary/import',
                    label: 'นำเข้าคำศัพท์',
                    onInvoke: () =>
                        _openImporter(context, generation, revision),
                    child: FloatingActionButton.small(
                      heroTag: 'words-import',
                      tooltip: 'นำเข้าคำศัพท์',
                      onPressed: () =>
                          _openImporter(context, generation, revision),
                      child: const Icon(Icons.file_upload_outlined),
                    ),
                  ),
                const SizedBox(height: 12),
                MenuActionBinding(
                  id: 'vocabulary/add-word',
                  label: 'เพิ่มคำศัพท์',
                  onInvoke: () =>
                      _openWordEditor(context, generation, revision),
                  child: FloatingActionButton.extended(
                    key: const ValueKey('add-word'),
                    heroTag: 'words-add',
                    onPressed: () =>
                        _openWordEditor(context, generation, revision),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มคำศัพท์'),
                  ),
                ),
              ],
            ),
    );
  }

  void _openImporter(BuildContext context, int generation, int revision) {
    if (!_current(generation, revision)) return;
    final features = widget.featureRegistry;
    final categoryId = widget.categoryId;
    final categoryName = widget.categoryName;
    final explicitImporter = widget.importer;
    _openRoute(
      generation,
      revision,
      AppPage<void>(
        name: 'vocabulary/import',
        builder: (_) => AddMultipleWordsScreen(
          featureRegistry: features,
          importer: explicitImporter,
          categoryId: categoryId,
          categoryName: categoryName,
        ),
      ),
    );
  }

  void _openWordEditor(
    BuildContext context,
    int generation,
    int revision, {
    VocabularyWord? word,
  }) {
    if (!_current(generation, revision)) return;
    final features = widget.featureRegistry;
    final categoryId = widget.categoryId;
    final explicitVocabulary = widget.vocabulary;
    _openRoute(
      generation,
      revision,
      AppPage<void>(
        name: word == null ? 'vocabulary/add' : 'vocabulary/edit',
        builder: (_) => AddWordScreen(
          categoryId: categoryId,
          word: word,
          featureRegistry: features,
          vocabulary: explicitVocabulary,
        ),
      ),
    );
  }

  void _openExamples(
    BuildContext context,
    VocabularyWord word,
    int generation,
    int revision,
  ) {
    if (!_current(generation, revision)) return;
    final features = widget.featureRegistry;
    _openRoute(
      generation,
      revision,
      AppPage<void>(
        name: 'vocabulary/examples',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.vocabulary,
          registry: features,
          builder: (childContext) => Scaffold(
            appBar: AppBar(title: const Text('ตัวอย่างการใช้คำ')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    word.spelling,
                    style: Theme.of(childContext).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    word.meaning,
                    style: Theme.of(childContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('${word.partOfSpeech} · ${word.cefrLevel}'),
                  CefrPracticeExample(
                    spelling: word.spelling,
                    meaning: word.meaning,
                    partOfSpeech: word.partOfSpeech,
                    cefrLevel: word.cefrLevel,
                    revealed: true,
                    showUnavailable: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWord(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyWord word,
  ) async {
    if (!_admitted) return;
    var deleting = false;
    var deletionCommitted = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => MenuActionBinding(
        id: 'vocabulary/word-delete-target',
        label: '${word.spelling} — ${word.meaning}',
        ownerId: word.ownerId,
        onInvoke: null,
        readValue: word.id,
        child: StatefulBuilder(
          builder: (dialogContext, updateDialog) {
            void cancel() => Navigator.pop(dialogContext, false);
            return MenuActionBinding(
              id: 'vocabulary/word-delete-confirm',
              label: 'ยืนยันลบคำ ${word.spelling}',
              ownerId: word.ownerId,
              onInvoke: null,
              fields: const {'wordId': 256},
              onForm: (values) async {
                if (values['wordId'] != word.id) return {'status': 'invalid'};
                if (deleting || !_admitted) return {'status': 'busy'};
                updateDialog(() => deleting = true);
                try {
                  final result = await _mcpDeleteWord(
                    dialogContext,
                    useCases,
                    word,
                    alreadyCommitted: deletionCommitted,
                    onCommitted: () => deletionCommitted = true,
                  );
                  if (result['status'] == 'deleted' && dialogContext.mounted) {
                    Navigator.pop(dialogContext, false);
                  }
                  return result;
                } finally {
                  if (dialogContext.mounted) {
                    updateDialog(() => deleting = false);
                  }
                }
              },
              child: AlertDialog(
                title: const Text('ลบคำศัพท์'),
                content: Text(
                  deletionCommitted
                      ? 'ยังยืนยันผลการลบไม่ได้ ปิดหน้าต่างนี้เพื่อตรวจสอบรายการคำศัพท์'
                      : 'ลบ “${word.spelling}” (${word.meaning}) หรือไม่',
                ),
                actions: [
                  MenuActionBinding(
                    id: 'vocabulary/word-delete-cancel',
                    label: deletionCommitted
                        ? 'ปิดผลการลบคำศัพท์'
                        : 'ยกเลิกการลบคำศัพท์',
                    ownerId: word.ownerId,
                    onInvoke: cancel,
                    child: TextButton(
                      onPressed: cancel,
                      child: Text(deletionCommitted ? 'ปิด' : 'ยกเลิก'),
                    ),
                  ),
                  FilledButton(
                    onPressed: deleting || deletionCommitted
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: const Text('ลบ'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (accepted != true || !_admitted) return;
    try {
      await useCases.deleteWord(word.id, expectedOwnerId: word.ownerId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบคำศัพท์ไม่สำเร็จ')));
      }
    }
  }

  Future<Map<String, Object?>> _mcpDeleteWord(
    BuildContext dialogContext,
    VocabularyUseCases useCases,
    VocabularyWord word, {
    required bool alreadyCommitted,
    required VoidCallback onCommitted,
  }) async {
    final registry = MenuActionScope.maybeOf(dialogContext);
    final revision = registry?.snapshot()['revision'];
    bool allowed() =>
        _admitted &&
        dialogContext.mounted &&
        ModalRoute.of(dialogContext)?.isCurrent == true &&
        registry?.currentOwner() == word.ownerId &&
        registry?.snapshot()['revision'] == revision;
    if (!allowed()) return {'status': 'stale'};
    var committed = alreadyCommitted;
    try {
      if (!committed) {
        await useCases.deleteWord(
          word.id,
          expectedOwnerId: word.ownerId,
          mutationAllowed: allowed,
        );
        committed = true;
        onCommitted();
      }
      final remaining = await useCases.vocabulary.listAllWords(word.ownerId);
      if (!allowed()) return {'status': 'stale'};
      if (remaining.any((record) => record.id == word.id)) {
        return {'status': 'verification_failed'};
      }
      return {'status': 'deleted', 'wordId': word.id};
    } catch (_) {
      return {'status': committed ? 'outcome_unknown' : 'failed'};
    }
  }
}
