import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  const expectedIds = <String>{
    'home/vocabulary',
    'home/learn',
    'home/today',
    'home/study-planning',
    'home/mastery',
    'home/weakness',
    'home/achievements',
    'home/profile',
    'drawer/rewards/shop',
    'drawer/practice/object-scanner',
    'drawer/practice/shadowing',
    'drawer/learning/ghost-duel',
    'drawer/ai-tutor/chat',
    'drawer/ai-tutor/settings',
    'drawer/export/center',
    'drawer/rewards/quests',
    'drawer/settings',
    'home/learn/associative-reading',
    'home/learn/quiz',
    'home/learn/quiz/typed-recall',
    'home/learn/quiz/matching',
    'home/learn/quiz/cloze',
    'home/learn/quiz/definition',
    'home/learn/srs',
    'home/learn/reading/cefr',
    'home/learn/quiz/dictation',
    'home/learn/quiz/sentence-scramble',
    'home/learn/quiz/word-scramble',
    'home/learn/speech/speaking',
    'home/learn/speech/shadowing',
    'today-hub-resume-action',
    'today-hub-start-recommendation',
    'today-hub-assessment-action',
    'today-hub-open-review',
    'today-hub-open-history',
    'study-planning/open-catalog',
    'study-planning/open-goals',
    'study-planning/open-learning-preferences',
    'settings/display',
    'theme-system',
    'theme-light',
    'theme-dark',
    'reduced-motion-switch',
    'settings/account',
    'settings/offline-content',
    'settings/research-consent',
    'settings/cloud-status',
    'settings/change-password',
    'settings/logout',
    'erase-local-data',
    'profile/mastery',
    'profile/srs',
    'profile/effort',
    'profile/accuracy',
    'profile/weakness',
    'profile/engagement',
    'home/today/review',
    'home/today/history',
    'research/assessment',
    'study-planning/catalog',
    'study-planning/goals',
    'study-planning/learning-preferences',
  };

  test('Thai navigation glossary is the exact immutable registered set', () {
    expect(NavigationGlossary.entries.keys.toSet(), expectedIds);
    for (final entry in NavigationGlossary.entries.values) {
      expect(entry.id, isNotEmpty);
      expect(entry.fullThaiLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.shortThaiLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.semanticsLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.tooltip.trim(), isNotEmpty, reason: entry.id);
      expect(entry.icon.codePoint, greaterThan(0), reason: entry.id);
    }
    expect(
      NavigationGlossary.mainDestinationIds.every(
        (id) => NavigationGlossary.require(id).selectedIcon != null,
      ),
      isTrue,
    );
    expect(
      NavigationGlossary.require('home/learn').fullThaiLabel,
      'การเรียนรู้',
    );
    expect(
      NavigationGlossary.require('home/learn').shortThaiLabel,
      'การเรียนรู้',
    );
  });

  test('missing registered identity fails closed without a label fallback', () {
    expect(
      () => NavigationGlossary.require('home/not-registered'),
      throwsA(isA<StateError>()),
    );
  });
}
