import 'package:flutter/material.dart';

import 'fill_in_the_blanks_screen.dart';
import '../navigation/app_routes.dart';

List<String> createStableScramble(String word) {
  final letters = word.characters.toList();
  if (letters.length < 2) return letters;
  var shift =
      word.runes.fold<int>(0, (sum, rune) => sum + rune) % letters.length;
  if (shift == 0) shift = 1;
  final result = <String>[...letters.skip(shift), ...letters.take(shift)];
  if (result.join() == word) {
    final different = result.indexWhere((letter) => letter != result.first);
    if (different > 0) {
      final first = result.first;
      result[0] = result[different];
      result[different] = first;
    }
  }
  return result;
}

class WordScrambleScreen extends StatefulWidget {
  final String word;

  const WordScrambleScreen({super.key, required this.word});

  @override
  State<WordScrambleScreen> createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  List<String> scrambledLetters = [];
  List<String?> userAnswer = [];
  List<int> usedIndexes = [];

  @override
  void initState() {
    super.initState();
    _scrambleWord();
  }

  void _scrambleWord() {
    scrambledLetters = createStableScramble(widget.word);
    userAnswer = List.filled(scrambledLetters.length, null);
    usedIndexes.clear();
  }

  void _checkAnswer() {
    if (userAnswer.join() == widget.word) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ถูกต้อง กำลังไปหน้าถัดไป')));
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: 'learning/fill-blanks',
              builder: (context) => FillInTheBlanksScreen(word: widget.word),
            ),
            replace: true,
          );
        }
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ยังไม่ถูก ลองอีกครั้ง')));
    }
  }

  void _resetGame() {
    setState(() {
      _scrambleWord();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เกมเรียงตัวอักษร')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(scrambledLetters.length, (index) {
                    return DragTarget<int>(
                      onWillAcceptWithDetails: (details) =>
                          userAnswer[index] == null,
                      onAcceptWithDetails: (details) {
                        setState(() {
                          userAnswer[index] = scrambledLetters[details.data];
                          usedIndexes.add(details.data);
                        });
                      },
                      builder: (context, candidateData, rejectedData) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.all(5),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: userAnswer[index] != null
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            userAnswer[index] ?? "",
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(scrambledLetters.length, (index) {
                    return Visibility(
                      visible: !usedIndexes.contains(index),
                      child: Draggable<int>(
                        data: index,
                        feedback: Material(
                          child: _buildLetterTile(
                            scrambledLetters[index],
                            isDragging: true,
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.0,
                          child: _buildLetterTile(scrambledLetters[index]),
                        ),
                        child: _buildLetterTile(scrambledLetters[index]),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _checkAnswer,
                  child: const Text('ตรวจสอบคำตอบ'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _resetGame,
                  child: const Text('เริ่มใหม่'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLetterTile(String letter, {bool isDragging = false}) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDragging
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        letter,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
