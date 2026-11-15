import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

typedef BossSpellingWord = ({
  String word,
  String meaning,
  String hint,
  String? example,
  String? partOfSpeech,
  String? typo,
  String? exampleMeaning,
});

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.passedWords,
    required this.onChooseGame,
    this.onReturnPractice,
  });

  final List<BossSpellingWord> passedWords;
  final VoidCallback onChooseGame;
  final VoidCallback? onReturnPractice;

  void _review(BuildContext context, BossSpellingWord word) {
    if (ModalRoute.isCurrentOf(context) != true) return;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/spelling-stage/review',
        builder: (_) => _LastWordReview(word: word, onChooseGame: onChooseGame),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headline = Theme.of(context).textTheme.headlineSmall;
    final last = passedWords.isEmpty ? null : passedWords.last;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ผ่านด่านสะกดคำแล้ว'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('${passedWords.length} คำ', style: headline),
              const Text('ที่สะกดผ่าน'),
              const SizedBox(height: 8),
              Text(passedWords.map((word) => word.word).join(' · ')),
              const SizedBox(height: 20),
              if (last != null)
                OutlinedButton(
                  onPressed: () => _review(context, last),
                  child: const Text('ทวนคำสุดท้าย'),
                ),
              FilledButton(
                onPressed: onChooseGame,
                child: const Text('เลือกเกมอื่น'),
              ),
              if (onReturnPractice case final openPractice?)
                TextButton(
                  onPressed: openPractice,
                  child: const Text('กลับหน้าฝึกภาษา'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastWordReview extends StatelessWidget {
  const _LastWordReview({required this.word, required this.onChooseGame});

  final BossSpellingWord word;
  final VoidCallback onChooseGame;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ทวนคำสุดท้าย'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (word.partOfSpeech case final partOfSpeech?)
                Text(partOfSpeech),
              Text(word.word, style: text.headlineMedium),
              Text(word.meaning, style: text.titleLarge),
              if (word.example case final example?) ...[
                const SizedBox(height: 20),
                Text('ตัวอย่างการใช้', style: text.titleMedium),
                Text(example),
                if (word.exampleMeaning case final meaning?) Text(meaning),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onChooseGame,
                child: const Text('เลือกเกมอื่น'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('กลับไปดูผล'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
