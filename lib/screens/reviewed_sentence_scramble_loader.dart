import 'package:flutter/material.dart';

import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import 'sentence_scramble_screen.dart';

/// Uses the same reviewed, revision-pinned example admission as cloze. The
/// sentence mode retains its own recreational scoring and session lifecycle.
class ReviewedSentenceScrambleLoader extends StatefulWidget {
  const ReviewedSentenceScrambleLoader({
    super.key,
    required this.session,
    required this.modeAdapter,
    this.loadLexicalWords,
  });

  final QuizSession session;
  final SentenceScrambleModeAdapter modeAdapter;
  final Future<List<VocabularyWord>> Function(Iterable<String>)?
  loadLexicalWords;

  @override
  State<ReviewedSentenceScrambleLoader> createState() =>
      _ReviewedSentenceScrambleLoaderState();
}

class _ReviewedSentenceScrambleLoaderState
    extends State<ReviewedSentenceScrambleLoader> {
  Future<String?>? _sentence;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sentence ??= _load();
  }

  @override
  void didUpdateWidget(ReviewedSentenceScrambleLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        oldWidget.loadLexicalWords != widget.loadLexicalWords) {
      _sentence = _load();
    }
  }

  Future<String?> _load() async {
    final loader =
        widget.loadLexicalWords ??
        AppDependenciesScope.maybeOf(context)?.vocabulary?.readPinnedByIds;
    final session = widget.session;
    if (loader == null || session.questions.length != 1) return null;
    final words = await loader([session.questions.single.word.id]);
    final item = const ClozeModeAdapter()
        .pinItems(
          session: session,
          lexicalWords: words.where((word) => !word.isDeleted),
        )
        .single;
    return item.question?.completeSentence;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _sentence,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final sentence = snapshot.data;
      if (snapshot.hasError || sentence == null) {
        return const Center(
          key: ValueKey('sentence-example-unavailable'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('ยังไม่มีประโยคตัวอย่างที่ผ่านการตรวจทานสำหรับคำนี้'),
          ),
        );
      }
      final session = widget.session;
      return SentenceScrambleScreen(
        targetSentence: sentence,
        translation: session.questions.single.word.meaning,
        ownerId: session.ownerId,
        sessionId: session.id,
        wordId: session.questions.single.word.id,
        modeAdapter: widget.modeAdapter,
      );
    },
  );
}
