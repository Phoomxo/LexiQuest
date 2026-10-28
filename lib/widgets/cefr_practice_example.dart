import 'package:flutter/material.dart';
import '../features/vocabulary/application/cefr_practice_examples.dart';
import '../features/vocabulary/data/cefr_vocabulary_catalog.dart';

/// Only reveal after the host has committed the relevant answer/exposure.
/// Never loads examples while recall is still independent.
class CefrPracticeExample extends StatelessWidget {
  const CefrPracticeExample({
    super.key,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    required this.cefrLevel,
    required this.revealed,
    this.catalog,
    this.showUnavailable = false,
  });
  final String spelling, meaning, partOfSpeech;
  final String? cefrLevel;
  final bool revealed, showUnavailable;
  final Future<CefrVocabularyCatalog>? catalog;

  @override
  Widget build(BuildContext context) {
    if (!revealed || cefrLevel == null) return const SizedBox.shrink();
    return FutureBuilder<CefrVocabularyCatalog>(
      future: catalog ?? CefrPracticeExamples.load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final example = data == null
            ? null
            : CefrPracticeExamples.resolve(
                data,
                spelling: spelling,
                meaning: meaning,
                partOfSpeech: partOfSpeech,
                cefrLevel: cefrLevel,
              );
        if (example == null) {
          if (!showUnavailable ||
              snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              snapshot.hasError || data?.editorialLoadFailed == true
                  ? 'ยังโหลดตัวอย่างไม่ได้'
                  : 'ยังไม่มีตัวอย่างที่ตรงกับความหมายนี้',
            ),
          );
        }
        final theme = Theme.of(context);
        return Card.outlined(
          key: const ValueKey('cefr-practice-example'),
          margin: const EdgeInsets.symmetric(vertical: 16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ตัวอย่างประกอบความหมายนี้',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  example.example,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 16),
                Text(
                  example.translation,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 12),
                Text(
                  'ตรวจภาษาเบื้องต้นด้วย AI',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
