import 'package:flutter/material.dart';

import '../features/learning_packs/domain/content_manifest.dart';
import '../features/review/domain/content_quality_report.dart';
import '../features/review/domain/learner_intent.dart';
import '../features/review/presentation/content_report_sheet.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';

/// Accessible, optional presentation of verified lexical metadata.
///
/// The card neither fetches content nor records learning evidence. Its input is
/// a vocabulary word already resolved by the canonical vocabulary authority.
final class RichLexicalCard extends StatefulWidget {
  const RichLexicalCard({
    super.key,
    required this.word,
    this.onPlayAudio,
    this.bookmarkIdentity,
    this.onBookmark,
    this.reportIdentity,
    this.onReport,
  });

  final VocabularyWord word;
  final VoidCallback? onPlayAudio;
  final ContentIdentity? bookmarkIdentity;
  final BookmarkLearningItemAction? onBookmark;
  final ContentIdentity? reportIdentity;
  final ReportContentAction? onReport;

  @override
  State<RichLexicalCard> createState() => _RichLexicalCardState();
}

final class _RichLexicalCardState extends State<RichLexicalCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final metadata = word.richMetadata;
    final entryLabel = _entryLabel(word);
    final bookmark = switch ((widget.bookmarkIdentity, widget.onBookmark)) {
      (final identity?, final action?)
          when identity.type == ContentType.lexicalMetadata &&
              identity.id == word.id &&
              identity.revision == word.contentRevision =>
        (identity: identity, action: action),
      _ => null,
    };
    final report = switch ((widget.reportIdentity, widget.onReport)) {
      (final identity?, final action?)
          when identity.type == ContentType.lexicalMetadata &&
              identity.id == word.id &&
              identity.revision == word.contentRevision =>
        (identity: identity, action: action),
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: entryLabel,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.spelling,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(word.meaning),
                    Text('ชนิดของคำ: ${word.partOfSpeech}'),
                    if (word.cefrLevel != null) Text('CEFR: ${word.cefrLevel}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (bookmark case final contract?) ...[
              Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                label: 'บันทึกไว้ทบทวน',
                enabled: true,
                onTap: () => contract.action(contract.identity),
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: () => contract.action(contract.identity),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('บันทึกไว้ทบทวน'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (report case final contract?) ...[
              Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                label: 'รายงานเนื้อหา',
                enabled: true,
                onTap: () => _showContentReport(
                  context,
                  identity: contract.identity,
                  action: contract.action,
                ),
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: () => _showContentReport(
                      context,
                      identity: contract.identity,
                      action: contract.action,
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('รายงานเนื้อหา'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (metadata == null)
              const Text('รายละเอียดคำศัพท์เพิ่มเติมไม่พร้อมใช้งาน')
            else ...[
              Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                enabled: true,
                onTap: _toggleDetails,
                label: _expanded
                    ? 'ซ่อนรายละเอียดคำศัพท์'
                    : 'ดูรายละเอียดคำศัพท์',
                child: ExcludeSemantics(
                  child: OutlinedButton(
                    onPressed: _toggleDetails,
                    child: Text(
                      _expanded
                          ? 'ซ่อนรายละเอียดคำศัพท์'
                          : 'ดูรายละเอียดคำศัพท์',
                    ),
                  ),
                ),
              ),
              if (_expanded) _RichDetails(metadata: metadata),
            ],
            const SizedBox(height: 8),
            _AudioControl(
              audio: metadata?.audio,
              onPlayAudio: widget.onPlayAudio,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDetails() => setState(() => _expanded = !_expanded);

  String _entryLabel(VocabularyWord word) {
    final cefr = word.cefrLevel;
    return 'คำศัพท์: ${word.spelling}. ความหมาย: ${word.meaning}. '
        'ชนิดของคำ: ${word.partOfSpeech}.${cefr == null ? '' : ' CEFR: $cefr.'}';
  }
}

Future<void> _showContentReport(
  BuildContext context, {
  required ContentIdentity identity,
  required ReportContentAction action,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ContentReportSheet(
      identity: identity,
      onSubmit: ({required reason, comment}) =>
          action(identity: identity, reason: reason, comment: comment),
    ),
  );
}

final class _RichDetails extends StatelessWidget {
  const _RichDetails({required this.metadata});

  final RichLexicalMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final label = _detailsLabel(metadata);
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metadata.ipa != null) Text('IPA: ${metadata.ipa}'),
              if (metadata.examples.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('ตัวอย่าง'),
                for (final example in metadata.examples) Text(example),
              ],
              if (metadata.synonyms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('คำใกล้เคียง: ${metadata.synonyms.join(', ')}'),
              ],
              if (metadata.antonyms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('คำตรงข้าม: ${metadata.antonyms.join(', ')}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _detailsLabel(RichLexicalMetadata metadata) {
    final parts = <String>[];
    final ipa = metadata.ipa;
    if (ipa != null) parts.add('IPA: $ipa.');
    if (metadata.examples.isNotEmpty) {
      parts.add('ตัวอย่าง: ${metadata.examples.join(' ')}.');
    }
    if (metadata.synonyms.isNotEmpty) {
      parts.add('คำใกล้เคียง: ${metadata.synonyms.join(', ')}.');
    }
    if (metadata.antonyms.isNotEmpty) {
      parts.add('คำตรงข้าม: ${metadata.antonyms.join(', ')}.');
    }
    return 'รายละเอียดคำศัพท์เพิ่มเติม: ${parts.join(' ')}';
  }
}

final class _AudioControl extends StatelessWidget {
  const _AudioControl({required this.audio, required this.onPlayAudio});

  final LexicalAudioMetadata? audio;
  final VoidCallback? onPlayAudio;

  @override
  Widget build(BuildContext context) {
    if (audio == null || onPlayAudio == null) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'เสียงอ่านคำศัพท์ไม่พร้อมใช้งาน',
        child: ExcludeSemantics(child: Text('เสียงอ่านคำศัพท์ไม่พร้อมใช้งาน')),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'ฟังเสียงอ่านคำศัพท์',
      enabled: true,
      onTap: onPlayAudio,
      child: ExcludeSemantics(
        child: IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: onPlayAudio,
          tooltip: 'ฟังเสียงอ่านคำศัพท์',
        ),
      ),
    );
  }
}
