import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_reaction_selector.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_reaction.dart';

void main() {
  const selector = AdventureReactionSelector();

  test('v1 deterministically selects every committed reaction trigger', () {
    const triggers = <AdventureReactionTrigger>[
      AdventureReactionTrigger.missionReady,
      AdventureReactionTrigger.independentCorrect,
      AdventureReactionTrigger.guidedCorrect,
      AdventureReactionTrigger.incorrect,
      AdventureReactionTrigger.skipped,
      AdventureReactionTrigger.resumed,
      AdventureReactionTrigger.completed,
      AdventureReactionTrigger.rewardPending,
      AdventureReactionTrigger.recovered,
    ];

    for (final trigger in triggers) {
      final first = selector.select(
        catalogVersion: AdventureReactionCatalog.v1Version,
        trigger: trigger,
        variantSeed: 7,
      );
      final replay = selector.select(
        catalogVersion: AdventureReactionCatalog.v1Version,
        trigger: trigger,
        variantSeed: 7,
      );

      expect(first, isNotNull, reason: trigger.name);
      expect(replay?.reactionId, first?.reactionId, reason: trigger.name);
      expect(first?.trigger, trigger);
      expect(first?.catalogVersion, AdventureReactionCatalog.v1Version);
    }
  });

  test('variant seed is stable and can select another reviewed variant', () {
    final first = selector.select(
      catalogVersion: AdventureReactionCatalog.v1Version,
      trigger: AdventureReactionTrigger.incorrect,
      variantSeed: 0,
    );
    final second = selector.select(
      catalogVersion: AdventureReactionCatalog.v1Version,
      trigger: AdventureReactionTrigger.incorrect,
      variantSeed: 1,
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.reactionId, isNot(second!.reactionId));
    expect(
      selector
          .select(
            catalogVersion: AdventureReactionCatalog.v1Version,
            trigger: AdventureReactionTrigger.incorrect,
            variantSeed: 0,
          )
          ?.reactionId,
      first.reactionId,
    );
  });

  test('unsupported version and invalid seed fail closed', () {
    expect(
      selector.select(
        catalogVersion: '99.0.0',
        trigger: AdventureReactionTrigger.completed,
        variantSeed: 0,
      ),
      isNull,
    );
    expect(
      selector.select(
        catalogVersion: AdventureReactionCatalog.v1Version,
        trigger: AdventureReactionTrigger.completed,
        variantSeed: -1,
      ),
      isNull,
    );
  });

  test('reviewed catalog has complete bilingual accessible copy', () {
    const catalog = AdventureReactionCatalog.v1;

    expect(
      catalog.reactions.map((reaction) => reaction.trigger).toSet(),
      AdventureReactionTrigger.values.toSet(),
    );
    for (final reaction in catalog.reactions) {
      expect(reaction.copy.th.trim(), isNotEmpty, reason: reaction.reactionId);
      expect(reaction.copy.en.trim(), isNotEmpty, reason: reaction.reactionId);
      expect(
        reaction.accessibilityText.th.trim(),
        isNotEmpty,
        reason: reaction.reactionId,
      );
      expect(
        reaction.accessibilityText.en.trim(),
        isNotEmpty,
        reason: reaction.reactionId,
      );
      expect(
        AdventureReactionContentReview.findViolations(reaction),
        isEmpty,
        reason: reaction.reactionId,
      );
    }
  });

  test('content review rejects shame coercion and false mastery claims', () {
    expect(
      AdventureReactionContentReview.reviewCopy(
        th: 'ถ้าหยุดจะถูกลงโทษ',
        en: 'You failed. Continue or lose your reward.',
      ),
      containsAll(<AdventureReactionContentViolation>{
        AdventureReactionContentViolation.shame,
        AdventureReactionContentViolation.coercion,
      }),
    );
    expect(
      AdventureReactionContentReview.reviewCopy(
        th: 'คุณเชี่ยวชาญภาษาอังกฤษแล้ว',
        en: 'You have mastered English.',
      ),
      contains(AdventureReactionContentViolation.falseMastery),
    );
  });

  test(
    'architecture exposes no AI free-text relationship or punishment state',
    () {
      final sources = <String>[
        'lib/features/adventure/domain/adventure_reaction.dart',
        'lib/features/adventure/application/adventure_reaction_selector.dart',
        'lib/features/adventure/presentation/widgets/adventure_companion_panel.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');

      for (final forbiddenImport in <String>[
        'features/ai_tutor',
        'features/gemini',
        'openai_',
        'anthropic_',
      ]) {
        expect(sources, isNot(contains(forbiddenImport)));
      }
      for (final forbiddenField in <String>[
        'freeText',
        'free_text',
        'relationshipScore',
        'relationship_score',
        'punishmentState',
        'punishment_state',
      ]) {
        expect(sources, isNot(contains(forbiddenField)));
      }
      expect(sources, isNot(contains('factory AdventureReaction.fromJson')));
      expect(sources, isNot(contains('.purchase(')));
      expect(sources, isNot(contains('.equip(')));
      expect(sources, isNot(contains('.grantCoins(')));
    },
  );
}
