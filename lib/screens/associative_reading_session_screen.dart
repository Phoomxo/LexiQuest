import 'package:flutter/material.dart';

import '../learning/associative_reading_coordinator.dart';
import '../learning/reading_session.dart';
import '../learning/recall_attempt.dart';

class AssociativeReadingSessionScreen extends StatefulWidget {
  const AssociativeReadingSessionScreen({
    super.key,
    required this.coordinator,
    required this.initialState,
  });

  final AssociativeReadingCoordinator coordinator;
  final AssociativeReadingState initialState;

  @override
  State<AssociativeReadingSessionScreen> createState() =>
      _AssociativeReadingSessionScreenState();
}

class _AssociativeReadingSessionScreenState
    extends State<AssociativeReadingSessionScreen> {
  late AssociativeReadingState _state;
  final _answerController = TextEditingController();
  var _busy = false;
  var _stageStarted = DateTime.now();

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _state.session.currentStage;
    return Scaffold(
      appBar: AppBar(
        title: Text('Associative Reading (${_state.session.cefrLevel})'),
        actions: [
          if (!_terminal(stage))
            IconButton(
              tooltip: 'Abandon session',
              onPressed: _busy ? null : () => _run(widget.coordinator.abandon),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: _progress(stage)),
              const SizedBox(height: 16),
              Text(
                _title(stage),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Expanded(child: SingleChildScrollView(child: _content(stage))),
              if (!_terminal(stage)) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : () => _primaryIntent(stage),
                  child: Text(_buttonLabel(stage)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(ReadingSessionStage stage) {
    switch (stage) {
      case ReadingSessionStage.supportedReading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_state.content.passage),
            const SizedBox(height: 12),
            Text('Target words: ${_state.session.targetWordKeys.join(', ')}'),
          ],
        );
      case ReadingSessionStage.cueFading:
        return Text(_state.content.passage);
      case ReadingSessionStage.recall:
        return _answerField('Type the missing target word');
      case ReadingSessionStage.association:
        return const Text(
          'Review or create a private memory cue before continuing.',
        );
      case ReadingSessionStage.transfer:
        return _answerField('Use the target word in a new sentence');
      case ReadingSessionStage.scheduling:
        return const Text('Your local evidence is ready to schedule.');
      case ReadingSessionStage.completed:
        return const Text('Session evidence was saved successfully.');
      case ReadingSessionStage.abandoned:
        return const Text('Session abandoned. Your prior evidence was kept.');
    }
  }

  Widget _answerField(String hint) {
    return TextField(
      controller: _answerController,
      enabled: !_busy,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _primaryIntent(ReadingSessionStage stage) async {
    switch (stage) {
      case ReadingSessionStage.supportedReading:
      case ReadingSessionStage.cueFading:
      case ReadingSessionStage.association:
        await _run(widget.coordinator.advance);
      case ReadingSessionStage.recall:
      case ReadingSessionStage.transfer:
        final answer = _answerController.text.trim();
        if (answer.isEmpty) return;
        final target = _state.session.targetWordKeys.first;
        await _run(
          () => widget.coordinator.submit(
            ReadingAnswerSubmission(
              wordKey: target,
              correct: stage == ReadingSessionStage.recall
                  ? answer.toLowerCase() == target.toLowerCase()
                  : answer.toLowerCase().contains(target.toLowerCase()),
              responseTimeMs: DateTime.now()
                  .difference(_stageStarted)
                  .inMilliseconds,
              confidence: 3,
              cueLevel: RecallCueLevel.none,
            ),
          ),
        );
      case ReadingSessionStage.scheduling:
        await _run(widget.coordinator.finalize);
      case ReadingSessionStage.completed:
      case ReadingSessionStage.abandoned:
        return;
    }
  }

  Future<void> _run(Future<AssociativeReadingState> Function() intent) async {
    setState(() => _busy = true);
    try {
      final next = await intent();
      if (!mounted) return;
      setState(() {
        _state = next;
        _busy = false;
        _answerController.clear();
        _stageStarted = DateTime.now();
      });
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this step. Try again.')),
      );
    }
  }
}

String _title(ReadingSessionStage stage) => switch (stage) {
  ReadingSessionStage.supportedReading => 'Supported Reading',
  ReadingSessionStage.cueFading => 'Cue Fading',
  ReadingSessionStage.recall => 'Recall',
  ReadingSessionStage.association => 'Association',
  ReadingSessionStage.transfer => 'Transfer',
  ReadingSessionStage.scheduling => 'Scheduling',
  ReadingSessionStage.completed => 'Completed',
  ReadingSessionStage.abandoned => 'Abandoned',
};

String _buttonLabel(ReadingSessionStage stage) => switch (stage) {
  ReadingSessionStage.recall || ReadingSessionStage.transfer => 'Submit',
  ReadingSessionStage.scheduling => 'Finish',
  _ => 'Continue',
};

double _progress(ReadingSessionStage stage) => switch (stage) {
  ReadingSessionStage.supportedReading => 1 / 6,
  ReadingSessionStage.cueFading => 2 / 6,
  ReadingSessionStage.recall => 3 / 6,
  ReadingSessionStage.association => 4 / 6,
  ReadingSessionStage.transfer => 5 / 6,
  ReadingSessionStage.scheduling ||
  ReadingSessionStage.completed ||
  ReadingSessionStage.abandoned => 1,
};

bool _terminal(ReadingSessionStage stage) {
  return stage == ReadingSessionStage.completed ||
      stage == ReadingSessionStage.abandoned;
}
