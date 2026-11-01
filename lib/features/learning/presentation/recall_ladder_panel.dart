import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../domain/learning_models.dart';
import '../domain/recall_ladder.dart';

class RecallLadderPanel extends StatefulWidget {
  const RecallLadderPanel({
    super.key,
    required this.reader,
    required this.ownerId,
    required this.ownerChanges,
    this.wordId,
    this.onPractice,
    this.canPractice,
  });
  final RecallLadderReader reader;
  final String ownerId;
  final Stream<String?> ownerChanges;
  final String? wordId;
  final Future<void> Function(RecallLadderStage stage, QuizWord word)?
  onPractice;
  final bool Function(RecallLadderStage stage, QuizWord word)? canPractice;

  @override
  State<RecallLadderPanel> createState() => _RecallLadderPanelState();
}

class _RecallLadderPanelState extends State<RecallLadderPanel>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _owners;
  AppDependencies? _dependencies;
  RecallLadderSnapshot? _snapshot;
  ModalRoute<Object?>? _route;
  var _configured = false;
  var _retired = false;
  var _foreground = true;
  var _covered = false;
  var _busy = false;
  var _read = 0;
  String? _error;
  bool get _visible =>
      mounted &&
      _configured &&
      !_retired &&
      _foreground &&
      (_route?.isCurrent ?? true) &&
      Visibility.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _owners = widget.ownerChanges.listen(
      (owner) {
        if (owner != widget.ownerId) _retire();
      },
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_configured && !identical(dependencies, _dependencies)) ||
        (dependencies?.recallLadder != null &&
            !identical(dependencies!.recallLadder, widget.reader))) {
      _retire();
      return;
    }
    _dependencies = dependencies;
    _route = ModalRoute.of(context);
    if (!_configured) {
      _configured = true;
      unawaited(_reload());
    }
    if (!_visible && !_covered) {
      _covered = true;
      _invalidate();
    } else if (_visible && _covered) {
      _covered = false;
      unawaited(_reload());
    }
  }

  @override
  void didUpdateWidget(RecallLadderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.reader, oldWidget.reader) ||
        widget.ownerId != oldWidget.ownerId ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges)) {
      _retire();
    } else if (widget.wordId != oldWidget.wordId) {
      _invalidate();
      unawaited(_reload());
    }
  }

  void _invalidate() {
    _read++;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _error = null;
      });
    }
  }

  void _retire() {
    _retired = true;
    _invalidate();
    unawaited(_owners?.cancel());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (_foreground) unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!_visible) return;
    final read = ++_read;
    bool current() => _visible && read == _read;
    setState(() {
      _snapshot = null;
      _error = null;
    });
    try {
      final snapshot = await widget.reader.load(
        expectedOwnerId: widget.ownerId,
        wordId: widget.wordId,
        stillCurrent: current,
      );
      if (!current() || snapshot.ownerId != widget.ownerId) return;
      setState(() => _snapshot = snapshot);
    } on Object {
      if (current()) setState(() => _error = 'อ่านคำแนะนำการฝึกไม่สำเร็จ');
    }
  }

  bool _canPractice(RecallLadderStage stage, QuizWord word) =>
      !_busy &&
      _visible &&
      widget.onPractice != null &&
      (widget.canPractice?.call(stage, word) ?? true);

  Future<void> _practice(RecallLadderStage stage) async {
    final snapshot = _snapshot;
    final word = snapshot?.word;
    if (snapshot == null || word == null || !_canPractice(stage, word)) return;
    final read = _read;
    bool current() =>
        _visible && read == _read && identical(snapshot, _snapshot);
    setState(() => _busy = true);
    var refresh = true;
    try {
      final fresh = await widget.reader.load(
        expectedOwnerId: widget.ownerId,
        wordId: word.id,
        stillCurrent: current,
      );
      if (!current() ||
          fresh.ownerId != widget.ownerId ||
          !_sameWord(fresh.word, word) ||
          !(widget.canPractice?.call(stage, word) ?? true)) {
        return;
      }
      await widget.onPractice!(stage, word);
    } on Object {
      refresh = false;
      if (current()) {
        setState(() => _error = 'เปิดกิจกรรมไม่ได้ ลองอ่านคำแนะนำใหม่');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (_visible && refresh) unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _retired = true;
    _read++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_owners?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired) return const SizedBox.shrink();
    final snapshot = _snapshot;
    final word = snapshot?.word;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'ลำดับการฝึกจากคำตอบที่บันทึก',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!)),
              TextButton.icon(
                key: const ValueKey('recall-ladder-retry'),
                onPressed: _visible && !_busy ? _reload : null,
                icon: const Icon(Icons.refresh),
                label: const Text('อ่านใหม่'),
              ),
            ] else if (snapshot == null)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังอ่านคำแนะนำการฝึก',
              ),
            if (snapshot != null && word == null)
              const Text('ยังไม่มีคำศัพท์ที่พร้อมใช้ในบัญชีนี้'),
            if (snapshot != null && word != null) ...[
              Text('คำอ้างอิง: ${word.spelling}'),
              Text(
                snapshot.observations.isEmpty
                    ? 'ยังไม่พบหลักฐานที่ใช้ได้ในรายการล่าสุด'
                    : 'อ่านคำตอบล่าสุดของคำนี้ไม่เกิน 200 รายการ',
              ),
              const Text('เป็นคำแนะนำกิจกรรม ไม่ใช่ระดับความชำนาญ'),
              if (snapshot.latest case final latest?)
                Text(
                  '${recallLadderStageLabel(latest.stage)}ล่าสุด: '
                  '${latest.isCorrect ? 'ตอบถูก' : 'ตอบผิด'}'
                  '${latest.assisted ? ' · มีตัวช่วย' : ''}'
                  '${latest.evidenceClass.name == 'pronunciation' ? ' · หลักฐานการออกเสียง' : ''}',
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('recall-ladder-suggested'),
                onPressed: _canPractice(snapshot.suggestedStage, word)
                    ? () => unawaited(_practice(snapshot.suggestedStage))
                    : null,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 64)),
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  'แนะนำ: ${recallLadderStageLabel(snapshot.suggestedStage)}',
                ),
              ),
              const SizedBox(height: 8),
              const Text('เลือกกิจกรรมต่อ จากนั้นเลือกคำหรือหมวดในกิจกรรมนั้น'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final stage in RecallLadderStage.values)
                    OutlinedButton(
                      key: ValueKey('recall-ladder-${stage.name}'),
                      onPressed: _canPractice(stage, word)
                          ? () => unawaited(_practice(stage))
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 64),
                      ),
                      child: Text(
                        '${recallLadderStageLabel(stage)}'
                        '${snapshot.observedCount(stage) == 0 ? '' : ' · พบคำตอบ ${snapshot.observedCount(stage)}'}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String recallLadderStageLabel(RecallLadderStage stage) => switch (stage) {
  RecallLadderStage.exposure => 'อ่านคำและตัวอย่าง',
  RecallLadderStage.recognition => 'เลือกความหมาย',
  RecallLadderStage.matching => 'จับคู่คำศัพท์',
  RecallLadderStage.cloze => 'เติมคำในบริบท',
  RecallLadderStage.typedRecall => 'พิมพ์จากความจำ',
  RecallLadderStage.dictation => 'ฟังแล้วพิมพ์',
  RecallLadderStage.speaking => 'ฝึกออกเสียง',
};

bool _sameWord(QuizWord? a, QuizWord b) =>
    a != null &&
    a.id == b.id &&
    a.categoryId == b.categoryId &&
    a.spelling == b.spelling &&
    a.meaning == b.meaning &&
    a.partOfSpeech == b.partOfSpeech &&
    a.contentRevision == b.contentRevision;
