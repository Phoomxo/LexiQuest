import 'association_record.dart';
import 'learning_record_validation.dart';

final class AssociationPrompt {
  AssociationPrompt({
    required this.promptId,
    required this.wordKey,
    required this.cueType,
    required this.cueText,
    required this.contentVersion,
  }) {
    LearningRecordValidation.identifier(promptId, 'promptId');
    LearningRecordValidation.identifier(wordKey, 'wordKey');
    LearningRecordValidation.identifier(contentVersion, 'contentVersion');
    if (cueText.trim().isEmpty || cueText.length > 500) {
      throw ArgumentError.value(
        cueText,
        'cueText',
        'must be non-empty and at most 500 characters',
      );
    }
  }

  final String promptId;
  final String wordKey;
  final AssociationCueType cueType;
  final String cueText;
  final String contentVersion;
}

abstract interface class AssociationPromptCatalog {
  List<AssociationPrompt> forWord(String wordKey);
}

final class CuratedAssociationPromptCatalog
    implements AssociationPromptCatalog {
  factory CuratedAssociationPromptCatalog.offlineDefaults() {
    return CuratedAssociationPromptCatalog({
      'ephemeral': [
        AssociationPrompt(
          promptId: 'curated-ephemeral-mist-v1',
          wordKey: 'ephemeral',
          cueType: AssociationCueType.sensory,
          cueText: 'Morning mist disappears soon after sunrise.',
          contentVersion: 'curated-v1',
        ),
        AssociationPrompt(
          promptId: 'curated-ephemeral-synonym-v1',
          wordKey: 'ephemeral',
          cueType: AssociationCueType.synonym,
          cueText: 'Brief, fleeting, and short-lived.',
          contentVersion: 'curated-v1',
        ),
      ],
      'resilient': [
        AssociationPrompt(
          promptId: 'curated-resilient-bamboo-v1',
          wordKey: 'resilient',
          cueType: AssociationCueType.sensory,
          cueText: 'Bamboo bends in a storm and rises again.',
          contentVersion: 'curated-v1',
        ),
      ],
    });
  }

  CuratedAssociationPromptCatalog(
    Map<String, List<AssociationPrompt>> promptsByWord,
  ) : _promptsByWord = Map<String, List<AssociationPrompt>>.unmodifiable(
        promptsByWord.map((wordKey, prompts) {
          LearningRecordValidation.identifier(wordKey, 'wordKey');
          if (prompts.length > 3) {
            throw ArgumentError.value(
              prompts.length,
              'prompts',
              'curated prompts are limited to three per word',
            );
          }
          if (prompts.any((prompt) => prompt.wordKey != wordKey)) {
            throw ArgumentError(
              'Every curated prompt must match its catalog word.',
            );
          }
          return MapEntry(
            wordKey,
            List<AssociationPrompt>.unmodifiable(prompts),
          );
        }),
      );

  final Map<String, List<AssociationPrompt>> _promptsByWord;

  @override
  List<AssociationPrompt> forWord(String wordKey) {
    return _promptsByWord[wordKey] ?? const <AssociationPrompt>[];
  }
}
