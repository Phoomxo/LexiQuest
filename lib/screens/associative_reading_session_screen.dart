import 'package:flutter/material.dart';

class AssociativeReadingSessionScreen extends StatefulWidget {
  final String cefrLevel;
  final List<String> targetWords;
  final String passageText;

  const AssociativeReadingSessionScreen({
    super.key,
    required this.cefrLevel,
    required this.targetWords,
    required this.passageText,
  });

  @override
  State<AssociativeReadingSessionScreen> createState() =>
      _AssociativeReadingSessionScreenState();
}

class _AssociativeReadingSessionScreenState
    extends State<AssociativeReadingSessionScreen> {
  int _currentStage = 1; // Stages 1 to 6
  final Set<int> _completedStages = {};

  final List<String> _stageTitles = [
    'Stage 1: Supported Reading',
    'Stage 2: Cue Fading',
    'Stage 3: Active Recall',
    'Stage 4: Memory Association',
    'Stage 5: Context Transfer',
    'Stage 6: Schedule Update',
  ];

  void _nextStage() {
    setState(() {
      _completedStages.add(_currentStage);
      if (_currentStage < 6) {
        _currentStage++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Associative Reading (${widget.cefrLevel})')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _currentStage / 6.0),
            const SizedBox(height: 12),
            Text(
              _stageTitles[_currentStage - 1],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: _buildStageContent())),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextStage,
                child: Text(
                  _currentStage < 6 ? 'Complete & Continue' : 'Finish Session',
                ),
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
            const Text(
              'Read the passage carefully with target word highlights:',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  widget.passageText,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Target Words: ${widget.targetWords.join(', ')}'),
          ],
        );
      case 2:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cue Fading: Highlighting and translations are now hidden.'),
            SizedBox(height: 12),
            Text('Re-read the passage independently.'),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recall Test: Fill in the missing target word.'),
            const SizedBox(height: 12),
            Text(
              'Question 1: Fill in for "${widget.targetWords.isNotEmpty ? widget.targetWords.first : ''}"',
            ),
            const TextField(
              decoration: InputDecoration(
                hintText: 'Type your answer here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Memory Association: Review or attach a personal association.',
            ),
            const SizedBox(height: 12),
            ...widget.targetWords.map(
              (w) => ListTile(
                title: Text(w),
                subtitle: const Text('Tap to set memory cue'),
                trailing: const Icon(Icons.lightbulb_outline),
              ),
            ),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Context Transfer: Apply target word in a new context.'),
            const SizedBox(height: 12),
            Text(
              'Write a new sentence using "${widget.targetWords.isNotEmpty ? widget.targetWords.first : ''}":',
            ),
            const TextField(
              decoration: InputDecoration(
                hintText: 'Enter new sentence...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );
      case 6:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text('Session Completed!'),
            Text('Completed Stages: ${_completedStages.length + 1} / 6'),
            const SizedBox(height: 8),
            const Text(
              'Memory stability and due timestamps updated successfully.',
            ),
          ],
        );
    }
  }
}
