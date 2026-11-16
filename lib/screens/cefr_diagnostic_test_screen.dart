import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

class CefrDiagnosticTestScreen extends StatefulWidget {
  const CefrDiagnosticTestScreen({
    super.key,
    this.suggestedDeckBuilder,
    this.suggestedArticleBuilder,
    this.suggestedArticleTitle,
  });

  final Widget Function(BuildContext context, String level)?
  suggestedDeckBuilder;
  final Widget Function(BuildContext context, String level)?
  suggestedArticleBuilder;
  final String Function(String level)? suggestedArticleTitle;

  @override
  State<CefrDiagnosticTestScreen> createState() =>
      _CefrDiagnosticTestScreenState();
}

class _CefrDiagnosticTestScreenState extends State<CefrDiagnosticTestScreen> {
  static const _questions = [
    (
      word: 'apple',
      prompt: 'คำนี้หมายถึงอะไร',
      options: ['กล้วย', 'แอปเปิล', 'ส้ม', 'มะม่วง'],
      correctIndex: 1,
    ),
    (
      word: 'journey',
      prompt: 'คำไหนมีความหมายใกล้กัน',
      options: ['Food', 'House', 'Trip', 'Book'],
      correctIndex: 2,
    ),
    (
      word: 'achieve',
      prompt: 'คำนี้หมายถึงอะไร',
      options: ['บรรลุเป้าหมาย', 'ล้มเหลว', 'ปฏิเสธ', 'ละทิ้ง'],
      correctIndex: 0,
    ),
    (
      word: 'innovative',
      prompt: 'คำไหนใกล้เคียงที่สุด',
      options: ['โบราณ', 'ธรรมดา', 'น่าเบื่อ', 'ที่นำเสนอสิ่งใหม่'],
      correctIndex: 3,
    ),
    (
      word: 'ubiquitous',
      prompt: 'เลือกความหมายภาษาอังกฤษ',
      options: ['Rare', 'Present everywhere', 'Hidden', 'Ancient'],
      correctIndex: 1,
    ),
  ];
  static const _suggestedLevels = ['A1', 'A1', 'A2', 'B1', 'B2', 'C1'];

  final _headingFocus = FocusNode(debugLabel: 'Sample survey heading');
  int _answered = 0;
  int _score = 0;

  void _answer(int questionIndex, int optionIndex) {
    if (questionIndex != _answered ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      if (optionIndex == _questions[questionIndex].correctIndex) _score++;
      _answered++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _headingFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _headingFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complete = _answered == _questions.length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          complete ? 'ผลที่ลองตอบ' : 'ลองตอบก่อนเลือกระดับ',
        ),
      ),
      body: SafeArea(
        child: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: ListView(
            key: ValueKey(_answered),
            padding: const EdgeInsets.all(24),
            children: complete ? _result(context) : _question(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _question(BuildContext context) {
    final index = _answered;
    final question = _questions[index];
    final progress = 'ข้อ ${index + 1} จาก ${_questions.length}';
    final styles = Theme.of(context).textTheme;
    return [
      Text(progress, style: styles.labelLarge),
      const SizedBox(height: 8),
      ExcludeSemantics(
        child: LinearProgressIndicator(value: (index + 1) / _questions.length),
      ),
      const SizedBox(height: 24),
      Text(question.prompt, style: styles.titleMedium),
      Focus(
        focusNode: _headingFocus,
        skipTraversal: true,
        child: Semantics(
          header: true,
          liveRegion: true,
          label: '$progress ${question.prompt}',
          child: Text(question.word, style: styles.headlineLarge),
        ),
      ),
      const SizedBox(height: 20),
      for (final (optionIndex, option) in question.options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () => _answer(index, optionIndex),
            child: Text(option, textAlign: TextAlign.center),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('พักแล้วกลับไปเลือกบทเรียน'),
      ),
    ];
  }

  List<Widget> _result(BuildContext context) {
    final deckLevel = _suggestedLevels[_score];
    final displayLevel = _score == _questions.length ? 'C1 หรือ C2' : deckLevel;
    final recommendation = 'ระดับคำที่แนะนำ · $displayLevel';
    final readingLevel = _score < 2 ? 'A1' : 'A2';
    final deckBuilder = widget.suggestedDeckBuilder;
    final articleBuilder = widget.suggestedArticleBuilder;
    return [
      Text('แบบสำรวจคำศัพท์ ${_questions.length} ข้อ'),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(
                focusNode: _headingFocus,
                skipTraversal: true,
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  label: 'ข้อที่ตอบถูก',
                  child: Text(
                    '$_score / ${_questions.length}',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
              ),
              const Text('ข้อที่ตอบถูก'),
              const SizedBox(height: 8),
              const Text('ใช้ผลชุดสั้นนี้เลือกบทเรียนถัดไป'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (deckBuilder == null)
        Text(recommendation)
      else
        OutlinedButton(
          onPressed: () => _open(
            'learning/cefr/suggested-deck',
            (context) => deckBuilder(context, deckLevel),
          ),
          child: Text(recommendation, textAlign: TextAlign.center),
        ),
      if (articleBuilder != null)
        FilledButton(
          onPressed: () => _open(
            'learning/cefr/suggested-reading',
            (_) => _SuggestedReading(
              level: readingLevel,
              title: widget.suggestedArticleTitle?.call(readingLevel),
              articleBuilder: articleBuilder,
            ),
          ),
          child: const Text('ดูบทอ่านที่แนะนำ'),
        ),
      TextButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('เลือกบทเรียนเอง'),
      ),
    ];
  }

  void _open(String name, WidgetBuilder builder) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: builder),
    );
  }
}

class _SuggestedReading extends StatelessWidget {
  const _SuggestedReading({
    required this.level,
    required this.title,
    required this.articleBuilder,
  });

  final String level;
  final String? title;
  final Widget Function(BuildContext context, String level) articleBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'บทอ่านที่แนะนำ'),
      ),
      body: SafeArea(
        child: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('บทอ่าน $level'),
              if (title != null) ...[
                const SizedBox(height: 8),
                Text(title!, style: Theme.of(context).textTheme.headlineSmall),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (ModalRoute.of(context)?.isCurrent != true) return;
                  AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'learning/cefr/recommended-article',
                      builder: (context) => articleBuilder(context, level),
                    ),
                  );
                },
                child: const Text('เริ่มอ่านเรื่องนี้'),
              ),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('กลับไปดูผลเดิม'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
