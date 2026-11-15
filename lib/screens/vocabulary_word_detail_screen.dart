import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'add_vocab_screen.dart';
import 'dictation_quiz_screen.dart';
import 'phonetic_explorer_screen.dart';

class VocabularyWordDetailScreen extends StatelessWidget {
  const VocabularyWordDetailScreen({
    super.key,
    required this.word,
    required this.categoryName,
    required this.vocabulary,
    required this.scope,
    this.bookmarkedOnly = false,
    this.returnLabel = 'กลับชุดคำ',
  });

  final VocabularyWord word;
  final String categoryName;
  final VocabularyUseCases vocabulary;
  final AppDependencies? scope;
  final bool bookmarkedOnly;
  final String returnLabel;

  bool get _speechVisible =>
      (scope?.fieldFeatures.isVisible(FieldFeature.speechPractice) ?? true) &&
      (scope?.features.isVisible(Feature.speechPractice) ?? true);

  void _open(
    BuildContext context,
    String route,
    Widget Function(VocabularyWord) buildActivity, {
    bool speech = true,
  }) {
    if (ModalRoute.isCurrentOf(context) != true) return;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'vocabulary/word/$route',
        builder: (_) => OwnedVocabularyWordRoute(
          word: word,
          vocabulary: vocabulary,
          scope: scope,
          bookmarkedOnly: bookmarkedOnly,
          builder: (_, current) => !speech || _speechVisible
              ? KeyedSubtree(
                  key: ValueKey(speech ? current.localRevision : current.id),
                  child: buildActivity(current),
                )
              : const _WordUnavailable(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OwnedVocabularyWordRoute(
    word: word,
    vocabulary: vocabulary,
    scope: scope,
    bookmarkedOnly: bookmarkedOnly,
    builder: (context, current) {
      final theme = Theme.of(context);
      final station =
          current.normalizedSpelling == 'station' && current.meaning == 'สถานี';
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(context, categoryName),
        ),
        body: AdaptiveContentPane(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(current.spelling, style: theme.textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  station
                      ? '/ˈsteɪʃən/ · ${current.partOfSpeech}'
                      : current.partOfSpeech,
                ),
                const SizedBox(height: 20),
                Text(current.meaning, style: theme.textTheme.headlineSmall),
                if (station) ...[
                  const SizedBox(height: 12),
                  const Text('Meet me at the station.'),
                  const Text('มาเจอกันที่สถานีนะ'),
                ],
                const SizedBox(height: 20),
                if (_speechVisible) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _open(
                      context,
                      'phonetic',
                      (item) => PhoneticExplorerScreen(
                        targetWord: item.spelling,
                        voice: scope?.voice,
                      ),
                    ),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('ฟังและฝึกพูด'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _open(
                      context,
                      'dictation',
                      (item) => DictationQuizScreen(
                        targetWord: item.spelling,
                        meaning: item.meaning,
                        partOfSpeech: item.partOfSpeech,
                        categoryName: categoryName,
                        voice: scope?.voice,
                        autoPlay: false,
                      ),
                    ),
                    icon: const Icon(Icons.hearing_outlined),
                    label: const Text('ฝึกฟังแล้วเขียน'),
                  ),
                ],
                OutlinedButton(
                  onPressed: () => _open(
                    context,
                    'edit',
                    (item) => AddWordScreen(
                      categoryId: item.categoryId,
                      categoryName: categoryName,
                      vocabulary: vocabulary,
                      expectedOwnerId: item.ownerId,
                      word: item,
                    ),
                    speech: false,
                  ),
                  child: const Text('แก้ไขคำ'),
                ),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(returnLabel),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class OwnedVocabularyWordRoute extends StatefulWidget {
  const OwnedVocabularyWordRoute({
    super.key,
    required this.word,
    required this.vocabulary,
    required this.scope,
    required this.builder,
    this.bookmarkedOnly = false,
  });

  final VocabularyWord word;
  final VocabularyUseCases vocabulary;
  final AppDependencies? scope;
  final Widget Function(BuildContext, VocabularyWord) builder;
  final bool bookmarkedOnly;

  @override
  State<OwnedVocabularyWordRoute> createState() => _OwnedWordRouteState();
}

class _OwnedWordRouteState extends State<OwnedVocabularyWordRoute> {
  StreamSubscription<void>? _owners;
  StreamSubscription<List<VocabularyWord>>? _words;
  VocabularyWord? _current;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _owners = widget.scope?.watchLocalOwnerWrites()?.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
    unawaited(_openWord());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!identical(AppDependenciesScope.maybeOf(context), widget.scope)) {
      _invalidate();
    }
  }

  Future<void> _openWord() async {
    final word = widget.word;
    final scope = widget.scope;
    try {
      if ((widget.bookmarkedOnly || _owners != null) &&
          await scope?.readActiveOwnerId() != word.ownerId) {
        _invalidate();
        return;
      }
      if (!mounted || _unavailable) return;
      final words = widget.bookmarkedOnly
          ? widget.vocabulary.watchBookmarkedWords(
              expectedOwnerId: word.ownerId,
            )
          : widget.vocabulary.watchWords(
              word.categoryId,
              expectedOwnerId: word.ownerId,
            );
      _words = words.listen((words) {
        if (!mounted || _unavailable) return;
        final current = words
            .where(
              (item) =>
                  item.id == word.id && item.categoryId == word.categoryId,
            )
            .firstOrNull;
        if (current == null) {
          _invalidate();
          return;
        }
        setState(() => _current = current);
      }, onError: (Object _) => _invalidate());
    } catch (_) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted || _unavailable) return;
    setState(() {
      _current = null;
      _unavailable = true;
    });
  }

  @override
  void dispose() {
    unawaited(_owners?.cancel());
    unawaited(_words?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const _WordUnavailable();
    if (_current case final word?) return widget.builder(context, word);
    return Scaffold(
      appBar: AppBar(title: const Text('คำศัพท์')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _WordUnavailable extends StatelessWidget {
  const _WordUnavailable();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('คำศัพท์')),
    body: const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('คำนี้ไม่พร้อมใช้งาน กรุณากลับไปเลือกคำใหม่'),
      ),
    ),
  );
}
