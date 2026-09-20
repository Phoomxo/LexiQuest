import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/flashcard_mode_adapter.dart';
import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/definition_quiz_mode_adapter.dart';
import '../features/learning/application/lesson_mode_registry.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/application/matching_mode_adapter.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/application/session_configuration_policy.dart';
import '../features/learning/application/typed_recall_mode_adapter.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/learning_repository.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/session_configuration_sheet.dart';
import '../features/learning/presentation/handwriting_scratchpad_route.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/learning_packs/domain/learning_pack.dart';
import '../navigation/app_routes.dart';
import '../services/local_reading_catalog.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'associative_reading_launcher_screen.dart';
import 'cefr_article_reader_screen.dart';
import 'local_reading_library_screen.dart';
import 'definition_quiz_screen.dart';
import 'dictation_quiz_screen.dart';
import 'fill_in_the_blanks_screen.dart';
import 'quiz_screen.dart';
import 'matching_mode_screen.dart';
import 'pair_matching_learn_screen.dart';
import 'reviewed_sentence_scramble_loader.dart';
import 'shadowing_challenge_screen.dart';
import 'speak_to_text_screen.dart';
import 'srs_flashcards_screen.dart';
import 'word_scramble_screen.dart';

class ChooseModeScreen extends StatefulWidget {
  const ChooseModeScreen({
    super.key,
    this.featureRegistry,
    this.lessonModes,
    this.sessionConfigurationPolicy = const SessionConfigurationPolicy(),
    this.leadingCards = const <Widget>[],
    this.secondaryCards = const <Widget>[],
  });

  final FeatureRegistry? featureRegistry;
  final LessonModeRegistry? lessonModes;
  final SessionConfigurationPolicy sessionConfigurationPolicy;
  final List<Widget> leadingCards;
  final List<Widget> secondaryCards;

  @override
  State<ChooseModeScreen> createState() => _ChooseModeScreenState();
}

class _ChooseModeScreenState extends State<ChooseModeScreen> {
  bool _openingMode = false;

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final features = widget.featureRegistry ?? dependencies?.features;
    final modes = widget.lessonModes ?? dependencies?.lessonModes;
    final matching = modes?.resolve(LessonMode.matching);
    final typedRecall = modes?.resolveTypedRecall();
    final dictation = modes?.resolve(LessonMode.dictation);
    final speaking = modes?.resolve(LessonMode.speaking);
    final shadowing = modes?.resolve(LessonMode.shadowing);
    final cefrReading = modes?.resolve(LessonMode.cefrReading);
    final sentenceScramble = modes?.resolve(LessonMode.sentenceScramble);
    final wordScramble = modes?.resolve(LessonMode.wordScramble);
    final handwriting = modes?.resolve(LessonMode.handwritingScratchpad);
    final tiles = <_LearningTile>[
      if (features?.isVisible(Feature.quiz) == true && handwriting != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/handwriting-scratchpad'),
          glossary: NavigationGlossary.require(
            'home/learn/handwriting-scratchpad',
          ),
          onTap: () => _openScratchpad(context),
        ),
      if (features?.isVisible(Feature.reading) == true)
        _LearningTile(
          key: const ValueKey<String>('home/learn/associative-reading'),
          glossary: NavigationGlossary.require(
            'home/learn/associative-reading',
          ),
          onTap: () => _openMode(
            context,
            LessonMode.associativeReading,
            (_, _, configuration, revalidateConfiguration) =>
                AssociativeReadingLauncherScreen(
                  sessionConfiguration: configuration,
                  revalidateSessionConfiguration: revalidateConfiguration,
                ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz'),
          glossary: NavigationGlossary.require('home/learn/quiz'),
          onTap: () => _openMode(
            context,
            LessonMode.meaningQuiz,
            (_, adapter, configuration, _) => QuizScreen(
              modeAdapter: adapter as MeaningQuizModeAdapter,
              sessionConfiguration: configuration,
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true && typedRecall != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/typed-recall'),
          glossary: NavigationGlossary.require('home/learn/quiz/typed-recall'),
          onTap: () => _openMode(
            context,
            LessonMode.typedRecall,
            (_, adapter, configuration, _) => QuizScreen.typedRecall(
              modeAdapter: adapter as TypedRecallModeAdapter,
              sessionConfiguration: configuration,
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true && matching != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/matching'),
          glossary: NavigationGlossary.require('home/learn/quiz/matching'),
          onTap: () => _openMode(
            context,
            LessonMode.matching,
            (_, adapter, configuration, _) => MatchingModeScreen(
              modeAdapter: adapter as MatchingModeAdapter,
              sessionConfiguration: configuration,
              timeLimit: configuration.timing.timedLimit,
              showCountdown: !configuration.timing.isUntimedAlternative,
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/cloze'),
          glossary: NavigationGlossary.require('home/learn/quiz/cloze'),
          onTap: () => _openMode(
            context,
            LessonMode.cloze,
            (_, adapter, configuration, _) => FillInTheBlanksScreen(
              modeAdapter: adapter as ClozeModeAdapter,
              sessionConfiguration: configuration,
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/definition'),
          glossary: NavigationGlossary.require('home/learn/quiz/definition'),
          onTap: () => _openMode(
            context,
            LessonMode.definitionQuiz,
            (_, adapter, configuration, _) => DefinitionQuizScreen(
              modeAdapter: adapter as DefinitionQuizModeAdapter,
              sessionConfiguration: configuration,
            ),
          ),
        ),
      if (features?.isVisible(Feature.srs) == true)
        _LearningTile(
          key: const ValueKey<String>('home/learn/srs'),
          glossary: NavigationGlossary.require('home/learn/srs'),
          onTap: () => _openMode(
            context,
            LessonMode.flashcard,
            (_, adapter, configuration, _) => SrsFlashcardsScreen(
              modeAdapter: adapter as FlashcardModeAdapter,
              sessionConfiguration: configuration,
            ),
          ),
        ),
      if (features?.isVisible(Feature.reading) == true && cefrReading != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/reading/cefr'),
          glossary: NavigationGlossary.require('home/learn/reading/cefr'),
          onTap: () => _openReadingLibrary(
            context,
            () => _openMode(context, LessonMode.cefrReading, (
              _,
              adapter,
              configuration,
              _,
            ) {
              final cefrAdapter = adapter as CefrReadingModeAdapter;
              return NativeVocabularyLessonModeLoader(
                sessionConfiguration: configuration,
                isQuestionAvailable: (question) {
                  try {
                    cefrAdapter.requireCanonicalCefrLevel(
                      question.word.cefrLevel,
                    );
                    return true;
                  } on StateError {
                    return false;
                  }
                },
                builder: (_, session, question) => CefrArticleReaderScreen(
                  title: LocalReadingCatalog.forLevel(
                    question.word.cefrLevel!,
                  ).title,
                  contentNotice: LocalReadingCatalog.notice,
                  content:
                      '${LocalReadingCatalog.forLevel(question.word.cefrLevel!).text}\n\n'
                      '${LocalReadingCatalog.forLevel(question.word.cefrLevel!).reflection}\n\n'
                      '${question.word.spelling} means ${question.word.meaning}.',
                  cefrLevel: cefrAdapter.requireCanonicalCefrLevel(
                    question.word.cefrLevel,
                  ),
                  ownerId: session.ownerId,
                  sessionId: session.id,
                  wordId: question.word.id,
                  modeAdapter: cefrAdapter,
                ),
              );
            }),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true && dictation != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/dictation'),
          glossary: NavigationGlossary.require('home/learn/quiz/dictation'),
          onTap: () => _openMode(
            context,
            LessonMode.dictation,
            (_, adapter, configuration, _) => NativeVocabularyLessonModeLoader(
              sessionConfiguration: configuration,
              builder: (_, session, question) => DictationQuizScreen(
                targetWord: question.word.spelling,
                ownerId: session.ownerId,
                sessionId: session.id,
                wordId: question.word.id,
                modeAdapter: adapter as DictationModeAdapter,
              ),
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true && sentenceScramble != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/sentence-scramble'),
          glossary: NavigationGlossary.require(
            'home/learn/quiz/sentence-scramble',
          ),
          onTap: () => _openMode(
            context,
            LessonMode.sentenceScramble,
            (_, adapter, configuration, _) => NativeVocabularyLessonModeLoader(
              sessionConfiguration: configuration,
              builder: (_, session, question) => ReviewedSentenceScrambleLoader(
                session: session,
                modeAdapter: adapter as SentenceScrambleModeAdapter,
              ),
            ),
          ),
        ),
      if (features?.isVisible(Feature.quiz) == true && wordScramble != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/quiz/word-scramble'),
          glossary: NavigationGlossary.require('home/learn/quiz/word-scramble'),
          onTap: () => _openMode(
            context,
            LessonMode.wordScramble,
            (_, adapter, configuration, _) => NativeVocabularyLessonModeLoader(
              sessionConfiguration: configuration,
              builder: (_, session, question) => WordScrambleScreen(
                word: question.word.spelling,
                meaning: question.word.meaning,
                partOfSpeech: question.word.partOfSpeech,
                ownerId: session.ownerId,
                sessionId: session.id,
                wordId: question.word.id,
                modeAdapter: adapter as WordScrambleModeAdapter,
              ),
            ),
          ),
        ),
      if (features?.isVisible(Feature.speechPractice) == true &&
          speaking != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/speech/speaking'),
          glossary: NavigationGlossary.require('home/learn/speech/speaking'),
          onTap: () => _openMode(
            context,
            LessonMode.speaking,
            (_, adapter, configuration, _) => NativeVocabularyLessonModeLoader(
              sessionConfiguration: configuration,
              builder: (_, session, question) => SpeakToTextScreen(
                correctWord: question.word.spelling,
                ownerId: session.ownerId,
                sessionId: session.id,
                wordId: question.word.id,
                modeAdapter: adapter as SpeakingModeAdapter,
              ),
            ),
          ),
        ),
      if (features?.isVisible(Feature.speechPractice) == true &&
          shadowing != null)
        _LearningTile(
          key: const ValueKey<String>('home/learn/speech/shadowing'),
          glossary: NavigationGlossary.require('home/learn/speech/shadowing'),
          onTap: () => _openMode(
            context,
            LessonMode.shadowing,
            (_, adapter, configuration, _) => NativeVocabularyLessonModeLoader(
              sessionConfiguration: configuration,
              builder: (_, session, question) => ShadowingChallengeScreen(
                referenceSentence: question.word.spelling,
                ownerId: session.ownerId,
                sessionId: session.id,
                wordId: question.word.id,
                modeAdapter: adapter as ShadowingModeAdapter,
              ),
            ),
          ),
        ),
    ];
    const groups = <String, List<String>>{
      'จำคำศัพท์': [
        'home/learn/quiz',
        'home/learn/quiz/typed-recall',
        'home/learn/quiz/matching',
        'home/learn/quiz/definition',
        'home/learn/srs',
        'home/learn/quiz/word-scramble',
        'home/learn/handwriting-scratchpad',
      ],
      'อ่านและประโยค': [
        'home/learn/associative-reading',
        'home/learn/quiz/cloze',
        'home/learn/reading/cefr',
        'home/learn/quiz/sentence-scramble',
      ],
      'ฟังและพูด': [
        'home/learn/quiz/dictation',
        'home/learn/speech/speaking',
        'home/learn/speech/shadowing',
      ],
    };
    _LearningTile? starter;
    if (dependencies?.learning != null &&
        dependencies?.createLessonController != null) {
      for (final candidate in const {
        'home/learn/quiz': LessonMode.meaningQuiz,
        'home/learn/srs': LessonMode.flashcard,
        'home/learn/associative-reading': LessonMode.associativeReading,
      }.entries) {
        if (modes?.resolve(candidate.value) == null ||
            (candidate.value == LessonMode.associativeReading &&
                typedRecall == null)) {
          continue;
        }
        for (final tile in tiles) {
          if (tile.glossary.id == candidate.key) starter = tile;
        }
        if (starter != null) break;
      }
    }
    final visibleGroups = groups.entries
        .where(
          (group) =>
              tiles.any((tile) => group.value.contains(tile.glossary.id)),
        )
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('เรียน')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              key: const ValueKey('learning-menu-scroll'),
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                8,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in widget.leadingCards)
                    _supplementaryCard(context, card),
                  if (starter != null) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'เริ่มฝึกสั้น ๆ',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(_modeDescription(starter.glossary.id)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey('learn-starter'),
                              onPressed: _openingMode ? null : starter.onTap,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(
                                'เริ่ม${starter.glossary.shortThaiLabel}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (widget.secondaryCards.isNotEmpty) ...[
                    Semantics(
                      header: true,
                      child: Text(
                        'วันนี้และแผนเรียน',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final card in widget.secondaryCards)
                      _supplementaryCard(context, card),
                    const SizedBox(height: 12),
                  ],
                  for (final group in visibleGroups) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        top: group == visibleGroups.first ? 8 : 24,
                        bottom: 12,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          group.key,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    _LearningChoiceGrid(
                      tiles: [
                        for (final id in group.value)
                          for (final tile in tiles)
                            if (tile.glossary.id == id) tile,
                      ],
                    ),
                  ],
                  if (tiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('ยังไม่มีกิจกรรมที่เปิดใช้งาน'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _supplementaryCard(BuildContext context, Widget card) => CardTheme(
    data: Theme.of(context).cardTheme.copyWith(margin: EdgeInsets.zero),
    child: Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
  );

  Future<void> _openScratchpad(BuildContext context) async {
    if (_openingMode) return;
    _openingMode = true;
    try {
      final dependencies = AppDependenciesScope.maybeOf(context);
      final database = dependencies?.database;
      final registration = dependencies?.lessonModes?.resolve(
        LessonMode.handwritingScratchpad,
      );
      if (database == null ||
          registration == null ||
          dependencies?.features.isEnabled(Feature.quiz) != true) {
        return;
      }
      final owners = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).get();
      if (!context.mounted ||
          owners.length != 1 ||
          dependencies?.features.isEnabled(Feature.quiz) != true) {
        return;
      }
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: registration.routeName,
          builder: (_) => HandwritingScratchpadRoute(ownerId: owners.single.id),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กระดานฝึกเขียนยังไม่พร้อมใช้งาน')),
        );
      }
    } finally {
      _openingMode = false;
    }
  }

  Future<void> _openReadingLibrary(
    BuildContext context,
    VoidCallback onVocabularyPractice,
  ) async {
    final registry =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.features;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'home/learn/reading/library',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.reading,
          registry: registry,
          builder: (_) => LocalReadingLibraryScreen(
            onVocabularyPractice: onVocabularyPractice,
          ),
        ),
      ),
    );
  }

  Future<void> _openMode(
    BuildContext context,
    LessonMode mode,
    Widget Function(
      BuildContext context,
      LessonModeAdapter adapter,
      SessionConfiguration configuration,
      SessionConfigurationRevalidator revalidateConfiguration,
    )
    builder,
  ) async {
    if (_openingMode) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final modes = widget.lessonModes ?? dependencies?.lessonModes;
    final registration = modes?.resolve(mode);
    if (registration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหมดการเรียนนี้ยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    if (mode == LessonMode.flashcard &&
        registration.adapter is! FlashcardModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหมดทบทวนแบบเว้นระยะยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    final typedRecall = modes?.resolveTypedRecall();
    if (mode == LessonMode.associativeReading && typedRecall == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหมดนึกคำแล้วพิมพ์ยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    if (mode == LessonMode.meaningQuiz &&
        registration.adapter is! MeaningQuizModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('แบบทดสอบจากคลังคำศัพท์ยังไม่พร้อมใช้งาน'),
        ),
      );
      return;
    }
    if (mode == LessonMode.typedRecall &&
        registration.adapter is! TypedRecallModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหมดนึกคำแล้วพิมพ์ยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    if (mode == LessonMode.definitionQuiz &&
        registration.adapter is! DefinitionQuizModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กิจกรรมเลือกคำจากคำอธิบายยังไม่พร้อมใช้งาน'),
        ),
      );
      return;
    }
    if (mode == LessonMode.cloze && registration.adapter is! ClozeModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กิจกรรมเติมคำในประโยคยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    if (mode == LessonMode.matching &&
        registration.adapter is! MatchingModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กิจกรรมจับคู่คำศัพท์ยังไม่พร้อมใช้งาน')),
      );
      return;
    }
    final features = widget.featureRegistry ?? dependencies?.features;
    if (features?.isEnabled(registration.feature) != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โหมดการเรียนนี้ไม่พร้อมใช้งานแล้ว')),
      );
      return;
    }
    setState(() => _openingMode = true);
    try {
      if (mode == LessonMode.matching &&
          (registration.adapter as MatchingModeAdapter).internalPairMatching &&
          dependencies?.learning != null &&
          dependencies?.activeOwnerIdentities != null) {
        final owner = await dependencies!.activeOwnerIdentities!
            .requireSingleActiveOwnerId();
        final saved = await dependencies.learning!.loadActivityRecovery(
          activityType: 'matching',
          ownerId: owner,
        );
        // Legacy checkpoints retain the existing configuration and renderer.
        if (saved == null || saved.checkpoint?.state['schemaVersion'] == 6) {
          if (!context.mounted) return;
          await AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: registration.routeName,
              builder: (_) => ProductionFeatureGate(
                feature: Feature.quiz,
                registry: features,
                builder: (_) =>
                    PairMatchingLearnScreen(dependencies: dependencies),
              ),
            ),
          );
          return;
        }
      }
      final configurationContext = await _loadConfigurationContext(
        dependencies,
        mode,
      );
      if (!context.mounted) return;
      final configuration = await showSessionConfigurationSheet(
        context: context,
        registration: registration,
        policy: widget.sessionConfigurationPolicy,
        limits: configurationContext.limits,
        ownerId: configurationContext.ownerId,
        packs: configurationContext.packs,
        initialConfiguration: configurationContext.initialConfiguration,
        initialResetRequired: configurationContext.initialResetRequired,
        initialResetCanUseDefaults:
            configurationContext.protocolResetRequired == null,
      );
      if (configuration == null || !context.mounted) return;

      var candidate = configuration;
      var recovery = configurationContext.recovery;
      final recoveryConfiguration = recovery?.session.sessionConfiguration;
      if (recovery != null && recoveryConfiguration != candidate) {
        final canDiscard = recovery.session.state == 'active';
        if (recoveryConfiguration == null && !canDiscard) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.tampered,
            'The terminal saved session has no reconstructible configuration.',
          );
        }
        final decision = await showSessionConfigurationRecoveryPrompt(
          context: context,
          canResume: recoveryConfiguration != null,
          canDiscard: canDiscard,
        );
        if (decision == null || !context.mounted) return;
        if (decision == SessionConfigurationRecoveryDecision.resume) {
          candidate = recoveryConfiguration!;
        } else {
          final learning = dependencies?.learning;
          if (learning == null || recovery.session.state != 'active') {
            throw const SessionConfigurationResetRequired(
              SessionConfigurationResetReason.tampered,
              'The saved session cannot be discarded safely.',
            );
          }
          await learning.abandonSession(
            ownerId: recovery.session.ownerId,
            sessionId: recovery.session.id,
            abandonedAtUtc: learning.nowUtc(),
          );
          recovery = null;
        }
      }

      Future<SessionConfiguration> revalidateConfiguration(
        SessionConfiguration candidate,
      ) async {
        final currentDependencies = AppDependenciesScope.maybeOf(context);
        final currentModes =
            widget.lessonModes ?? currentDependencies?.lessonModes;
        final currentRegistration = currentModes?.resolve(mode);
        final currentFeatures =
            widget.featureRegistry ?? currentDependencies?.features;
        if (currentRegistration == null ||
            !identical(currentRegistration.adapter, registration.adapter) ||
            currentFeatures?.isEnabled(registration.feature) != true) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.modeUnavailable,
          );
        }
        final currentContext = await _loadConfigurationContext(
          currentDependencies,
          mode,
        );
        final protocolResetRequired = currentContext.protocolResetRequired;
        if (protocolResetRequired != null) throw protocolResetRequired;
        return widget.sessionConfigurationPolicy.revalidate(
          configuration: candidate,
          registration: currentRegistration,
          limits: currentContext.limits,
          ownerId: currentContext.ownerId,
          availablePackIdentities: currentContext.packs.map(
            (pack) => pack.identity,
          ),
        );
      }

      final refreshed = await revalidateConfiguration(candidate);
      final store = dependencies?.sessionConfigurations;
      if (store != null && recovery == null) {
        try {
          await store.save(refreshed, updatedAtUtc: DateTime.now().toUtc());
        } on SessionConfigurationResetRequired {
          rethrow;
        } catch (_) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.tampered,
            'The validated configuration could not be persisted.',
          );
        }
      }
      if (!context.mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: registration.routeName,
          builder: (_) {
            final createController = dependencies?.createLessonController;
            if (createController == null) {
              return ProductionFeatureGate(
                feature: registration.feature,
                registry: features,
                builder: (_) => ProductionFeatureUnavailable(
                  feature: registration.feature,
                  reason: ProductionFeatureUnavailableReason.missingDependency,
                ),
              );
            }
            if (mode == LessonMode.associativeReading) {
              // The launcher can create multiple durable sessions. Each
              // pushed session owns a fresh shell/controller instance.
              return ProductionFeatureGate(
                feature: registration.feature,
                registry: features,
                builder: (_) => builder(
                  context,
                  registration.adapter,
                  refreshed,
                  revalidateConfiguration,
                ),
              );
            }
            return UnifiedLessonModeHost(
              adapter: registration.adapter,
              createController: createController,
              feature: registration.feature,
              featureRegistry: features,
              learning: dependencies?.learning,
              configuration: refreshed,
              revalidateConfiguration: revalidateConfiguration,
              builder: (context) => builder(
                context,
                registration.adapter,
                refreshed,
                revalidateConfiguration,
              ),
            );
          },
        ),
      );
    } on SessionConfigurationResetRequired catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.promptMessage)));
      }
    } finally {
      if (mounted) setState(() => _openingMode = false);
    }
  }

  Future<_SessionConfigurationContext> _loadConfigurationContext(
    AppDependencies? dependencies,
    LessonMode mode,
  ) async {
    var ownerId = 'owner:local-compatibility';
    final owners = dependencies?.localOwners;
    if (owners != null) {
      try {
        ownerId = (await owners.getOrCreateActiveOwner()).id;
        SessionConfigurationPolicy.requireCanonical(ownerId, 'ownerId');
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.ownerDrift,
        );
      }
    }
    var limits = const SessionConfigurationProtocolLimits.standard();
    SessionConfiguration? initialConfiguration;
    SessionConfigurationResetRequired? protocolResetRequired;
    SessionConfigurationResetRequired? storedResetRequired;
    LearningActivityRecovery? recovery;
    final provider = dependencies?.sessionConfigurationProtocols;
    if (provider != null) {
      try {
        limits = await provider.resolveForOwner(ownerId);
      } on SessionConfigurationResetRequired catch (error) {
        protocolResetRequired = error;
      } catch (_) {
        protocolResetRequired = const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.invalidProtocol,
        );
      }
    }
    final store = dependencies?.sessionConfigurations;
    if (store != null) {
      try {
        initialConfiguration = await store.read(ownerId: ownerId, mode: mode);
      } on SessionConfigurationResetRequired catch (error) {
        storedResetRequired = error;
      } catch (_) {
        storedResetRequired = const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
    }
    if (mode == LessonMode.matching && dependencies?.learning != null) {
      try {
        recovery = await dependencies!.learning!.loadActivityRecovery(
          activityType: MatchingModeAdapter.activityType,
          ownerId: ownerId,
        );
        if (recovery?.session.state == 'completed' &&
            recovery?.checkpoint?.terminalAcknowledged == true &&
            recovery?.checkpoint?.state['summaryPresented'] == true) {
          recovery = null;
        }
        final durableConfiguration = recovery?.session.sessionConfiguration;
        if (durableConfiguration != null) {
          initialConfiguration = durableConfiguration;
          storedResetRequired = null;
        }
      } on SessionConfigurationResetRequired {
        rethrow;
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
          'The saved session configuration could not be restored.',
        );
      }
    }
    final planning = dependencies?.studyPlanning;
    if (planning == null) {
      return _SessionConfigurationContext(
        ownerId: ownerId,
        limits: limits,
        packs: const [],
        initialConfiguration: initialConfiguration,
        initialResetRequired: protocolResetRequired ?? storedResetRequired,
        protocolResetRequired: protocolResetRequired,
        recovery: recovery,
      );
    }
    late final List<SessionConfigurationPackOption> packs;
    try {
      final catalog = await planning.listPacks(LearningPackFilter());
      final pinned = limits.pinnedPackIdentities;
      packs = catalog.packs
          .where(
            (pack) => pinned.isEmpty || pinned.contains(pack.contentIdentity),
          )
          .map(
            (pack) => SessionConfigurationPackOption(
              identity: pack.contentIdentity,
              label: '${pack.title} revision ${pack.revision}',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
    return _SessionConfigurationContext(
      ownerId: ownerId,
      limits: limits,
      packs: packs,
      initialConfiguration: initialConfiguration,
      initialResetRequired: protocolResetRequired ?? storedResetRequired,
      protocolResetRequired: protocolResetRequired,
      recovery: recovery,
    );
  }
}

final class _SessionConfigurationContext {
  const _SessionConfigurationContext({
    required this.ownerId,
    required this.limits,
    required this.packs,
    required this.initialConfiguration,
    required this.initialResetRequired,
    required this.protocolResetRequired,
    required this.recovery,
  });

  final String ownerId;
  final SessionConfigurationProtocolLimits limits;
  final List<SessionConfigurationPackOption> packs;
  final SessionConfiguration? initialConfiguration;
  final SessionConfigurationResetRequired? initialResetRequired;
  final SessionConfigurationResetRequired? protocolResetRequired;
  final LearningActivityRecovery? recovery;
}

typedef NativeLessonModeScreenBuilder =
    Widget Function(
      BuildContext context,
      QuizSession session,
      QuizQuestion question,
    );
typedef NativeLessonQuestionAvailability = bool Function(QuizQuestion question);

/// Loads one repository-owned vocabulary item only after the enclosing shell
/// exists, so flag retirement owns delayed-session compensation.
class NativeVocabularyLessonModeLoader extends StatefulWidget
    implements AccessibilityModeFeedbackSurface {
  const NativeVocabularyLessonModeLoader({
    super.key,
    required this.builder,
    this.isQuestionAvailable,
    this.sessionConfiguration,
  }) : _shellFeedback = null;

  const NativeVocabularyLessonModeLoader._withFeedback({
    super.key,
    required this.builder,
    required this.isQuestionAvailable,
    required this.sessionConfiguration,
    required this._shellFeedback,
  });

  final NativeLessonModeScreenBuilder builder;
  final NativeLessonQuestionAvailability? isQuestionAvailable;
  final SessionConfiguration? sessionConfiguration;
  final Widget? _shellFeedback;

  @override
  Widget withShellFeedback(Widget? feedback) =>
      NativeVocabularyLessonModeLoader._withFeedback(
        key: key,
        builder: builder,
        isQuestionAvailable: isQuestionAvailable,
        sessionConfiguration: sessionConfiguration,
        shellFeedback: feedback,
      );

  @override
  State<NativeVocabularyLessonModeLoader> createState() =>
      _NativeVocabularyModeLoaderState();
}

class _NativeVocabularyModeLoaderState
    extends State<NativeVocabularyLessonModeLoader> {
  Future<QuizSession>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    final learning = dependencies?.learning;
    if (learning == null || lifecycle == null) {
      _load = Future<QuizSession>.error(
        StateError('native lesson session authority is unavailable'),
      );
      return;
    }
    _load = _loadSession(learning, lifecycle);
  }

  Future<QuizSession> _loadSession(
    LearningUseCases learning,
    UnifiedLessonSessionLifecycle lifecycle,
  ) async {
    List<String>? eligibleWordIds;
    final availability = widget.isQuestionAvailable;
    if (availability != null) {
      final owner = await learning.owners.getOrCreateActiveOwner();
      // Scan bounded pages instead of treating the first page as the inventory.
      // Canonical pinned admission below still rechecks owner/content identity.
      final repository = learning.repository;
      final wanted = widget.sessionConfiguration?.itemCount ?? 1;
      eligibleWordIds = <String>[];
      String? cursor;
      while (eligibleWordIds.length < wanted) {
        final candidates = repository is PagedQuizWordRepository
            ? await (repository as PagedQuizWordRepository).listQuizWordPage(
                ownerId: owner.id,
                afterId: cursor,
                limit: 100,
              )
            : await repository.listQuizWords(ownerId: owner.id, limit: 100);
        if (candidates.isEmpty) break;
        eligibleWordIds.addAll(
          canonicalQuizQuestions(candidates)
              .where(availability)
              .map((question) => question.word.id)
              .take(wanted - eligibleWordIds.length),
        );
        if (repository is! PagedQuizWordRepository || candidates.length < 100) {
          break;
        }
        final next = candidates.last.id;
        if (cursor != null && next.compareTo(cursor) <= 0) {
          throw StateError('Candidate page did not advance');
        }
        cursor = next;
      }
    }
    final session = await lifecycle.initializeSession(
      learning.startQuiz(
        limit: widget.sessionConfiguration?.itemCount ?? 1,
        pinnedWordIds: eligibleWordIds,
        sessionConfiguration: widget.sessionConfiguration,
      ),
    );
    if (!session.isEmpty &&
        widget.isQuestionAvailable?.call(session.questions.single) == false) {
      await lifecycle.abandon();
      throw StateError('native lesson content is unavailable');
    }
    return session;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuizSession>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('กิจกรรมการเรียน')),
            body: const Center(child: Text('โหมดการเรียนนี้ยังไม่พร้อมใช้งาน')),
          );
        }
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (session.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('กิจกรรมการเรียน')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.isQuestionAvailable == null
                      ? 'เพิ่มคำศัพท์ก่อนเริ่มเรียน'
                      : 'ยังไม่มีคำศัพท์ที่เข้าเงื่อนไขของกิจกรรมนี้',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final modeSurface = widget.builder(
          context,
          session,
          session.questions.single,
        );
        final feedback = widget._shellFeedback;
        if (modeSurface is AccessibilityModeFeedbackSurface) {
          return (modeSurface as AccessibilityModeFeedbackSurface)
              .withShellFeedback(feedback);
        }
        if (feedback == null) return modeSurface;
        return Column(
          children: <Widget>[
            feedback,
            Expanded(child: modeSurface),
          ],
        );
      },
    );
  }
}

class _LearningChoiceGrid extends StatelessWidget {
  const _LearningChoiceGrid({required this.tiles});

  final List<_LearningTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = MediaQuery.sizeOf(context).width;
      final columns =
          width < 360 || MediaQuery.textScalerOf(context).scale(16) >= 24
          ? 1
          : width < 840
          ? 2
          : 3;
      return Column(
        children: [
          for (var index = 0; index < tiles.length; index += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: index + columns < tiles.length ? 12 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: 12),
                      Expanded(
                        child: index + column < tiles.length
                            ? tiles[index + column]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _LearningTile extends StatelessWidget {
  const _LearningTile({super.key, required this.glossary, required this.onTap});

  final NavigationGlossaryEntry glossary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Tooltip(
        message: glossary.tooltip,
        child: MenuActionBinding(
          id: glossary.id,
          label: glossary.fullThaiLabel,
          onInvoke: onTap,
          child: Semantics(
            button: true,
            label: glossary.semanticsLabel,
            onTap: onTap,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        glossary.icon,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      glossary.shortThaiLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _modeDescription(glossary.id),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _modeDescription(String id) => switch (id) {
  'home/learn/quiz' => 'เลือกความหมายที่ถูกต้อง',
  'home/learn/quiz/typed-recall' => 'นึกคำแล้วพิมพ์คำตอบ',
  'home/learn/quiz/matching' => 'จับคู่คำกับความหมาย',
  'home/learn/quiz/definition' => 'เลือกคำให้ตรงคำอธิบาย',
  'home/learn/srs' => 'ทบทวนคำที่เคยเรียน',
  'home/learn/handwriting-scratchpad' => 'เขียนหรือพิมพ์เพื่อตรวจด้วยตนเอง',
  'home/learn/quiz/word-scramble' => 'เรียงตัวอักษรให้เป็นคำศัพท์',
  'home/learn/associative-reading' => 'อ่านแล้วฝึกคำศัพท์',
  'home/learn/quiz/cloze' => 'เลือกคำเติมช่องว่างให้ประโยคสมบูรณ์',
  'home/learn/reading/cefr' => 'ฝึกอ่านเนื้อหาตามระดับภาษา',
  'home/learn/quiz/sentence-scramble' => 'เรียงคำให้เป็นประโยคที่ถูกต้อง',
  'home/learn/quiz/dictation' => 'ฟังคำศัพท์แล้วพิมพ์สิ่งที่ได้ยิน',
  'home/learn/speech/speaking' => 'พูดคำศัพท์และตรวจข้อความที่ระบบได้ยิน',
  'home/learn/speech/shadowing' => 'ฟังต้นแบบแล้วฝึกพูดตาม',
  _ => throw StateError('Missing learning description for $id'),
};
