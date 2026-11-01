import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../learning/domain/learning_models.dart';
import '../application/learning_pack_use_cases.dart';
import '../domain/learning_pack.dart';
import '../domain/learning_pack_repository.dart';

class RichLexicalCard extends StatelessWidget {
  const RichLexicalCard({
    super.key,
    required this.content,
    this.showIdentity = true,
    this.showAssistance = false,
  });
  final CurrentLexicalContent content;
  final bool showIdentity;
  final bool showAssistance;

  @override
  Widget build(BuildContext context) => LexicalEntryDetails(
    entry: content.entry,
    image: content.image,
    packCefrLevel: content.pack.manifest.cefrLevel,
    showIdentity: showIdentity,
    showAssistance: showAssistance,
  );
}

class LexicalEntryDetails extends StatelessWidget {
  const LexicalEntryDetails({
    super.key,
    required this.entry,
    this.image,
    this.packCefrLevel,
    this.showIdentity = true,
    this.showAssistance = false,
  });
  final LearningPackEntry entry;
  final LearningPackImage? image;
  final String? packCefrLevel;
  final bool showIdentity;
  final bool showAssistance;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showIdentity) ...[
          Text(
            entry.spelling,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${entry.meaning} · ${entry.partOfSpeech}'),
        ],
        if (packCefrLevel case final cefr?) Text('ระดับแพ็ก $cefr'),
        if (entry.lexicalDetails?.ipa case final ipa?)
          Semantics(
            label: 'การออกเสียง IPA $ipa',
            excludeSemantics: true,
            child: Text(ipa),
          ),
        if (image case final asset?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Image.memory(
                asset.bytes,
                fit: BoxFit.contain,
                semanticLabel: asset.altText,
              ),
            ),
          ),
        if (entry.definition case final definition?) ...[
          const SizedBox(height: 12),
          Text('คำจำกัดความภาษาอังกฤษ', style: title),
          Text(definition),
        ],
        if (entry.examples.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('ตัวอย่างการใช้', style: title),
          for (final example in entry.examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(example.text),
                  if (example.translation case final translation?)
                    Text(translation),
                ],
              ),
            ),
        ],
        if (entry.lexicalDetails?.synonyms.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text('คำที่มีความหมายใกล้เคียง', style: title),
          Text(entry.lexicalDetails!.synonyms.join(' · ')),
        ],
        if (entry.lexicalDetails?.antonyms.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text('คำที่มีความหมายตรงข้าม', style: title),
          Text(entry.lexicalDetails!.antonyms.join(' · ')),
        ],
        if (showAssistance) ...[
          if (entry.memoryCue case final cue?) ...[
            const SizedBox(height: 12),
            Text('ช่วยจำ', style: title),
            Text(cue),
          ],
          if (entry.hint case final hint?) ...[
            const SizedBox(height: 12),
            Text('คำใบ้', style: title),
            Text(hint),
          ],
          if (entry.strategy case final strategy?) ...[
            const SizedBox(height: 12),
            Text('วิธีฝึก', style: title),
            Text(strategy),
          ],
        ],
      ],
    );
  }
}

/// Optional authored detail; a missing pack never blocks the ordinary word.
class OwnedLexicalDetails extends StatefulWidget {
  const OwnedLexicalDetails({
    super.key,
    required this.word,
    required this.expectedOwnerId,
    required this.visible,
    this.showAssistance = false,
  });
  final QuizWord word;
  final String expectedOwnerId;
  final bool Function() visible;
  final bool showAssistance;
  @override
  State<OwnedLexicalDetails> createState() => _OwnedLexicalDetailsState();
}

class _OwnedLexicalDetailsState extends State<OwnedLexicalDetails> {
  AppDependencies? _dependencies;
  LearningPackUseCases? _packs;
  StreamSubscription<Object?>? _data;
  StreamSubscription<String?>? _owners;
  CurrentLexicalContent? _content;
  var _read = 0;
  var _bound = false;
  var _retired = false;
  bool get _visible =>
      mounted &&
      !_retired &&
      widget.visible() &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      Visibility.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_bound && !identical(dependencies, _dependencies)) {
      _retired = true;
      _clear();
      return;
    }
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _packs = dependencies?.learningPacks;
      final database = dependencies?.database;
      if (database != null) {
        _data = database
            .tableUpdates(
              TableUpdateQuery.allOf([
                TableUpdateQuery.onTable(database.vocabularyWords),
                TableUpdateQuery.onTable(database.learningPackVersions),
                TableUpdateQuery.onTable(database.lexicalContentSnapshots),
              ]),
            )
            .listen(
              (_) {
                _clear();
                unawaited(_load());
              },
              onError: (Object _) {
                _retired = true;
                _clear();
              },
              onDone: () {
                _retired = true;
                _clear();
              },
            );
      }
      _owners = _packs?.watchActiveOwnerId().listen(
        (owner) {
          if (owner != widget.expectedOwnerId) _retired = true;
          _clear();
          if (!_retired) unawaited(_load());
        },
        onError: (Object _) {
          _retired = true;
          _clear();
        },
        onDone: () {
          _retired = true;
          _clear();
        },
      );
    }
    if (!_visible) {
      _clear();
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(OwnedLexicalDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId) _retired = true;
    if (!identical(oldWidget.word, widget.word) ||
        oldWidget.showAssistance != widget.showAssistance) {
      _clear();
      unawaited(_load());
    }
  }

  void _clear() {
    _read++;
    if (mounted) setState(() => _content = null);
  }

  Future<void> _load() async {
    final packs = _packs;
    if (!_visible || packs == null || widget.word.contentRevision == null) {
      return;
    }
    final read = ++_read;
    bool current() => _visible && read == _read && identical(packs, _packs);
    try {
      final scope = await packs.captureOwner(stillCurrent: current);
      if (!current() ||
          scope == null ||
          scope.ownerId != widget.expectedOwnerId) {
        return;
      }
      final content = await packs.currentLexical(
        scope: scope,
        wordId: widget.word.id,
      );
      if (!current() || !scope.isCurrent || content == null) return;
      final actual = content.word;
      final expected = widget.word;
      if (actual.ownerId != widget.expectedOwnerId ||
          actual.id != expected.id ||
          actual.categoryId != expected.categoryId ||
          actual.spelling != expected.spelling ||
          actual.meaning != expected.meaning ||
          actual.partOfSpeech != expected.partOfSpeech ||
          expected.contentRevision !=
              'local-vocabulary-v1:${actual.localRevision}') {
        return;
      }
      setState(() => _content = content);
    } on Object {
      if (current()) setState(() => _content = null);
    }
  }

  @override
  void dispose() {
    _retired = true;
    _read++;
    unawaited(_data?.cancel());
    unawaited(_owners?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_visible || _content == null
      ? const SizedBox.shrink()
      : RichLexicalCard(
          content: _content!,
          showIdentity: false,
          showAssistance: widget.showAssistance,
        );
}
