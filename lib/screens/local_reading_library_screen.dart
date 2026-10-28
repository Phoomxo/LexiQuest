import 'package:flutter/material.dart';

import '../services/local_reading_catalog.dart';
import 'cefr_article_reader_screen.dart';
import 'cefr_vocabulary_catalog_screen.dart';

/// Local reading practice does not invent a vocabulary session or CEFR result.
/// The parent production feature gate continues to own this whole subtree.
class LocalReadingLibraryScreen extends StatelessWidget {
  const LocalReadingLibraryScreen({
    super.key,
    required this.onVocabularyPractice,
  });
  final VoidCallback onVocabularyPractice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ชุดบทอ่านเริ่มต้น')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'เลือกบทอ่านของคุณ',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            LocalReadingCatalog.notice,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 28),
          Text(
            'บทอ่านตามระดับ',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          for (final level in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
            Card.outlined(
              margin: const EdgeInsets.only(bottom: 12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                title: Text(
                  '$level · ${LocalReadingCatalog.forLevel(level).title}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final selected = LocalReadingCatalog.forLevel(level);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CefrArticleReaderScreen(
                        title: selected.title,
                        content: '${selected.text}\n\n${selected.reflection}',
                        cefrLevel: selected.level,
                        contentNotice:
                            '${LocalReadingCatalog.notice}\nอ่านฝึกได้โดยไม่เปลี่ยนระดับหรือความก้าวหน้าคำศัพท์',
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'คำศัพท์และการฝึก',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(20)),
            key: const ValueKey('reading-library-vocabulary-catalog'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(
                  name: 'home/learn/reading/cefr/vocabulary',
                ),
                builder: (_) => const CefrVocabularyCatalogScreen(),
              ),
            ),
            child: const Text('คลังคำศัพท์ 5,000 คำ + ชุดเสริม C2'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(20)),
            onPressed: onVocabularyPractice,
            child: const Text('ฝึกจากคำศัพท์ที่มีระดับ'),
          ),
        ],
      ),
    );
  }
}
