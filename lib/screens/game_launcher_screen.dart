import 'package:flutter/material.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'boss_battle_screen.dart';
import 'dictation_quiz_screen.dart';
import 'word_scramble_screen.dart';

/// Launcher screen that fetches vocabulary content and opens the selected
/// game mode with real words from the learner's wordbook.
///
/// Shows a loading spinner while fetching, an empty-state message when no
/// words are available, and navigates to the game once content is ready.
class GameLauncherScreen extends StatefulWidget {
  const GameLauncherScreen({
    super.key,
    required this.gameMode,
    this.vocabulary,
  });

  /// Which game to launch after content is ready.
  final GameMode gameMode;

  final VocabularyUseCases? vocabulary;

  @override
  State<GameLauncherScreen> createState() => _GameLauncherScreenState();
}

enum GameMode { wordScramble, dictation, bossBattle }

enum GameLauncherUnavailableReason {
  missingDependency,
  emptyInventory,
  loadFailure,
}

class _GameLauncherScreenState extends State<GameLauncherScreen> {
  List<VocabularyWord>? _words;
  GameLauncherUnavailableReason? _unavailableReason;
  bool _loadStarted = false;
  bool _navigationScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    final useCases =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    if (useCases == null) {
      _unavailableReason = GameLauncherUnavailableReason.missingDependency;
      return;
    }
    _loadWords(useCases);
  }

  Future<void> _loadWords(VocabularyUseCases useCases) async {
    try {
      final words = await useCases.getGameWords(limit: 10);
      if (!mounted) return;
      if (words.isEmpty) {
        setState(
          () =>
              _unavailableReason = GameLauncherUnavailableReason.emptyInventory,
        );
        return;
      }
      setState(
        () => _words = List<VocabularyWord>.unmodifiable(words.take(10)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _unavailableReason = GameLauncherUnavailableReason.loadFailure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    final unavailableReason = _unavailableReason;
    if (unavailableReason != null) {
      return GameLauncherUnavailable(reason: unavailableReason);
    }
    if (words == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Content is ready — launch the game.
    if (!_navigationScheduled) {
      _navigationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigateToGame(context, words);
      });
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  void _navigateToGame(BuildContext context, List<VocabularyWord> words) {
    final first = words.first;
    switch (widget.gameMode) {
      case GameMode.wordScramble:
        AppNavigator.pushPage(
          context,
          AppPage<void>(
            name: 'game/word-scramble',
            builder: (_) => WordScrambleScreen(word: first.spelling),
          ),
          replace: true,
        );
      case GameMode.dictation:
        AppNavigator.pushPage(
          context,
          AppPage<void>(
            name: 'game/dictation',
            builder: (_) => DictationQuizScreen(targetWord: first.spelling),
          ),
          replace: true,
        );
      case GameMode.bossBattle:
        AppNavigator.pushPage(
          context,
          AppPage<void>(
            name: 'game/boss-battle',
            builder: (_) => BossBattleScreen(
              questions: words
                  .map((w) => {'word': w.spelling, 'translation': w.meaning})
                  .toList(),
            ),
          ),
          replace: true,
        );
    }
  }
}

class GameLauncherUnavailable extends StatelessWidget {
  const GameLauncherUnavailable({super.key, required this.reason});

  final GameLauncherUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final message = switch (reason) {
      GameLauncherUnavailableReason.missingDependency =>
        'Vocabulary is unavailable for this game.',
      GameLauncherUnavailableReason.emptyInventory =>
        'Save at least one vocabulary word before playing.',
      GameLauncherUnavailableReason.loadFailure =>
        'Vocabulary could not be loaded for this game.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Game unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_books_outlined, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
