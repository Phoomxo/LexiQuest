import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'associative_reading_session_screen.dart';
import 'categories_page.dart';

enum AssociativeReadingLauncherUnavailableReason {
  vocabulary,
  learning,
  associativeLearning,
}

class AssociativeReadingLauncherScreen extends StatefulWidget {
  const AssociativeReadingLauncherScreen({
    super.key,
    this.vocabulary,
    this.learning,
    this.associativeLearning,
  });

  final VocabularyUseCases? vocabulary;
  final LearningUseCases? learning;
  final AssociativeLearningPort? associativeLearning;

  @override
  State<AssociativeReadingLauncherScreen> createState() =>
      _AssociativeReadingLauncherScreenState();
}

class _AssociativeReadingLauncherScreenState
    extends State<AssociativeReadingLauncherScreen> {
  bool _initialized = false;
  List<VocabularyWord>? _words;
  Object? _loadFailure;
  AssociativeReadingLauncherUnavailableReason? _unavailableReason;
  LearningUseCases? _learning;
  AssociativeLearningPort? _associativeLearning;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final dependencies = AppDependenciesScope.maybeOf(context);
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    _learning = widget.learning ?? dependencies?.learning;
    _associativeLearning =
        widget.associativeLearning ?? dependencies?.associativeLearning;

    if (vocabulary == null) {
      _unavailableReason =
          AssociativeReadingLauncherUnavailableReason.vocabulary;
      return;
    }
    if (_learning == null) {
      _unavailableReason = AssociativeReadingLauncherUnavailableReason.learning;
      return;
    }
    if (_associativeLearning == null) {
      _unavailableReason =
          AssociativeReadingLauncherUnavailableReason.associativeLearning;
      return;
    }
    _loadWords(vocabulary);
  }

  Future<void> _loadWords(VocabularyUseCases vocabulary) async {
    try {
      final loaded = await vocabulary.getGameWords(limit: 10);
      if (!mounted) return;
      final spellings = <String>{};
      final words = loaded
          .where((word) => spellings.add(word.spelling))
          .toList(growable: false);
      setState(() => _words = List.unmodifiable(words));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadFailure = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unavailableReason = _unavailableReason;
    if (unavailableReason != null) {
      return _LauncherUnavailable(reason: unavailableReason);
    }
    if (_loadFailure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Associative Reading')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Vocabulary could not be loaded for associative reading.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final words = _words;
    if (words == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (words.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Associative Reading')),
        body: Center(
          key: const ValueKey('associative-reading-empty'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Save at least one vocabulary word before starting.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'vocabulary/create',
                      builder: (_) => CategoriesPage(),
                    ),
                    replace: true,
                  ),
                  child: const Text('Create vocabulary'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Associative Reading')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${words.length} target word${words.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: words
                    .map(
                      (word) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(word.spelling),
                        subtitle: Text(word.meaning),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            FilledButton(
              onPressed: () => _start(words),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Start reading'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(List<VocabularyWord> words) {
    final learning = _learning!;
    final associativeLearning = _associativeLearning!;
    final wordIds = <String, String>{
      for (final word in words) word.spelling: word.id,
    };
    var cefrLevel = 'A2';
    for (final word in words) {
      final candidate = word.cefrLevel?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        cefrLevel = candidate;
        break;
      }
    }
    final passage = words
        .map((word) => '${word.spelling} means ${word.meaning}.')
        .join(' ');
    final versionSeed = jsonEncode([
      for (final word in words) [word.id, word.localRevision],
    ]);
    final documentDigest = sha256.convert(utf8.encode(versionSeed)).toString();
    final documentRevision =
        int.parse(documentDigest.substring(0, 13), radix: 16) + 1;

    return AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/associative-reading/session',
        builder: (_) => AssociativeReadingSessionScreen(
          cefrLevel: cefrLevel,
          targetWords: words
              .map((word) => word.spelling)
              .toList(growable: false),
          targetWordIds: Map.unmodifiable(wordIds),
          passageText: passage,
          documentId: 'associative-reading:$documentDigest',
          documentRevision: documentRevision,
          learning: learning,
          associativeLearning: associativeLearning,
        ),
      ),
    );
  }
}

class _LauncherUnavailable extends StatelessWidget {
  const _LauncherUnavailable({required this.reason});

  final AssociativeReadingLauncherUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final detail = switch (reason) {
      AssociativeReadingLauncherUnavailableReason.vocabulary =>
        'Vocabulary is unavailable.',
      AssociativeReadingLauncherUnavailableReason.learning =>
        'Learning records are unavailable.',
      AssociativeReadingLauncherUnavailableReason.associativeLearning =>
        'Associative persistence is unavailable.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Associative Reading')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Associative reading is unavailable on this installation. '
            '$detail',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
