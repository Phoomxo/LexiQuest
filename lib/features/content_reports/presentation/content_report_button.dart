import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../widgets/word_report_sheet.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/learning_time_admission.dart';
import '../../learning_packs/domain/learning_pack.dart';
import '../../vocabulary/domain/word_report.dart';
import '../domain/content_report.dart';
import 'content_report_sheet.dart';

String contentReportEntryText(LearningPackEntry entry) => [
  entry.spelling,
  entry.meaning,
  entry.partOfSpeech,
  if (entry.definition != null) entry.definition!,
  for (final example in entry.examples) ...[
    example.text,
    if (example.translation != null) example.translation!,
  ],
  if (entry.memoryCue != null) entry.memoryCue!,
  if (entry.hint != null) entry.hint!,
  if (entry.strategy != null) entry.strategy!,
  if (entry.lexicalDetails case final details?) ...[
    if (details.ipa != null) details.ipa!,
    ...details.synonyms,
    ...details.antonyms,
  ],
].join('\n');

class ContentReportButton extends StatefulWidget {
  const ContentReportButton.content({
    super.key,
    required this.expectedOwnerId,
    required this.sourceIdentity,
    required String this._sourceText,
    required ContentReportTarget Function(String, bool)
    this._targetForSelection,
    required this.callerContext,
    required this.canOpen,
    this.ownerChanges,
    this.beforeOpen,
    this.onOverlayChanged,
    this.sessionId,
    this.revalidateSource,
    this.compact = false,
    this.languageCode = 'th',
  }) : _word = null;
  ContentReportButton.ownedWord({
    super.key,
    required this.expectedOwnerId,
    required QuizWord word,
    required this.callerContext,
    required this.canOpen,
    this.ownerChanges,
    this.beforeOpen,
    this.onOverlayChanged,
    this.sessionId,
    this.revalidateSource,
    this.compact = false,
    this.languageCode = 'th',
  }) : sourceIdentity = (
         word.id,
         word.categoryId,
         word.spelling,
         word.meaning,
         word.partOfSpeech,
         word.contentRevision,
       ),
       _word = word,
       _sourceText = null,
       _targetForSelection = null;

  final String expectedOwnerId;
  final Object sourceIdentity;
  final LearningTimeCallerContext callerContext;
  final bool Function() canOpen;
  final Stream<String?>? ownerChanges;
  final Future<void> Function()? beforeOpen;
  final void Function(bool)? onOverlayChanged;
  final String? sessionId;
  final Future<void> Function(bool Function() stillCurrent)? revalidateSource;
  final bool compact;
  final String languageCode;
  final String? _sourceText;
  final ContentReportTarget Function(String, bool)? _targetForSelection;
  final QuizWord? _word;
  @override
  State<ContentReportButton> createState() => _ContentReportButtonState();
}

class _ContentReportButtonState extends State<ContentReportButton>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  WordReportOwnerScope? _scope;
  Stream<String?> Function()? _owners;
  ModalRoute<dynamic>? _route;
  ValueNotifier<bool>? _sourceLease;
  bool _bound = false;
  bool _retired = false;
  bool _busy = false;
  bool _opening = false;
  bool _foreground = false;
  bool _paneVisible = true;
  bool _everCurrent = false;
  int _ownerGeneration = -1;
  int _epoch = 0;
  bool get _ordinary =>
      widget.callerContext == LearningTimeCallerContext.ordinary;
  bool get _available => _ordinary && !_retired && _scope?.current == true;
  bool _current(int epoch) =>
      mounted && _available && epoch == _epoch && widget.canOpen();
  bool _sourceCurrent(int epoch) => mounted && _available && epoch == _epoch;
  Future<void> _revalidate(int epoch) async {
    bool current() => _sourceCurrent(epoch);
    if (!current()) throw StateError('The report source is no longer current');
    final sessionId = widget.sessionId;
    if (sessionId != null) {
      await _dependencies!.contentReports!.requireOrdinarySession(
        expectedOwnerId: widget.expectedOwnerId,
        sessionId: sessionId,
        stillCurrent: current,
      );
    }
    await widget.revalidateSource?.call(current);
    if (!current()) throw StateError('The report source changed');
    if (sessionId != null) {
      await _dependencies!.contentReports!.requireOrdinarySession(
        expectedOwnerId: widget.expectedOwnerId,
        sessionId: sessionId,
        stillCurrent: current,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ordinary) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _route = ModalRoute.of(context);
    final routeCurrent = ModalRoute.isCurrentOf(context) == true;
    _paneVisible = Visibility.of(context);
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      final progress = dependencies?.progress;
      _owners = progress != null
          ? progress.watchActiveOwnerId
          : widget.ownerChanges == null
          ? null
          : () => widget.ownerChanges!;
      if (_owners != null) {
        _scope = WordReportOwnerScope(
          expectedOwnerId: widget.expectedOwnerId,
          ownerChanges: _owners!(),
          visible: () =>
              mounted &&
              !_retired &&
              _foreground &&
              _paneVisible &&
              (_route?.isCurrent == true || _opening),
        )..addListener(_ownerChanged);
      }
    } else if (!identical(dependencies, _dependencies)) {
      _retire();
    }
    if (!_paneVisible || (!routeCurrent && !_opening)) _retire();
    _scope?.synchronize();
  }

  void _ownerChanged() {
    final scope = _scope!;
    if (_everCurrent &&
        (!scope.current || scope.ownerGeneration != _ownerGeneration)) {
      _retire();
    }
    if (scope.current) {
      _everCurrent = true;
      _ownerGeneration = scope.ownerGeneration;
    }
    if (mounted) setState(() {});
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _epoch++;
    _sourceLease?.value = false;
  }

  @override
  void didUpdateWidget(covariant ContentReportButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        oldWidget.sourceIdentity != widget.sourceIdentity ||
        oldWidget._sourceText != widget._sourceText ||
        oldWidget.callerContext != widget.callerContext ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _retire();
    }
    if (oldWidget.sessionId != widget.sessionId) {
      _epoch++;
      if (_opening || _busy) _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _retire();
    _scope?.synchronize();
  }

  Future<void> _open(int epoch) async {
    if (_busy || !_current(epoch)) return;
    final dependencies = _dependencies;
    final owners = _owners;
    if (dependencies == null || owners == null) return;
    setState(() => _busy = true);
    ValueNotifier<bool>? lease;
    try {
      await widget.beforeOpen?.call();
      if (!_current(epoch)) return;
      await _revalidate(epoch);
      if (!_current(epoch)) return;
      WordReportTarget? wordTarget;
      if (widget._word case final expected?) {
        final vocabulary = dependencies.vocabulary;
        if (vocabulary == null || dependencies.wordReports == null) return;
        final rows = await vocabulary.vocabulary
            .watchWords(widget.expectedOwnerId, expected.categoryId)
            .first
            .timeout(const Duration(seconds: 10));
        if (!_current(epoch)) return;
        final word = rows
            .where(
              (word) =>
                  !word.isDeleted &&
                  word.ownerId == widget.expectedOwnerId &&
                  word.id == expected.id &&
                  word.categoryId == expected.categoryId &&
                  word.spelling == expected.spelling &&
                  word.meaning == expected.meaning &&
                  word.partOfSpeech == expected.partOfSpeech &&
                  'local-vocabulary-v1:${word.localRevision}' ==
                      expected.contentRevision,
            )
            .firstOrNull;
        if (word == null) throw StateError('The displayed word changed');
        wordTarget = WordReportTarget.fromWord(word);
      } else if (dependencies.contentReports == null) {
        return;
      }
      if (!mounted || !_current(epoch)) return;
      _opening = true;
      widget.onOverlayChanged?.call(true);
      lease = ValueNotifier(true);
      _sourceLease = lease;
      if (wordTarget != null) {
        final sheetOwners = owners();
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: lease!,
            builder: (_, valid, _) => !valid
                ? const SizedBox.shrink()
                : WordReportSheet(
                    expectedOwnerId: widget.expectedOwnerId,
                    target: wordTarget!,
                    wordReports: dependencies.wordReports,
                    ownerChanges: sheetOwners,
                    revalidate: () => _revalidate(epoch),
                    languageCode: widget.languageCode,
                  ),
          ),
        );
      } else {
        await showContentReportComposer(
          context,
          expectedOwnerId: widget.expectedOwnerId,
          sourceText: widget._sourceText!,
          targetForSelection: widget._targetForSelection!,
          reports: dependencies.contentReports!,
          ownerChanges: owners(),
          sourceLease: lease,
          revalidate: () => _revalidate(epoch),
          languageCode: widget.languageCode,
        );
      }
    } on Object {
      if (mounted && _current(epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.languageCode == 'en'
                  ? 'The source is unavailable. Close and reopen it before reporting.'
                  : 'ข้อมูลต้นทางไม่พร้อม กรุณาปิดแล้วเปิดเนื้อหาใหม่ก่อนรายงาน',
            ),
          ),
        );
      }
    } finally {
      lease?.value = false;
      lease?.dispose();
      if (identical(_sourceLease, lease)) _sourceLease = null;
      _opening = false;
      if (mounted) {
        widget.onOverlayChanged?.call(false);
        setState(() => _busy = false);
        _scope?.synchronize();
      }
    }
  }

  @override
  void dispose() {
    _retire();
    WidgetsBinding.instance.removeObserver(this);
    _scope?.removeListener(_ownerChanged);
    unawaited(_scope?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (!_ordinary ||
        dependencies == null ||
        (widget.sessionId != null &&
            dependencies.contentReports?.ordinarySessionGuard == null) ||
        (widget._word != null
            ? dependencies.wordReports == null ||
                  dependencies.vocabulary == null
            : dependencies.contentReports == null)) {
      return const SizedBox.shrink();
    }
    final epoch = _epoch;
    final onPressed = !_available || _busy || !widget.canOpen()
        ? null
        : () => unawaited(_open(epoch));
    final label = widget.languageCode == 'en'
        ? 'Report content'
        : 'รายงานเนื้อหานี้';
    return widget.compact
        ? IconButton(
            onPressed: onPressed,
            tooltip: label,
            icon: const Icon(Icons.flag_outlined),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.flag_outlined),
            label: Text(label),
          );
  }
}
