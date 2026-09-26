import 'word_delete_dialog.dart';
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
  final _deleteChanges = ChangeNotifier();
  Listenable? _deleteFeatures;
  Route<void>? _deleteDialog;
  int _deleteEpoch = 0;
  bool _deleteForeground = true;
  bool _deleteExited = false;

  void _retireDelete() {
    _deleteEpoch++;
    _deleteChanges.notifyListeners();
  }

  bool get _deleteVisible =>
      mounted &&
      !_deleteExited &&
      _deleteForeground &&
      TickerMode.valuesOf(this.context).enabled &&
      (ModalRoute.of(this.context)?.isCurrent != false ||
          _deleteDialog?.isCurrent == true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _deleteForeground = state == AppLifecycleState.resumed;
    _retireDelete();
  }

  void _bind() {
    final next =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final features = _features;
    if (!identical(features, _boundFeatures)) {
      browseGeneration++;
      _retireDelete();
      _deleteFeatures?.removeListener(_retireDelete);
      _deleteFeatures = features is Listenable ? features as Listenable : null;
      _deleteFeatures?.addListener(_retireDelete);
    }
    _boundFeatures = features;
    bindBrowseFeatures(features);
    if (identical(next, _vocabulary) && _boundCategory == widget.categoryId)
      return;
    browseGeneration++;
    _retireDelete();
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
    if (_deleteDialog != null && !_deleteVisible) _retireDelete();
  }

  @override
  void didUpdateWidget(VocabListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.importer, widget.importer)) {
      browseGeneration++;
      _retireDelete();
    }
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
    _deleteExited = true;
    _retireDelete();
    _deleteFeatures?.removeListener(_retireDelete);
    _deleteChanges.dispose();
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
      if (didPop) {
        _deleteExited = true;
        _retireDelete();
        browseExit();
      }
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
                                      onInvoke: () => _deleteWord(
                                        useCases,
                                        word,
                                        generation,
                                        revision,
                                      ),
                                      child: IconButton(
                                        tooltip: 'ลบคำศัพท์',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteWord(
                                          useCases,
                                          word,
                                          generation,
                                          revision,
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
    VocabularyUseCases useCases,
    VocabularyWord word,
    int generation,
    int revision,
  ) async {
    if (!_current(generation, revision) ||
        !identical(useCases, _vocabulary) ||
        word.isReadOnly)
      return;
    browseOpening = true;
    final read = _words!;
    final epoch = ++_deleteEpoch;
    bool entryCurrent() =>
        browseCurrent(generation) &&
        _admitted &&
        identical(useCases, _vocabulary) &&
        read.revision == revision;
    try {
      if (!await read.admit() || !entryCurrent()) return;
      final words = await useCases.vocabulary.listAllWords(word.ownerId);
      if (!entryCurrent() || !words.any((w) => sameDeleteWord(w, word))) return;
      bool allowed() =>
          _deleteVisible &&
          _admitted &&
          epoch == _deleteEpoch &&
          identical(useCases, _vocabulary);
      final route = DialogRoute<void>(
        context: this.context,
        builder: (_) => WordDeleteDialog(
          vocabulary: useCases,
          word: word,
          read: read,
          admitted: allowed,
          reconcileAdmitted: () =>
              _deleteVisible && _admitted && identical(useCases, _vocabulary),
          changes: _deleteChanges,
        ),
      );
      _deleteDialog = route;
      await Navigator.of(this.context).push(route);
    } catch (_) {
      if (entryCurrent()) read.refresh();
    } finally {
      _deleteDialog = null;
      browseOpening = false;
      if (mounted) setState(() {});
    }
  }
}
