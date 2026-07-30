import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../runtime/app_dependencies.dart';

class AssociativeReadingSessionScreen extends StatefulWidget {
  const AssociativeReadingSessionScreen({
    super.key,
    required this.cefrLevel,
    required this.targetWords,
    required this.passageText,
    this.documentId,
    this.documentRevision = 1,
    this.learning,
  });

  final String cefrLevel;
  final List<String> targetWords;
  final String passageText;
  final String? documentId;
  final int documentRevision;
  final LearningUseCases? learning;

  @override
  State<AssociativeReadingSessionScreen> createState() =>
      _AssociativeReadingSessionScreenState();
}

class _AssociativeReadingSessionScreenState
    extends State<AssociativeReadingSessionScreen>
    with WidgetsBindingObserver {
  static const _stageTitles = <String>[
    'Stage 1: Supported Reading',
    'Stage 2: Cue Fading',
    'Stage 3: Active Recall',
    'Stage 4: Memory Association',
    'Stage 5: Context Transfer',
    'Stage 6: Finish',
  ];

  LearningUseCases? _learning;
  int _currentStage = 1;
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;

  String get _documentId {
    final supplied = widget.documentId?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    var hash = 2166136261;
    for (final unit in '${widget.cefrLevel}:${widget.passageText}'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return 'reading:$hash';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading || _learning != null) return;
    _learning =
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    final learning = _learning;
    if (learning == null) {
      setState(() => _loading = false);
      return;
    }
    learning
        .loadReadingProgress(
          documentId: _documentId,
          documentRevision: widget.documentRevision,
        )
        .then((progress) {
          if (!mounted) return;
          setState(() {
            _currentStage = (progress?.lastPosition ?? 1).clamp(1, 6);
            _completed = progress?.isCompleted ?? false;
            _loading = false;
          });
        })
        .catchError((Object _) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_checkpoint(isCompleted: false, showFailure: false));
    }
  }

  Future<void> _nextStage() async {
    if (_saving) return;
    final finishing = _currentStage == 6;
    final nextStage = finishing ? 6 : _currentStage + 1;
    setState(() => _saving = true);
    final saved = await _checkpoint(
      position: nextStage,
      isCompleted: finishing,
      showFailure: true,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    if (finishing) {
      setState(() {
        _saving = false;
        _completed = true;
      });
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _currentStage = nextStage;
      _saving = false;
    });
  }

  Future<bool> _checkpoint({
    int? position,
    required bool isCompleted,
    required bool showFailure,
  }) async {
    final learning = _learning;
    if (learning == null) return true;
    try {
      await learning.saveReadingProgress(
        documentId: _documentId,
        documentRevision: widget.documentRevision,
        position: position ?? _currentStage,
        isCompleted: isCompleted,
      );
      return true;
    } catch (_) {
      if (showFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Associative Reading (${widget.cefrLevel})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _currentStage / 6),
                  const SizedBox(height: 12),
                  Text(
                    _stageTitles[_currentStage - 1],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(child: _buildStageContent()),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving || _completed ? null : _nextStage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(
                      _currentStage < 6
                          ? 'Complete & Continue'
                          : 'Finish Session',
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStageContent() {
    switch (_currentStage) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Read the passage and notice the target words.'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.passageText),
              ),
            ),
            const SizedBox(height: 12),
            Text('Target Words: ${widget.targetWords.join(', ')}'),
          ],
        );
      case 2:
        return const Text(
          'Cue Fading: re-read the passage without translations or highlights.',
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recall Test: type the missing target word.'),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: widget.targetWords.isEmpty
                    ? 'Type your answer'
                    : 'Recall: ${widget.targetWords.first}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review the memory cues you created for these words.'),
            ...widget.targetWords.map(
              (word) => ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(word),
              ),
            ),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use one target word in a new sentence.'),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter a new sentence',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );
      case 6:
      default:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fact_check_outlined, size: 48),
            SizedBox(height: 12),
            Text('Ready to finish'),
            SizedBox(height: 8),
            Text(
              'Tap Finish Session to save completion. SRS changes only when an answer is recorded.',
            ),
          ],
        );
    }
  }
}
