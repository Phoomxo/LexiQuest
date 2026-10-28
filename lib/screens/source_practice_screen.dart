import 'package:flutter/material.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/vocabulary/application/source_practice.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'ai_tutor_screen.dart';
import 'associative_reading_session_screen.dart';
import 'quiz_screen.dart';
import 'score_screen.dart';
import 'srs_flashcards_screen.dart';
import 'speak_to_text_screen.dart';

class SourcePracticeScreen extends StatefulWidget {
  const SourcePracticeScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.vocabulary,
    required this.learning,
    required this.filePicker,
    this.associativeLearning,
    this.voice,
  });

  final String categoryId;
  final String categoryName;
  final VocabularyUseCases vocabulary;
  final LearningUseCases learning;
  final SourcePracticeFilePicker filePicker;
  final AssociativeLearningPort? associativeLearning;
  final VoiceUseCases? voice;

  @override
  State<SourcePracticeScreen> createState() => _SourcePracticeScreenState();
}

class _SourcePracticeScreenState extends State<SourcePracticeScreen> {
  static const _maxPracticeWords = 20;

  final TextEditingController _textController = TextEditingController();
  SourcePracticePreview? _preview;
  String? _sourceName;
  String? _ownerId;
  String? _error;
  bool _working = false;
  bool _confirmed = false;
  final _voiceContext = ValueNotifier(0);

  @override
  void didUpdateWidget(covariant SourcePracticeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learning != widget.learning ||
        oldWidget.vocabulary != widget.vocabulary ||
        oldWidget.categoryId != widget.categoryId ||
        oldWidget.filePicker != widget.filePicker) {
      // The result route is a sibling, not a descendant of this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _voiceContext.value++;
      });
    }
  }

  @override
  void dispose() {
    _voiceContext.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('ฝึกจากไฟล์ในเครื่อง')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth >= 600 ? 32 : 20,
                  vertical: 16,
                ),
                children: [
                  Text(
                    widget.categoryName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'เลือกไฟล์ TXT หรือ Markdown ภาษาอังกฤษ แล้วตรวจข้อความ'
                    'และคำที่ตรงกับหมวดนี้ก่อนเริ่มฝึก',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('choose-source-file'),
                    onPressed: _working ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(
                      _sourceName == null ? 'เลือกไฟล์' : 'เลือกไฟล์ใหม่',
                    ),
                  ),
                  if (_sourceName != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      _sourceName!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('source-text'),
                      controller: _textController,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'ข้อความสำหรับฝึก',
                        helperText: 'แก้ไขได้ แล้วกดตรวจข้อความอีกครั้ง',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) {
                        _voiceContext.value++;
                        if (_preview == null && !_confirmed) return;
                        setState(() {
                          _preview = null;
                          _confirmed = false;
                          _error = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('review-source-text'),
                      onPressed: _working ? null : _reviewText,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('ตรวจข้อความอีกครั้ง'),
                    ),
                  ],
                  if (_working) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'กำลังอ่านไฟล์ในเครื่อง',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const ValueKey('source-practice-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  if (preview != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'คำที่ตรงกับหมวด (${preview.matchedWords.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (preview.matchedWords.isEmpty)
                      const Text('ยังไม่พบคำศัพท์ในหมวดนี้')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final word in preview.matchedWords)
                            Chip(label: Text(word.spelling)),
                        ],
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'คำที่ยังไม่อยู่ในหมวด (${preview.unknownWords.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (preview.unknownWords.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('show-all-unknown'),
                          onPressed: () =>
                              _showAllUnknown(preview.unknownWords),
                          icon: const Icon(Icons.list_alt_outlined),
                          label: const Text('ดูคำทั้งหมด'),
                        ),
                      ),
                    Text(_unknownSummary(preview.unknownWords)),
                    const SizedBox(height: 8),
                    const Text('คำเหล่านี้จะไม่ถูกเพิ่มเข้าคลังโดยอัตโนมัติ'),
                    if (preview.matchedWords.length > _maxPracticeWords) ...[
                      const SizedBox(height: 8),
                      const Text('รอบนี้ใช้ 20 คำแรกที่พบในข้อความ'),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const ValueKey('confirm-source'),
                      onPressed:
                          _working || preview.matchedWords.isEmpty || _confirmed
                          ? null
                          : _confirm,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('ยืนยันข้อความ'),
                    ),
                    if (_confirmed) ...[
                      const SizedBox(height: 24),
                      Text(
                        'เลือกวิธีฝึก',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('start-source-reading'),
                        onPressed: _working ? null : _startReading,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('อ่านและเติมคำ'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('start-source-quiz'),
                        onPressed: _working ? null : _startQuiz,
                        icon: const Icon(Icons.quiz_outlined),
                        label: const Text('เริ่มทำแบบทดสอบ'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('start-source-flashcards'),
                        onPressed: _working ? null : _startFlashcards,
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('เริ่มฝึกด้วยบัตรคำ'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('start-source-ask-lexi'),
                        onPressed: _working ? null : _startAskLexi,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(
                          'ถาม Lexi เรื่อง ${preview.matchedWords.first.spelling}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'เตรียมคำถามจากคำแรกเท่านั้น ไฟล์และข้อความต้นฉบับไม่ได้แนบ',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('start-source-voice'),
                        onPressed: _working ? null : _startVoice,
                        icon: const Icon(Icons.mic_none),
                        label: Text(
                          'ฝึกพูดคำว่า ${preview.matchedWords.first.spelling}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ฝึกพูดคำแรกเท่านั้น ไม่ส่งไฟล์หรือข้อความต้นฉบับ '
                        'ประเมินจากข้อความที่ระบบรู้จำ ไม่ใช่เสียงรายหน่วย',
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    _voiceContext.value++;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final file = await widget.filePicker();
      if (file == null || !mounted) return;
      final owner = await widget.learning.owners.getOrCreateActiveOwner();
      final words = await widget.vocabulary.watchWords(widget.categoryId).first;
      final current = await widget.learning.owners.getOrCreateActiveOwner();
      if (!mounted) return;
      if (current.id != owner.id) {
        _ownerChanged();
        return;
      }
      final preview = parseSourcePracticeFile(
        fileName: file.name,
        mimeType: file.mimeType,
        bytes: file.bytes,
        words: words,
      );
      if (!mounted) return;
      _textController.text = preview.passageText;
      setState(() {
        _sourceName = file.name;
        _ownerId = owner.id;
        _preview = preview;
        _confirmed = false;
        _voiceContext.value++;
      });
    } on SourcePracticeFailure catch (failure) {
      if (mounted) _sourceFailure(failure.code);
    } catch (_) {
      if (mounted) _sourceFailure('unavailable');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reviewText() async {
    _voiceContext.value++;
    final sourceName = _sourceName;
    if (sourceName == null) return;
    try {
      final words = await _loadCurrentCategoryWords();
      if (words == null) return;
      final preview = reviewSourcePracticeText(
        sourceName: sourceName,
        text: _textController.text,
        words: words,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _confirmed = false;
        _voiceContext.value++;
        _error = null;
      });
    } on SourcePracticeFailure catch (failure) {
      if (mounted) _sourceFailure(failure.code, clearFile: false);
    }
  }

  Future<void> _confirm() async {
    if (!await _ownerStillCurrent()) return;
    if (!mounted) return;
    setState(() {
      _confirmed = true;
      _error = null;
    });
  }

  Future<void> _startReading() async {
    if (_working || !_confirmed || _preview == null) return;
    setState(() => _working = true);
    try {
      final preview = await _validatedPreviewForLaunch();
      if (preview == null || !mounted) return;
      final words = preview.matchedWords.take(_maxPracticeWords).toList();
      final resultContext = _captureResultContext(preview, words);
      if (resultContext == null) return;
      final result = await AppNavigator.pushPage<LearningSessionResult>(
        context,
        AppPage<LearningSessionResult>(
          name: 'learning/source-reading',
          builder: (_) => AssociativeReadingSessionScreen(
            cefrLevel: 'Source',
            targetWords: words.map((word) => word.spelling).toList(),
            passageText: preview.passageText,
            documentId: preview.documentId,
            documentRevision: preview.documentRevision,
            learning: resultContext.learning,
            associativeLearning: widget.associativeLearning,
            targetWordIds: {for (final word in words) word.spelling: word.id},
            targetWordContentRevisions: {
              for (final word in words)
                word.spelling: 'local-vocabulary-v1:${word.localRevision}',
            },
            ownerId: resultContext.ownerId,
          ),
        ),
      );
      await _showSourceResult(
        resultContext,
        result,
        routeName: 'learning/source-reading-result',
        repairRouteName: 'learning/source-reading-repair',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startQuiz() async {
    if (_working || !_confirmed || _preview == null) return;
    setState(() => _working = true);
    try {
      final preview = await _validatedPreviewForLaunch();
      if (preview == null || !mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/source-quiz',
          builder: (_) => QuizScreen(
            wordIds: preview.matchedWords
                .take(_maxPracticeWords)
                .map((word) => word.id)
                .toList(),
            selectionMode: QuizWordSelectionMode.sourcePractice,
            learning: widget.learning,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startFlashcards() async {
    if (_working || !_confirmed || _preview == null) return;
    setState(() => _working = true);
    try {
      final preview = await _validatedPreviewForLaunch();
      if (preview == null || !mounted) return;
      final words = preview.matchedWords.take(_maxPracticeWords).toList();
      final resultContext = _captureResultContext(preview, words);
      if (resultContext == null) return;
      final result = await AppNavigator.pushPage<LearningSessionResult>(
        context,
        AppPage<LearningSessionResult>(
          name: 'learning/source-flashcards',
          builder: (_) => SrsFlashcardsScreen(
            sourceWordIds: words.map((word) => word.id).toList(growable: false),
            learning: resultContext.learning,
            voice: widget.voice,
          ),
        ),
      );
      await _showSourceResult(
        resultContext,
        result,
        routeName: 'learning/source-flashcards-result',
        repairRouteName: 'learning/source-flashcards-repair',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<List<VocabularyWord>?> _loadCurrentCategoryWords() async {
    if (!await _ownerStillCurrent()) return null;
    final words = await widget.vocabulary.watchWords(widget.categoryId).first;
    if (!mounted || !await _ownerStillCurrent()) return null;
    return words;
  }

  _SourceResultContext? _captureResultContext(
    SourcePracticePreview preview,
    List<VocabularyWord> words,
  ) {
    final ownerId = _ownerId;
    final sourceName = _sourceName;
    if (ownerId == null || sourceName == null || words.isEmpty) return null;
    return _SourceResultContext(
      epoch: _voiceContext.value,
      ownerId: ownerId,
      categoryId: widget.categoryId,
      sourceName: sourceName,
      sourceText: _textController.text,
      documentId: preview.documentId,
      documentRevision: preview.documentRevision,
      words: words,
      learning: widget.learning,
      vocabulary: widget.vocabulary,
    );
  }

  bool _resultContextCurrent(_SourceResultContext captured) =>
      mounted &&
      _voiceContext.value == captured.epoch &&
      _ownerId == captured.ownerId &&
      _sourceName == captured.sourceName &&
      _textController.text == captured.sourceText &&
      _confirmed &&
      widget.categoryId == captured.categoryId &&
      identical(widget.learning, captured.learning) &&
      identical(widget.vocabulary, captured.vocabulary);

  Future<List<VocabularyWord>?> _revalidateResultContext(
    _SourceResultContext captured,
  ) async {
    if (!_resultContextCurrent(captured) ||
        !await _ownerStillCurrent() ||
        !_resultContextCurrent(captured)) {
      return null;
    }
    final categories = await captured.vocabulary.watchCategories().first;
    if (!_resultContextCurrent(captured) ||
        !categories.any(
          (category) =>
              category.id == captured.categoryId &&
              category.ownerId == captured.ownerId &&
              !category.isDeleted,
        )) {
      return null;
    }
    final preview = await _validatedPreviewForLaunch();
    if (preview == null || !_resultContextCurrent(captured)) return null;
    final words = preview.matchedWords
        .take(_maxPracticeWords)
        .toList(growable: false);
    if (preview.documentId != captured.documentId ||
        preview.documentRevision != captured.documentRevision ||
        !_sameWordSnapshots(captured.words, words)) {
      return null;
    }
    return words;
  }

  Future<void> _showSourceResult(
    _SourceResultContext captured,
    LearningSessionResult? result, {
    required String routeName,
    required String repairRouteName,
  }) async {
    if (result == null) return;
    if (!_resultContextCurrent(captured)) {
      if (mounted) {
        setState(
          () => _error = 'ยังยืนยันผลรอบนี้ไม่ได้ กรุณากลับไปเลือกกิจกรรม',
        );
      }
      return;
    }
    final mistakeIds = result.mistakeWordIds.toSet().toList(growable: false);
    final summary = result.summary;
    final total = summary.correctCount + summary.wrongCount;
    final expectedScore = total == 0
        ? 0
        : ((summary.correctCount * 100) / total).round();
    final targetIds = captured.words.map((word) => word.id).toSet();
    if (summary.id.trim().isEmpty ||
        summary.state != 'completed' ||
        summary.correctCount < 0 ||
        summary.wrongCount < 0 ||
        total != captured.words.length ||
        summary.score != expectedScore ||
        mistakeIds.length != summary.wrongCount ||
        !mistakeIds.every(targetIds.contains)) {
      if (mounted) {
        setState(
          () => _error = 'ยังยืนยันผลรอบนี้ไม่ได้ กรุณากลับไปเลือกกิจกรรม',
        );
      }
      return;
    }
    final currentWords = await _revalidateResultContext(captured);
    if (currentWords == null || !mounted || !_resultContextCurrent(captured)) {
      return;
    }
    final wordsById = {for (final word in currentWords) word.id: word};
    final mistakes = [
      for (final id in mistakeIds)
        QuizWord(
          id: wordsById[id]!.id,
          categoryId: wordsById[id]!.categoryId,
          spelling: wordsById[id]!.spelling,
          meaning: wordsById[id]!.meaning,
          partOfSpeech: wordsById[id]!.partOfSpeech,
        ),
    ];
    var resultOpen = true;
    var repairing = false;
    var dismissScheduled = false;
    final sourceRoute = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    void dismissInvalidatedFlow() {
      if (_resultContextCurrent(captured) || dismissScheduled) return;
      dismissScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dismissScheduled = false;
        if (mounted &&
            resultOpen &&
            !_resultContextCurrent(captured) &&
            sourceRoute?.isActive == true &&
            navigator.mounted &&
            !sourceRoute!.isCurrent) {
          navigator.pop();
          dismissInvalidatedFlow();
        }
      });
    }

    _voiceContext.addListener(dismissInvalidatedFlow);
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: routeName,
          builder: (scoreContext) => ValueListenableBuilder<int>(
            valueListenable: _voiceContext,
            builder: (_, _, _) {
              if (!_resultContextCurrent(captured) || !resultOpen) {
                return Scaffold(
                  appBar: AppBar(title: const Text('ผลการเรียน')),
                  body: const Center(
                    child: Text('ข้อมูลเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'),
                  ),
                );
              }
              return ScoreScreen(
                correctAnswers: summary.correctCount,
                wrongAnswers: summary.wrongCount,
                score: summary.score,
                mistakes: mistakes,
                onPracticeMistakes: mistakes.isEmpty
                    ? null
                    : () async {
                        if (repairing ||
                            !resultOpen ||
                            !scoreContext.mounted ||
                            ModalRoute.of(scoreContext)?.isCurrent != true) {
                          return;
                        }
                        repairing = true;
                        try {
                          final current = await _revalidateResultContext(
                            captured,
                          );
                          if (current == null ||
                              !_resultContextCurrent(captured) ||
                              !resultOpen ||
                              !scoreContext.mounted ||
                              ModalRoute.of(scoreContext)?.isCurrent != true) {
                            if (scoreContext.mounted &&
                                ModalRoute.of(scoreContext)?.isCurrent ==
                                    true) {
                              Navigator.of(scoreContext).pop();
                            }
                            return;
                          }
                          await AppNavigator.pushPage<void>(
                            scoreContext,
                            AppPage<void>(
                              name: repairRouteName,
                              builder: (_) => QuizScreen(
                                wordIds: mistakeIds,
                                learning: captured.learning,
                              ),
                            ),
                          );
                          if (scoreContext.mounted &&
                              ModalRoute.of(scoreContext)?.isCurrent == true) {
                            Navigator.of(scoreContext).pop();
                          }
                        } on Object {
                          if (scoreContext.mounted &&
                              ModalRoute.of(scoreContext)?.isCurrent == true) {
                            Navigator.of(scoreContext).pop();
                          }
                        } finally {
                          repairing = false;
                        }
                      },
              );
            },
          ),
        ),
      );
    } finally {
      resultOpen = false;
      _voiceContext.removeListener(dismissInvalidatedFlow);
    }
  }

  Future<void> _startVoice() async {
    final ownerId = _ownerId;
    if (_working || !_confirmed || _preview == null || ownerId == null) return;
    final learning = widget.learning;
    final vocabulary = widget.vocabulary;
    final categoryId = widget.categoryId;
    final voiceContext = _voiceContext.value;
    final target = _preview!.matchedWords.first;
    bool contextCurrent() =>
        mounted &&
        _voiceContext.value == voiceContext &&
        _ownerId == ownerId &&
        _confirmed &&
        identical(widget.learning, learning) &&
        identical(widget.vocabulary, vocabulary) &&
        widget.categoryId == categoryId;
    Future<bool> validateTarget() async {
      if (!contextCurrent()) return false;
      if (!await _ownerStillCurrent() || !contextCurrent()) return false;
      final categories = await vocabulary.watchCategories().first;
      if (!contextCurrent()) return false;
      if (!categories.any(
        (category) =>
            category.id == categoryId &&
            category.ownerId == ownerId &&
            !category.isDeleted,
      )) {
        if (!await _ownerStillCurrent() || !contextCurrent()) return false;
        setState(() {
          _confirmed = false;
          _error = 'หมวดคำศัพท์เปลี่ยนแล้ว กรุณาเลือกไฟล์ใหม่';
          _voiceContext.value++;
        });
        return false;
      }
      final preview = await _validatedPreviewForLaunch();
      return contextCurrent() &&
          preview != null &&
          preview.matchedWords.first.id == target.id &&
          preview.matchedWords.first.spelling == target.spelling &&
          preview.matchedWords.first.localRevision == target.localRevision &&
          preview.matchedWords.first.meaning == target.meaning &&
          preview.matchedWords.first.partOfSpeech == target.partOfSpeech;
    }

    setState(() => _working = true);
    try {
      final preview = await _validatedPreviewForLaunch();
      if (preview == null || !contextCurrent()) return;
      if (!identical(learning, widget.learning) ||
          preview.matchedWords.first.spelling != target.spelling) {
        setState(() {
          _confirmed = false;
          _error = 'คลังคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง';
        });
        return;
      }
      final session = await learning.startSourcePronunciationForWords(
        wordIds: [target.id],
        limit: 1,
      );
      if (!mounted) return;
      final current = await _validatedPreviewForLaunch();
      if (current == null || !mounted || !contextCurrent()) return;
      if (!identical(learning, widget.learning) ||
          current.matchedWords.first.id != target.id ||
          current.matchedWords.first.spelling != target.spelling ||
          session.id.isEmpty ||
          session.questions.length != 1 ||
          session.questions.single.word.id != target.id ||
          session.questions.single.word.spelling != target.spelling ||
          session.questions.single.word.categoryId != widget.categoryId) {
        setState(() {
          _confirmed = false;
          _error = 'ข้อมูลคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง';
        });
        return;
      }
      final summary = await AppNavigator.pushPage<LearningSessionSummary>(
        context,
        AppPage<LearningSessionSummary>(
          name: 'learning/source-voice',
          builder: (_) => SpeakToTextScreen(
            correctWord: target.spelling,
            wordId: target.id,
            sessionId: session.id,
            sourceOwnerId: ownerId,
            contentRevision: 'local-vocabulary-v1:${target.localRevision}',
            learning: learning,
            voice: widget.voice,
          ),
        ),
      );
      if (summary == null || !contextCurrent()) return;
      if (summary.id != session.id ||
          summary.state != 'completed' ||
          !((summary.correctCount == 1 &&
                  summary.wrongCount == 0 &&
                  summary.score == 100) ||
              (summary.correctCount == 0 &&
                  summary.wrongCount == 1 &&
                  summary.score == 0))) {
        setState(
          () => _error = 'ยังยืนยันผลรอบนี้ไม่ได้ กรุณากลับไปเลือกกิจกรรม',
        );
        return;
      }
      if (!await validateTarget() || !mounted || !contextCurrent()) return;
      final word = session.questions.single.word;
      var resultOpen = true;
      var repairing = false;
      var dismissScheduled = false;
      final sourceRoute = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      void dismissInvalidatedFlow() {
        if (contextCurrent() || dismissScheduled) return;
        dismissScheduled = true;
        // Let each Quiz/Score continuation settle before unwinding another route.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          dismissScheduled = false;
          if (mounted &&
              resultOpen &&
              !contextCurrent() &&
              sourceRoute?.isActive == true &&
              navigator.mounted &&
              !sourceRoute!.isCurrent) {
            navigator.pop();
            dismissInvalidatedFlow();
          }
        });
      }

      _voiceContext.addListener(dismissInvalidatedFlow);
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'learning/source-voice-result',
            builder: (scoreContext) => ValueListenableBuilder<int>(
              valueListenable: _voiceContext,
              builder: (_, _, _) {
                if (!contextCurrent() || !resultOpen) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('ผลการเรียน')),
                    body: const Center(
                      child: Text('ข้อมูลเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'),
                    ),
                  );
                }
                return ScoreScreen(
                  correctAnswers: summary.correctCount,
                  wrongAnswers: summary.wrongCount,
                  score: summary.score,
                  mistakes: summary.wrongCount == 1 ? [word] : const [],
                  onPracticeMistakes: summary.wrongCount == 0
                      ? null
                      : () async {
                          if (repairing ||
                              !resultOpen ||
                              !scoreContext.mounted ||
                              ModalRoute.of(scoreContext)?.isCurrent != true) {
                            return;
                          }
                          repairing = true;
                          try {
                            if (!await validateTarget() ||
                                !contextCurrent() ||
                                !resultOpen ||
                                !scoreContext.mounted ||
                                ModalRoute.of(scoreContext)?.isCurrent !=
                                    true) {
                              if (scoreContext.mounted &&
                                  ModalRoute.of(scoreContext)?.isCurrent ==
                                      true) {
                                Navigator.of(scoreContext).pop();
                              }
                              return;
                            }
                            await AppNavigator.pushPage<void>(
                              scoreContext,
                              AppPage<void>(
                                name: 'learning/source-voice-repair',
                                builder: (_) => ValueListenableBuilder<int>(
                                  valueListenable: _voiceContext,
                                  builder: (_, _, _) =>
                                      contextCurrent() &&
                                          resultOpen &&
                                          repairing
                                      ? QuizScreen(
                                          wordIds: [word.id],
                                          learning: learning,
                                        )
                                      : Scaffold(
                                          appBar: AppBar(
                                            title: const Text('ฝึกคำที่ผิด'),
                                          ),
                                          body: const Center(
                                            child: Text(
                                              'ข้อมูลเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม',
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            );
                            if (scoreContext.mounted &&
                                ModalRoute.of(scoreContext)?.isCurrent ==
                                    true) {
                              Navigator.of(scoreContext).pop();
                            }
                          } on Object {
                            if (scoreContext.mounted &&
                                ModalRoute.of(scoreContext)?.isCurrent ==
                                    true) {
                              Navigator.of(scoreContext).pop();
                            }
                          } finally {
                            repairing = false;
                          }
                        },
                );
              },
            ),
          ),
        );
      } finally {
        resultOpen = false;
        _voiceContext.removeListener(dismissInvalidatedFlow);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'เริ่มฝึกเสียงไม่สำเร็จ กรุณาตรวจข้อความแล้วลองใหม่',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startAskLexi() async {
    if (_working || !_confirmed || _preview == null) return;
    final target = _preview!.matchedWords.first;
    setState(() => _working = true);
    try {
      final tutor = AppDependenciesScope.maybeOf(context)?.geminiTutor;
      final scope = tutor?.scope;
      final epoch = tutor?.epoch;
      final preview = await _validatedPreviewForLaunch();
      if (preview == null || !mounted) return;
      if (tutor == null ||
          scope == null ||
          scope.ownerId != _ownerId ||
          !identical(
            tutor,
            AppDependenciesScope.maybeOf(context)?.geminiTutor,
          ) ||
          tutor.scope != scope ||
          tutor.epoch != epoch) {
        setState(
          () => _error = 'ผู้ช่วย AI ไม่พร้อมสำหรับบัญชีนี้ ยังฝึกในเครื่องได้',
        );
        return;
      }
      final current = preview.matchedWords.first;
      if (current.spelling != target.spelling) {
        setState(() {
          _confirmed = false;
          _error = 'คลังคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง';
        });
        return;
      }
      final text = 'Help me understand the English word "${current.spelling}".';
      if (text.length > 500) {
        setState(
          () => _error =
              'คำนี้ยาวเกินขอบเขตคำถาม 500 ตัวอักษร ยังฝึกในเครื่องได้',
        );
        return;
      }
      final draft = TutorWordDraft(
        controller: tutor,
        ownerScope: scope,
        ownerEpoch: tutor.epoch,
        text: text,
        wordId: current.id,
        spelling: current.spelling,
      );
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'gemini/source-word-draft',
          builder: (_) => AiTutorScreen(
            voice: widget.voice,
            wordDraft: draft,
            learning: widget.learning,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'ผู้ช่วย AI ไม่พร้อมสำหรับบัญชีนี้ ยังฝึกในเครื่องได้',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<SourcePracticePreview?> _validatedPreviewForLaunch() async {
    final previous = _preview;
    final sourceName = _sourceName;
    final confirmedText = _textController.text;
    if (previous == null || sourceName == null) return null;
    try {
      final words = await _loadCurrentCategoryWords();
      if (words == null) return null;
      if (!_confirmed ||
          !identical(_preview, previous) ||
          _textController.text != confirmedText) {
        return null;
      }
      final current = reviewSourcePracticeText(
        sourceName: sourceName,
        text: confirmedText,
        words: words,
      );
      if (!mounted) return null;
      if (!_sameMatchedWords(previous.matchedWords, current.matchedWords)) {
        setState(() {
          _preview = current;
          _confirmed = false;
          _error = 'คลังคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง';
        });
        return null;
      }
      _preview = current;
      return current;
    } on SourcePracticeFailure catch (failure) {
      if (mounted) _sourceFailure(failure.code, clearFile: false);
      return null;
    }
  }

  Future<void> _showAllUnknown(List<String> words) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  'คำที่ยังไม่อยู่ในหมวด (${words.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: words.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, index) => Text(words[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _ownerStillCurrent() async {
    final expected = _ownerId;
    if (expected == null) return false;
    try {
      final current = await widget.learning.owners.getOrCreateActiveOwner();
      if (current.id == expected) return true;
    } catch (_) {}
    if (mounted) _ownerChanged();
    return false;
  }

  void _ownerChanged() {
    _voiceContext.value++;
    _textController.clear();
    setState(() {
      _sourceName = null;
      _ownerId = null;
      _preview = null;
      _confirmed = false;
      _error = 'บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเลือกไฟล์ใหม่';
    });
  }

  void _sourceFailure(String code, {bool clearFile = true}) {
    _voiceContext.value++;
    if (clearFile) {
      _textController.clear();
      _sourceName = null;
      _ownerId = null;
    }
    setState(() {
      _preview = null;
      _confirmed = false;
      _error = _failureMessage(code);
    });
  }
}

final class _SourceResultContext {
  _SourceResultContext({
    required this.epoch,
    required this.ownerId,
    required this.categoryId,
    required this.sourceName,
    required this.sourceText,
    required this.documentId,
    required this.documentRevision,
    required List<VocabularyWord> words,
    required this.learning,
    required this.vocabulary,
  }) : words = List.unmodifiable(words);

  final int epoch;
  final String ownerId;
  final String categoryId;
  final String sourceName;
  final String sourceText;
  final String documentId;
  final int documentRevision;
  final List<VocabularyWord> words;
  final LearningUseCases learning;
  final VocabularyUseCases vocabulary;
}

bool _sameWordSnapshots(List<VocabularyWord> left, List<VocabularyWord> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.id != b.id ||
        a.ownerId != b.ownerId ||
        a.categoryId != b.categoryId ||
        a.spelling != b.spelling ||
        a.meaning != b.meaning ||
        a.partOfSpeech != b.partOfSpeech ||
        a.localRevision != b.localRevision ||
        a.isDeleted != b.isDeleted) {
      return false;
    }
  }
  return true;
}

bool _sameMatchedWords(List<VocabularyWord> left, List<VocabularyWord> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].id != right[index].id) return false;
  }
  return true;
}

String _unknownSummary(List<String> words) {
  if (words.isEmpty) return 'ไม่มี';
  const visibleLimit = 50;
  final visible = words.take(visibleLimit).join(', ');
  final remaining = words.length - visibleLimit;
  return remaining > 0 ? '$visible และอีก $remaining คำ' : visible;
}

String _failureMessage(String code) => switch (code) {
  'emptyFile' => 'ไฟล์หรือข้อความว่าง',
  'fileTooLarge' => 'ไฟล์ใหญ่เกิน 1 MB',
  'unsupportedType' => 'รองรับเฉพาะไฟล์ TXT และ Markdown',
  'invalidEncoding' => 'ไฟล์ต้องเป็น UTF-8',
  'notEnglish' => 'ข้อความต้องเป็นภาษาอังกฤษเป็นหลักและมีอย่างน้อย 5 คำ',
  _ => 'อ่านไฟล์ในเครื่องไม่สำเร็จ',
};
