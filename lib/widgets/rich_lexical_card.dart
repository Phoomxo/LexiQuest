import 'package:flutter/material.dart';

import '../features/learning_packs/domain/content_manifest.dart';
import '../features/review/domain/learner_intent.dart';
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
  });

  final VocabularyWord word;
  final VoidCallback? onPlayAudio;
  final ContentIdentity? bookmarkIdentity;
  final BookmarkLearningItemAction? onBookmark;

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
                    Text('Part of speech: ${word.partOfSpeech}'),
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
                label: 'Save for review',
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: () => contract.action(contract.identity),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save for review'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (metadata == null)
              const Text('Additional lexical details are unavailable.')
            else ...[
              Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                label: _expanded
                    ? 'Hide lexical details'
                    : 'Show lexical details',
                child: ExcludeSemantics(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded
                          ? 'Hide lexical details'
                          : 'Show lexical details',
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

  String _entryLabel(VocabularyWord word) {
    final cefr = word.cefrLevel;
    return 'Lexical entry: ${word.spelling}. Meaning: ${word.meaning}. '
        'Part of speech: ${word.partOfSpeech}.${cefr == null ? '' : ' CEFR: $cefr.'}';
  }
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
                const Text('Examples'),
                for (final example in metadata.examples) Text(example),
              ],
              if (metadata.synonyms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Synonyms: ${metadata.synonyms.join(', ')}'),
              ],
              if (metadata.antonyms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Antonyms: ${metadata.antonyms.join(', ')}'),
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
      parts.add('Examples: ${metadata.examples.join(' ')}.');
    }
    if (metadata.synonyms.isNotEmpty) {
      parts.add('Synonyms: ${metadata.synonyms.join(', ')}.');
    }
    if (metadata.antonyms.isNotEmpty) {
      parts.add('Antonyms: ${metadata.antonyms.join(', ')}.');
    }
    return 'Additional lexical details: ${parts.join(' ')}';
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
        label: 'Pronunciation audio unavailable',
        child: ExcludeSemantics(child: Text('Pronunciation audio unavailable')),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Play pronunciation audio',
      child: ExcludeSemantics(
        child: IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: onPlayAudio,
          tooltip: 'Play pronunciation audio',
        ),
      ),
    );
  }
}
