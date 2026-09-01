import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  test(
    'registered Thai navigation copy has no unexplained English fallback',
    () {
      final latin = RegExp(r'[A-Za-z]');
      for (final entry in NavigationGlossary.entries.values) {
        for (final value in <String>[
          entry.fullThaiLabel,
          entry.shortThaiLabel,
          entry.semanticsLabel,
          entry.tooltip,
        ]) {
          final withoutApprovedAcronyms = value
              .replaceAll('AI', '')
              .replaceAll('SRS', '')
              .replaceAll('CEFR', '');
          expect(
            latin.hasMatch(withoutApprovedAcronyms),
            isFalse,
            reason: '${entry.id}: $value',
          );
        }
      }
    },
  );

  test('approved acronyms retain canonical Thai explanatory context', () {
    expect(
      NavigationGlossary.require('drawer/ai-tutor/chat').fullThaiLabel,
      'ผู้ช่วยสอน AI',
    );
    expect(
      NavigationGlossary.require('home/learn/srs').fullThaiLabel,
      'ทบทวนแบบเว้นระยะ (SRS)',
    );
    expect(
      NavigationGlossary.require('home/learn/reading/cefr').fullThaiLabel,
      'อ่านตามระดับภาษา CEFR',
    );
  });
}
