import 'package:flutter/material.dart';
import '../features/vocabulary/data/cefr_vocabulary_catalog.dart';

/// Read-only sense selection. The parent retains import and owner authority.
class CefrVocabularyDetailScreen extends StatelessWidget {
  const CefrVocabularyDetailScreen({
    super.key,
    required this.word,
    required this.canAdd,
  });
  final CefrCatalogWord word;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editorial = word.editorial;
    final canSelect = canAdd && word.practiceUsageNotice == null;
    final alternatives = [
      for (final i in word.selectableMeaningIndices)
        if (i != editorial?.sourceMeaningIndex) i,
    ];
    Widget meanings() => Column(
      children: [
        if (editorial?.partOfSpeechOverride != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('ชนิดคำในข้อมูลต้นทาง: ${word.sourcePartOfSpeechThai}'),
          ),
        for (final i in alternatives)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: Text(word.meanings[i]),
            trailing: canSelect ? const Icon(Icons.add_circle_outline) : null,
            onTap: canSelect ? () => Navigator.pop(context, i) : null,
          ),
      ],
    );
    Widget section({
      required String title,
      required Widget child,
      Color? color,
    }) => Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: color ?? colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดคำศัพท์')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${word.word} · ${word.cefrLevel}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              word.partOfSpeechThai,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ระดับอ้างอิง · ${word.levelSource}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            if (word.practiceUsageNotice case final notice?) ...[
              section(title: 'ข้อควรระวังในการใช้คำ', child: Text(notice)),
              const SizedBox(height: 24),
            ],
            if (editorial != null) ...[
              section(
                title: 'ความหมายที่คัดแล้ว',
                color: colors.primaryContainer,
                child: Text(
                  editorial.meaning,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              section(
                title: 'ประโยคตัวอย่าง',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      editorial.example,
                      style: theme.textTheme.titleLarge?.copyWith(height: 1.6),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(height: 1),
                    ),
                    Text(
                      'คำแปล',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      editorial.translation,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ตัวอย่างนี้ตรวจภาษาเบื้องต้นด้วย AI',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 24),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(
                      word.senseReview == null
                          ? 'ความหมายอื่นจากพจนานุกรม · ยังรอตรวจ'
                          : 'ความหมายอื่นที่ผ่านการคัดด้วย AI',
                    ),
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    children: [meanings()],
                  ),
                ),
              ],
            ] else ...[
              section(
                title: 'ความหมายจากพจนานุกรม',
                child: const Text('คำนี้ยังรอคัดความหมายและเขียนตัวอย่าง'),
              ),
              const SizedBox(height: 20),
              Text(
                word.practiceUsageNotice == null
                    ? 'เลือกความหมายจากพจนานุกรมเข้าคลังของฉัน'
                    : 'ข้อมูลต้นทางสำหรับอ่านประกอบ',
              ),
              const SizedBox(height: 12),
              Card.outlined(margin: EdgeInsets.zero, child: meanings()),
            ],
            const SizedBox(height: 20),
            Card.outlined(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                title: const Text('เกี่ยวกับระดับภาษา'),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: const [Text(CefrVocabularyCatalog.notice)],
              ),
            ),
            if (!canAdd) ...[
              const SizedBox(height: 20),
              const Text('เพิ่มคำได้เมื่อคลังคำศัพท์ส่วนตัวพร้อมใช้งาน'),
            ],
          ],
        ),
      ),
      bottomNavigationBar: editorial == null || word.practiceUsageNotice != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton.icon(
                  key: const ValueKey('add-curated-meaning'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  onPressed: canSelect
                      ? () => Navigator.pop(context, -1)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'เพิ่มความหมายที่คัดแล้ว',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }
}
