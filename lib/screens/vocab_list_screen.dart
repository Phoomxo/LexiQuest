import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import 'add_multiple_words_screen.dart';
import 'add_vocab_screen.dart';
import '../navigation/app_routes.dart';
import 'source_practice_screen.dart';

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
  int _retryEpoch = 0;

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
    final canPracticeSource =
        useCases != null && learning != null && sourcePicker != null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, widget.categoryName),
      ),
      body: AdaptiveContentPane(
        child: useCases == null
            ? const Center(child: Text('ฐานข้อมูลในเครื่องไม่พร้อมใช้งาน'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SearchBar(
                          controller: _searchController,
                          hintText: 'ค้นหาคำศัพท์',
                          leading: const Icon(Icons.search),
                          onChanged: (value) {
                            setState(() => _query = value.trim().toLowerCase());
                          },
                        ),
                        if (canPracticeSource || importer != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (canPracticeSource)
                                OutlinedButton.icon(
                                  key: const ValueKey('source-practice'),
                                  onPressed: () {
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
                                          associativeLearning:
                                              dependencies?.associativeLearning,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.menu_book_outlined),
                                  label: const Text('ฝึกจากไฟล์'),
                                ),
                              if (importer != null)
                                OutlinedButton.icon(
                                  key: const ValueKey('import-words'),
                                  onPressed: () {
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
                                  label: const Text('นำเข้าคำศัพท์'),
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
                      stream: useCases.watchWords(widget.categoryId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text('อ่านคำศัพท์ไม่สำเร็จ'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _retryEpoch++),
                                  child: const Text('ลองใหม่'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'กำลังโหลดคำศัพท์',
                            ),
                          );
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
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: useCases == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('add-word'),
              heroTag: 'words-add',
              onPressed: () => _openWordEditor(context, useCases),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มคำศัพท์'),
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
