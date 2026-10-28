import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/associative_reading_coordinator.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database.dart';
import 'package:vocab_learning_app/learning/vocabulary_mixer.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/voice/reading_voice_enrichment.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('renders coordinator state and sends stage intents', (
    tester,
  ) async {
    final database = LearningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftLearningRepository(database);
    final coordinator = AssociativeReadingCoordinator(
      repository: repository,
      reader: repository,
      contentSource: CuratedReadingContentSource(const [
        ReadingContent(
          contentId: 'a2-resilient',
          contentVersion: 'curated-v1',
          cefrLevel: 'A2',
          passage: 'Nok stays resilient when plans change.',
          targetWords: ['resilient'],
          provenance: ReadingContentProvenance.curated,
        ),
      ]),
      mixer: const VersionedVocabularyMixer(),
      idGenerator: _TestIdGenerator(),
      clock: DateTime.now,
    );
    final initial = await coordinator.start(
      const ReadingStartRequest(
        ownerId: 'owner-a',
        cefrLevel: 'A2',
        mixRequest: VocabularyMixRequest(
          dueWords: ['resilient'],
          weakWords: [],
          newWords: [],
          targetCount: 1,
          maxNewWords: 1,
          seed: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AssociativeReadingSessionScreen(
          coordinator: coordinator,
          initialState: initial,
        ),
      ),
    );

    expect(find.text('Supported Reading'), findsOneWidget);
    expect(find.textContaining('Nok stays resilient'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Cue Fading'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Recall'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'resilient');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Association'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Transfer'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'She is resilient after setbacks.',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Scheduling'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('voice failure leaves the learning stage unchanged', (
    tester,
  ) async {
    final database = LearningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftLearningRepository(database);
    final coordinator = AssociativeReadingCoordinator(
      repository: repository,
      reader: repository,
      contentSource: CuratedReadingContentSource(const [
        ReadingContent(
          contentId: 'a2-adapt',
          contentVersion: 'curated-v1',
          cefrLevel: 'A2',
          passage: 'A learner can adapt when the daily plan changes.',
          targetWords: ['adapt'],
          provenance: ReadingContentProvenance.curated,
        ),
      ]),
      mixer: const VersionedVocabularyMixer(),
      idGenerator: _TestIdGenerator(),
      clock: DateTime.now,
    );
    final initial = await coordinator.start(
      const ReadingStartRequest(
        ownerId: 'owner-a',
        cefrLevel: 'A2',
        mixRequest: VocabularyMixRequest(
          dueWords: ['adapt'],
          weakWords: [],
          newWords: [],
          targetCount: 1,
          maxNewWords: 1,
          seed: 2,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AssociativeReadingSessionScreen(
          coordinator: coordinator,
          initialState: initial,
          readingVoice: ReadingVoiceEnrichment(
            provider: _FailingVoiceProvider(),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();

    expect(find.text('Supported Reading'), findsOneWidget);
    expect(
      find.text('Voice is unavailable. Continue reading.'),
      findsOneWidget,
    );
    expect(coordinator.state?.session.currentStage.name, 'supportedReading');
  });
}

final class _TestIdGenerator implements SecureIdGenerator {
  var value = 0;

  @override
  String nextId() => 'screen-${++value}';
}

final class _FailingVoiceProvider implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    throw const VoiceFailure(
      category: VoiceFailureCategory.modelUnavailable,
      message: 'unavailable',
    );
  }

  @override
  Future<void> stop() async {}
}
