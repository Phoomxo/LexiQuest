import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';
import 'result_screen.dart';

const _stageWords = <BossSpellingWord>[
  (
    word: 'ephemeral',
    meaning: 'ชั่วคราว',
    typo: 'ephemral',
    hint: 'หลังตัว m ยังมีตัว e',
    partOfSpeech: null,
    example: null,
    exampleMeaning: null,
  ),
  (
    word: 'meticulous',
    meaning: 'พิถีพิถัน',
    typo: 'meticulus',
    hint: 'ช่วงท้ายสะกดว่า -lous',
    partOfSpeech: null,
    example: null,
    exampleMeaning: null,
  ),
  (
    word: 'sustainable',
    meaning: 'ยั่งยืน',
    typo: 'sustainble',
    hint: 'สะกดส่วนท้ายว่า -able',
    partOfSpeech: 'คำคุณศัพท์',
    example: 'We need sustainable energy.',
    exampleMeaning: 'เราต้องการพลังงานที่ยั่งยืน',
  ),
];

class BossBattleScreen extends StatefulWidget {
  const BossBattleScreen({
    super.key,
    required this.onChooseGame,
    this.onReturnPractice,
  });

  final VoidCallback onChooseGame;
  final VoidCallback? onReturnPractice;

  @override
  State<BossBattleScreen> createState() => _BossBattleScreenState();
}

class _BossBattleScreenState extends State<BossBattleScreen> {
  final _answer = TextEditingController();
  final _passedWords = <BossSpellingWord>[];
  String? _submitted;
  bool _needsAnswer = false;
  bool _confirmingExit = false;
  bool _finished = false;

  void _submit() {
    if (_finished ||
        _submitted != null ||
        _confirmingExit ||
        ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    final answer = _answer.text.trim();
    if (answer.isEmpty) {
      setState(() => _needsAnswer = true);
      return;
    }
    final prompt = _stageWords[_passedWords.length];
    FocusScope.of(context).unfocus();
    if (answer.toLowerCase() != prompt.word) {
      setState(() => _submitted = answer);
      return;
    }
    setState(() {
      _passedWords.add(prompt);
      _answer.clear();
      _needsAnswer = false;
      _finished = _passedWords.length == _stageWords.length;
    });
    if (!_finished) return;
    final passedWords = List<BossSpellingWord>.unmodifiable(_passedWords);
    final onChooseGame = widget.onChooseGame;
    final onReturnPractice = widget.onReturnPractice;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/spelling-result',
        builder: (_) => ResultScreen(
          passedWords: passedWords,
          onChooseGame: onChooseGame,
          onReturnPractice: onReturnPractice,
        ),
      ),
      replace: true,
    );
  }

  Future<void> _requestExit() async {
    if (_confirmingExit ||
        _finished ||
        ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    setState(() => _confirmingExit = true);
    FocusScope.of(context).unfocus();
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('จะออกจากด่านไหม'),
        content: const Text('รอบนี้ยังเล่นไม่จบ ครั้งหน้าจะเริ่มที่คำแรก'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('เล่นคำเดิมต่อ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกไปเลือกเกม'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirmingExit = false);
    if (exit == true) widget.onChooseGame();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _passedWords.length;
    final total = _stageWords.length;
    final question = _stageWords[count.clamp(0, total - 1)];
    final submitted = _submitted;
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(
            context,
            submitted == null ? 'ด่านสะกดคำ' : 'ลองตรวจตัวสะกด',
          ),
        ),
        body: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text('ผ่านแล้ว $count จาก $total คำ'),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: count / total,
                  semanticsLabel: 'ความคืบหน้าด่าน',
                ),
                const SizedBox(height: 12),
                Text('พลังคู่ต่อสู้ ${(100 - count * 35).clamp(0, 100)}'),
                if (!_finished) ...[
                  const SizedBox(height: 16),
                  Text('คำที่ ${count + 1} จาก $total'),
                  const SizedBox(height: 12),
                  if (submitted == null) ...[
                    const Text('เขียนเป็นภาษาอังกฤษ'),
                    Text(
                      question.meaning,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _answer,
                      maxLength: maxSpellingLength,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_needsAnswer) setState(() => _needsAnswer = false);
                      },
                      decoration: InputDecoration(
                        labelText: 'คำตอบ',
                        errorText: _needsAnswer ? 'พิมพ์คำตอบก่อนส่ง' : null,
                      ),
                    ),
                    FilledButton(
                      onPressed: _submit,
                      child: const Text('ส่งคำตอบ'),
                    ),
                  ] else ...[
                    const Text('คำที่ส่ง'),
                    Text(submitted, style: theme.textTheme.headlineSmall),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        submitted.toLowerCase() == question.typo
                            ? question.hint
                            : 'ตรวจตัวสะกด เทียบกับ ${question.word}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _submitted = null),
                      child: const Text('แก้คำตอบ'),
                    ),
                  ],
                  TextButton(
                    onPressed: _requestExit,
                    child: const Text('ออกจากด่าน'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
