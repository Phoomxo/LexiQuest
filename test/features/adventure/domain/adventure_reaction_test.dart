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

  test('content review approves only the exact closed reviewed catalog', () {
    final approved = AdventureReactionCatalog.v1.reactions.first;

    expect(
      AdventureReactionContentReview.isApprovedScript(
        catalogVersion: approved.catalogVersion,
        reactionId: approved.reactionId,
        th: approved.copy.th,
        en: approved.copy.en,
        accessibilityTh: approved.accessibilityText.th,
        accessibilityEn: approved.accessibilityText.en,
      ),
      isTrue,
    );
    expect(
      AdventureReactionContentReview.isApprovedScript(
        catalogVersion: approved.catalogVersion,
        reactionId: approved.reactionId,
        th: approved.copy.th,
        en: 'A new but harmless sentence.',
        accessibilityTh: approved.accessibilityText.th,
        accessibilityEn: approved.accessibilityText.en,
      ),
      isFalse,
    );
    expect(
      AdventureReactionContentReview.isApprovedScript(
        catalogVersion: '99.0.0',
        reactionId: approved.reactionId,
        th: approved.copy.th,
        en: approved.copy.en,
        accessibilityTh: approved.accessibilityText.th,
        accessibilityEn: approved.accessibilityText.en,
      ),
      isFalse,
    );
  });

  test('entire Adventure tree enforces the scripted read-only boundary', () {
    final files = Directory('lib/features/adventure')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
    expect(files.length, greaterThan(20));

    final forbidden = <RegExp>[
      RegExp(
        r'(?:features/(?:ai_tutor|gemini)/|openai|anthropic|generative[_-]?ai)',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:free[_-]?text|(?:ai[_-]?)?generated[_-]?(?:copy|text|reaction))\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:relationship|affinity)[_-]?(?:score|level|state)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:punishment|penalty)[_-]?(?:score|level|state|config(?:uration)?)\b',
        caseSensitive: false,
      ),
      RegExp(r'\b(?:RewardUseCases|RewardRepository|RewardAccountWriter)\b'),
      RegExp(
        r'\.(?:purchase|equip|unequip|grantCoins|spendCoins|creditCoins|debitCoins)\s*\(',
      ),
      RegExp(r'features/rewards/(?:application|data)/'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync().replaceAll('\\', '/');
      for (final pattern in forbidden) {
        expect(
          pattern.hasMatch(source),
          isFalse,
          reason: '${file.path} matched ${pattern.pattern}',
        );
      }
    }

    final scriptedReactionFiles = <File>[
      File('lib/features/adventure/domain/adventure_reaction.dart'),
      File(
        'lib/features/adventure/application/adventure_reaction_selector.dart',
      ),
      File(
        'lib/features/adventure/presentation/widgets/'
        'adventure_companion_panel.dart',
      ),
    ];
    final promptConfiguration = RegExp(
      r'\b(?:(?:system|user)[_-]?)?prompt(?:[_-]?(?:template|config(?:uration)?))?\b',
      caseSensitive: false,
    );
    for (final file in scriptedReactionFiles) {
      expect(
        promptConfiguration.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} matched ${promptConfiguration.pattern}',
      );
    }

    final host = File(
      'lib/features/adventure/presentation/today_experience_host.dart',
    ).readAsStringSync();
    final hub = File(
      'lib/features/adventure/presentation/adventure_hub_screen.dart',
    ).readAsStringSync();
    final navigation = File(
      'lib/screens/main_navigation_screen.dart',
    ).readAsStringSync();
    expect(host, contains('AdventureReactionSelector'));
    expect(host, contains('RewardAccountReader'));
    expect(hub, contains('AdventureCompanionPanel'));
    expect(
      navigation,
      contains('rewardAccounts: dependencies.rewardAccounts!'),
    );
    expect(navigation, contains('AdventureLessonCompanionPanel'));
  });

  test('companion motion uses the M3 motion duration contract', () {
    final source = File(
      'lib/features/adventure/presentation/widgets/adventure_companion_panel.dart',
    ).readAsStringSync();

    expect(source, contains('M3Theme.motionDuration'));
    expect(source, contains('Durations.short2'));
    expect(source, isNot(contains('Duration(milliseconds: 180)')));
  });
}
