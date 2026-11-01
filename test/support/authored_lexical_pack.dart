import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

LearningPack authoredLexicalPack({
  String version = '1.0.0',
  bool includeDefinitions = true,
  bool duplicateSpelling = false,
  String language = 'en',
  bool includeChoiceQuestions = true,
}) => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-definition-deck',
      version: version,
      title: 'Synthetic authored definition deck',
      objectives: ['Distinguish two synthetic animal definitions'],
      cefrLevel: 'A1',
      language: language,
      meaningLanguage: 'th',
      provenance: const LearningPackProvenance(
        author: 'Synthetic test author',
        source: 'Synthetic local test fixture',
        license: 'Synthetic test only',
        attribution: 'No real publisher or participant',
      ),
    ),
    entries: [
      for (final code in const ['cat', 'dog'])
        LearningPackEntry(
          code: code,
          spelling: duplicateSpelling ? 'cat' : code,
          meaning: code == 'cat' ? 'แมว' : 'สุนัข',
          partOfSpeech: 'noun',
          definition: !includeDefinitions
              ? null
              : code == 'cat'
              ? 'A small animal that meows.'
              : 'An animal that barks.',
          hint: code == 'cat' ? 'Think of meowing.' : 'Think of barking.',
          strategy: 'Read the entire authored definition.',
          definitionQuestion: !includeDefinitions || !includeChoiceQuestions
              ? null
              : LearningPackDefinitionQuestion(
                  correctOptionCode: code,
                  options: [
                    for (final option in const ['cat', 'dog'])
                      LearningPackDefinitionOption(
                        code: option,
                        entryCode: option,
                        contrastiveExplanation: option == code
                            ? null
                            : '$option makes a different sound.',
                      ),
                  ],
                ),
        ),
    ],
  ),
);
