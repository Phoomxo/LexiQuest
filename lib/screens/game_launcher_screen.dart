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

class _GameLauncherScreenState extends State<GameLauncherScreen> {
  List<VocabularyWord>? _words;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final useCases = widget.vocabulary ??
        AppDependenciesScope.maybeOf(context)?.vocabulary;
    if (useCases == null) {
      setState(() => _error = 'ไม่สามารถเข้าถึงคลังคำศัพท์ได้');
      return;
    }
    try {
      final words = await useCases.getGameWords(limit: 10);
      if (!mounted) return;
      if (words.isEmpty) {
        setState(() => _error = 'ยังไม่มีคำศัพท์ในคลัง — เพิ่มคำศัพท์ก่อนเล่นเกม');
        return;
      }
      setState(() => _words = words);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'โหลดคำศัพท์ไม่สำเร็จ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    final error = _error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('เกม')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.library_books_outlined, size: 48),
                const SizedBox(height: 16),
                Text(error, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('กลับ'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (words == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Content is ready — launch the game.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateToGame(context, words);
    });
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
