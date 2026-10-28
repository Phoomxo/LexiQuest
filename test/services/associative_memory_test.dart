import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/local_learning_repository.dart';
import 'package:vocab_learning_app/services/associative_memory_service.dart';
import 'package:vocab_learning_app/widgets/association_dialog_widget.dart';

void main() {
  group('B2 Associative-Memory Vertical Slice Tests', () {
    late LocalLearningRepository repo;
    late AssociativeMemoryService service;

    setUp(() {
      repo = LocalLearningRepository();
      service = AssociativeMemoryService(repository: repo);
    });

    test(
      'AssociativeMemoryService retrieves curated and user prompts',
      () async {
        await service.createUserAssociation(
          ownerId: 'u1',
          wordKey: 'ephemeral',
          cueType: CueType.personalStory,
          cueText: 'My vacation in Kyoto was ephemeral.',
        );

        final prompts = await service.getPromptsForWord('u1', 'ephemeral');
        expect(prompts.length, 3); // 1 user + 2 curated
        expect(prompts.any((p) => p.cueText.contains('Kyoto')), isTrue);
      },
    );

    testWidgets('AssociationDialogWidget renders and fires creation callback', (
      WidgetTester tester,
    ) async {
      bool created = false;
      String createdText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssociationDialogWidget(
              wordKey: 'ephemeral',
              prompts: [
                AssociationRecord(
                  associationId: 'p1',
                  ownerId: 'sys',
                  wordKey: 'ephemeral',
                  cueType: CueType.synonym,
                  cueText: 'Fleeting / short-lived',
                  source: AssociationSource.curated,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              ],
              onCreate: (type, text) {
                created = true;
                createdText = text;
              },
            ),
          ),
        ),
      );

      expect(find.text('Memory Cue for "ephemeral"'), findsOneWidget);
      expect(find.text('Fleeting / short-lived'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Custom memory trigger');
      await tester.tap(find.text('Save Cue'));
      await tester.pumpAndSettle();

      expect(created, isTrue);
      expect(createdText, 'Custom memory trigger');
    });
  });
}
