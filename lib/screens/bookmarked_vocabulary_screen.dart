import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import 'vocabulary_word_detail_screen.dart';

class BookmarkedVocabularyScreen extends StatefulWidget {
  const BookmarkedVocabularyScreen({
    super.key,
    required this.scope,
    required this.expectedOwnerId,
  });

  final AppDependencies scope;
  final String expectedOwnerId;

  @override
  State<BookmarkedVocabularyScreen> createState() =>
      _BookmarkedVocabularyScreenState();
}

class _BookmarkedVocabularyScreenState
    extends State<BookmarkedVocabularyScreen> {
  late final _vocabulary = widget.scope.vocabulary;
  late final _words = _vocabulary?.watchBookmarkedWords(
    expectedOwnerId: widget.expectedOwnerId,
  );
  late final _categories = _vocabulary?.watchPinnedCategories(
    widget.expectedOwnerId,
  );
  bool _openingDetail = false;

  Future<void> _openDetail(
    VocabularyWord word,
    VocabularyCategory category,
  ) async {
    if (_openingDetail) return;
    _openingDetail = true;
    try {
      final owner = await widget.scope.readActiveOwnerId();
      if (!mounted ||
          owner != widget.expectedOwnerId ||
          !identical(AppDependenciesScope.maybeOf(context), widget.scope) ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'vocabulary/bookmarked-word',
          builder: (_) => VocabularyWordDetailScreen(
            word: word,
            categoryName: category.name,
            vocabulary: _vocabulary!,
            scope: widget.scope,
            bookmarkedOnly: true,
            returnLabel: 'กลับคำที่เก็บไว้',
          ),
        ),
      );
    } on Object {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดรายละเอียดคำไม่สำเร็จ')),
        );
      }
    } finally {
      _openingDetail = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, 'คำที่เก็บไว้'),
    ),
    body: AdaptiveContentPane(
      child: SafeArea(
        child: StreamBuilder<List<VocabularyCategory>>(
          stream: _categories,
          builder: (context, categories) => StreamBuilder<List<VocabularyWord>>(
            stream: _words,
            builder: (context, words) {
              if (_vocabulary == null ||
                  categories.hasError ||
                  words.hasError) {
                return const Center(child: Text('อ่านคำที่เก็บไว้ไม่สำเร็จ'));
              }
              if (!categories.hasData || !words.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'กำลังอ่านคำที่เก็บไว้',
                  ),
                );
              }
              final byId = {
                for (final category in categories.requireData)
                  category.id: category,
              };
              final saved = [
                for (final word in words.requireData)
                  if (byId.containsKey(word.categoryId)) word,
              ];
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('เก็บในเครื่อง · เปิดดูได้ขณะออฟไลน์'),
                  const SizedBox(height: 12),
                  if (saved.isEmpty) const Text('ยังไม่มีคำที่เก็บไว้'),
                  for (final word in saved)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(word.spelling),
                      subtitle: Text(
                        '${word.meaning} · ${byId[word.categoryId]!.name}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetail(word, byId[word.categoryId]!),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AdaptiveContentPane.formMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('กลับศูนย์ทบทวน'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
