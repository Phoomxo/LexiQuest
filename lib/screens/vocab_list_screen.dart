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

class _VocabListScreenState extends State<VocabListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  FeatureRegistry? get _features =>
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => ProductionFeatureGate(
    feature: Feature.vocabulary,
    registry: _features,
    builder: _buildContent,
  );

  Widget _buildContent(BuildContext context) {
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final importer =
        widget.importer ??
        AppDependenciesScope.maybeOf(context)?.vocabularyImporter;
    final isReadOnlyCategory = PackagedStarterIdentity.isReservedCategoryId(
      widget.categoryId,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
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
                      setState(() => _query = value.trim().toLowerCase());
                    },
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<VocabularyWord>>(
                    stream: useCases.watchWords(widget.categoryId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('อ่านคำศัพท์ไม่สำเร็จ'),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final words = snapshot.data!
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
                            snapshot.data!.isEmpty
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
                                : () => _openWordEditor(context, word: word),
                            child: ListTile(
                              title: Text(word.spelling),
                              subtitle: Text(
                                '${word.meaning} · ${word.partOfSpeech}',
                              ),
                              onTap: isReadOnly
                                  ? null
                                  : () => _openWordEditor(context, word: word),
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
                                      onInvoke: () =>
                                          _openExamples(context, word),
                                      child: IconButton(
                                        tooltip: 'ดูตัวอย่างการใช้',
                                        icon: const Icon(
                                          Icons.menu_book_outlined,
                                        ),
                                        onPressed: () =>
                                            _openExamples(context, word),
                                      ),
                                    ),
                                  if (!isReadOnly)
                                    IconButton(
                                      tooltip: 'ลบคำศัพท์',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _deleteWord(context, useCases, word),
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
      floatingActionButton: useCases == null || isReadOnlyCategory
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (importer != null)
                  MenuActionBinding(
                    id: 'vocabulary/import',
                    label: 'นำเข้าคำศัพท์',
                    onInvoke: () => _openImporter(context),
                    child: FloatingActionButton.small(
                      heroTag: 'words-import',
                      tooltip: 'นำเข้าคำศัพท์',
                      onPressed: () => _openImporter(context),
                      child: const Icon(Icons.file_upload_outlined),
                    ),
                  ),
                const SizedBox(height: 12),
                MenuActionBinding(
                  id: 'vocabulary/add-word',
                  label: 'เพิ่มคำศัพท์',
                  onInvoke: () => _openWordEditor(context),
                  child: FloatingActionButton.extended(
                    key: const ValueKey('add-word'),
                    heroTag: 'words-add',
                    onPressed: () => _openWordEditor(context),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มคำศัพท์'),
                  ),
                ),
              ],
            ),
    );
  }

  void _openImporter(BuildContext context) {
    if (!_admitted) return;
    final features = _features;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/import',
        builder: (_) => AddMultipleWordsScreen(
          featureRegistry: features,
          importer: widget.importer,
          categoryId: widget.categoryId,
          categoryName: widget.categoryName,
        ),
      ),
    );
  }

  void _openWordEditor(BuildContext context, {VocabularyWord? word}) {
    if (!_admitted) return;
    final features = _features;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: word == null ? 'vocabulary/add' : 'vocabulary/edit',
        builder: (_) => AddWordScreen(
          categoryId: widget.categoryId,
          word: word,
          featureRegistry: features,
          vocabulary: widget.vocabulary,
        ),
      ),
    );
  }

  void _openExamples(BuildContext context, VocabularyWord word) {
    if (!_admitted) return;
    final features = _features;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/examples',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.vocabulary,
          registry: features,
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('ตัวอย่างการใช้คำ')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    word.spelling,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    word.meaning,
                    style: Theme.of(context).textTheme.titleLarge,
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
    if (accepted != true || !_admitted) return;
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
