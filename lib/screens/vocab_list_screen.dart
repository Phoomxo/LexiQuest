import 'package:flutter/material.dart';

import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import '../navigation/app_routes.dart';

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.vocabulary,
    this.importer,
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? importer;

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

  @override
  Widget build(BuildContext context) {
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final importer =
        widget.importer ??
        AppDependenciesScope.maybeOf(context)?.vocabularyImporter;
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
                        return const Center(
                          child: Text('ยังไม่มีคำศัพท์ในหมวดนี้'),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: words.length,
                        itemBuilder: (context, index) {
                          final word = words[index];
                          return ListTile(
                            title: Text(word.spelling),
                            subtitle: Text(
                              '${word.meaning} · ${word.partOfSpeech}',
                            ),
                            onTap: () =>
                                _openWordEditor(context, useCases, word: word),
                            trailing: IconButton(
                              tooltip: 'ลบคำศัพท์',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _deleteWord(context, useCases, word),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: useCases == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (importer != null)
                  FloatingActionButton.small(
                    heroTag: 'words-import',
                    tooltip: 'นำเข้าคำศัพท์',
                    onPressed: () {
                      AppNavigator.pushPage<void>(
                        context,
                        AppPage<void>(
                          name: 'vocabulary/import',
                          builder: (_) => AddMultipleWordsScreen(
                            categoryId: widget.categoryId,
                            categoryName: widget.categoryName,
                            importer: importer,
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.file_upload_outlined),
                  ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  key: const ValueKey('add-word'),
                  heroTag: 'words-add',
                  onPressed: () => _openWordEditor(context, useCases),
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มคำศัพท์'),
                ),
              ],
            ),
    );
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
