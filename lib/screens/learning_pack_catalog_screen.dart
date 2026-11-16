import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../ai/ai_models.dart' show CefrLevel;
import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

typedef _LearningPack = ({
  String title,
  String level,
  String objective,
  String skill,
  String goal,
  String revision,
  List<(String, String)> words,
});

const _samplePacks = <_LearningPack>[
  (
    title: 'การเดินทาง',
    level: 'A2',
    objective: 'อ่านป้ายที่สถานี',
    skill: 'อ่าน',
    goal: 'เดินทางเอง',
    revision: 'LQ-TR-01',
    words: [('station', 'สถานี'), ('platform', 'ชานชาลา')],
  ),
  (
    title: 'ของใช้ในครัว',
    level: 'A1',
    objective: 'เรียกชื่อของที่ใช้ทุกวัน',
    skill: 'นึกความหมาย',
    goal: 'ใช้คำในบ้าน',
    revision: 'LQ-KT-01',
    words: [('cup', 'ถ้วย'), ('spoon', 'ช้อน')],
  ),
];

enum _PackFilter {
  level('ระดับภาษา'),
  topic('หัวข้อ'),
  skill('ทักษะ'),
  goal('เป้าหมาย');

  const _PackFilter(this.label);

  final String label;

  String valueOf(_LearningPack pack) => switch (this) {
    level => pack.level,
    topic => pack.title,
    skill => pack.skill,
    goal => pack.goal,
  };

  Iterable<String> get options => this == level
      ? CefrLevel.values
            .where((level) => level != CefrLevel.unknown)
            .map((level) => level.wire.toUpperCase())
      : _samplePacks.map(valueOf).toSet();
}

typedef _FilterSelection = (_PackFilter, String);

class LearningPackCatalogScreen extends StatefulWidget {
  const LearningPackCatalogScreen({super.key});

  @override
  State<LearningPackCatalogScreen> createState() => _LearningPackCatalogState();
}

class _LearningPackCatalogState extends State<LearningPackCatalogScreen> {
  _FilterSelection? _selection;

  Future<void> _chooseFilter() async {
    if (ModalRoute.isCurrentOf(context) != true) return;
    final selected = await AppNavigator.pushPage<_FilterSelection>(
      context,
      AppPage<_FilterSelection>(
        name: 'vocabulary/learning-packs/filter',
        builder: (filterContext) => _PackPage(
          title: 'ค้นชุดที่เหมาะกับฉัน',
          returnLabel: 'กลับไปดูชุดเรียน',
          children: [
            for (final filter in _PackFilter.values)
              OutlinedButton(
                onPressed: () => _chooseValue(filterContext, filter),
                child: Text(filter.label),
              ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _selection = selected);
  }

  Future<void> _chooseValue(BuildContext context, _PackFilter filter) async {
    if (ModalRoute.isCurrentOf(context) != true) return;
    final selected = await AppNavigator.pushPage<String>(
      context,
      AppPage<String>(
        name: 'vocabulary/learning-packs/filter/${filter.name}',
        builder: (optionContext) => _PackPage(
          title: 'เลือก${filter.label}',
          returnLabel: 'กลับไปเลือกตัวกรอง',
          children: [
            for (final value in filter.options)
              OutlinedButton(
                onPressed: () {
                  if (ModalRoute.isCurrentOf(optionContext) == true) {
                    Navigator.pop(optionContext, value);
                  }
                },
                child: Text(value),
              ),
          ],
        ),
      ),
    );
    if (selected != null &&
        context.mounted &&
        ModalRoute.isCurrentOf(context) == true) {
      Navigator.pop(context, (filter, selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final packs = selection == null
        ? _samplePacks
        : _samplePacks
              .where((pack) => selection.$1.valueOf(pack) == selection.$2)
              .toList();
    return _PackPage(
      title: 'เลือกชุดคำศัพท์',
      returnLabel: 'กลับคลังคำ',
      children: [
        if (selection case (final filter, final value)) ...[
          Semantics(
            liveRegion: true,
            child: Text('${filter.label} · $value · พบ ${packs.length} ชุด'),
          ),
          TextButton(
            onPressed: () => setState(() => _selection = null),
            child: const Text('ล้างตัวกรอง'),
          ),
        ] else
          const Text('ชุดเรียนตัวอย่างในเครื่อง'),
        OutlinedButton(
          onPressed: _chooseFilter,
          child: const Text(
            'เลือกตามระดับหรือสิ่งที่อยากฝึก',
            textAlign: TextAlign.center,
          ),
        ),
        if (packs.isEmpty) const Text('ไม่พบชุดตัวอย่างที่ตรงกับตัวกรอง'),
        for (final pack in packs)
          Card.outlined(
            child: ListTile(
              title: Text(pack.title),
              subtitle: Text('${pack.level} · ${pack.objective}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(
                context,
                pack.revision,
                _PackDetails(
                  pack: pack,
                  catalogReturnLabel: selection == null
                      ? 'ดูชุดเรียนทั้งหมด'
                      : 'กลับไปดูชุดที่ตรงกัน',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PackDetails extends StatefulWidget {
  const _PackDetails({required this.pack, required this.catalogReturnLabel});

  final _LearningPack pack;
  final String catalogReturnLabel;

  @override
  State<_PackDetails> createState() => _PackDetailsState();
}

class _PackDetailsState extends State<_PackDetails> {
  int _reviewedCount = 0;

  _LearningPack get pack => widget.pack;

  Future<void> _chooseReview() async {
    if (ModalRoute.isCurrentOf(context) != true || pack.words.isEmpty) return;
    final selected = await AppNavigator.pushPage<bool>(
      context,
      AppPage<bool>(
        name: 'vocabulary/learning-packs/${pack.revision}/method',
        builder: (methodContext) => _PackPage(
          title: 'เลือกวิธีฝึก',
          returnLabel: 'กลับไปดูชุดเรียน',
          children: [
            Text('${pack.title} · ${pack.words.length} คำ'),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: () {
                if (ModalRoute.isCurrentOf(methodContext) == true) {
                  Navigator.pop(methodContext, true);
                }
              },
              child: const Text('ทบทวนด้วยบัตรคำ'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected != true) return;
    _open(
      context,
      '${pack.revision}/review',
      _PackReview(
        pack: pack,
        onCompleted: (count) {
          if (mounted) setState(() => _reviewedCount = count);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _PackPage(
    title: pack.title,
    returnLabel: _reviewedCount > 0
        ? 'เลือกชุดอื่น'
        : widget.catalogReturnLabel,
    children: [
      Text('${pack.level} · ${pack.words.length} คำ'),
      const SizedBox(height: 12),
      Text(pack.objective, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: () => _open(
          context,
          '${pack.revision}/words',
          _PackPage(
            title: _reviewedCount > 0 ? 'คำที่เพิ่งทบทวน' : 'คำศัพท์ในชุด',
            returnLabel: _reviewedCount > 0
                ? 'กลับไปดูผลการทบทวน'
                : 'กลับไปดูชุดเรียน',
            children: _wordRows(pack),
          ),
        ),
        child: Text(_reviewedCount > 0 ? 'ดูคำที่เพิ่งทบทวน' : 'คำศัพท์ในชุด'),
      ),
      OutlinedButton(
        onPressed: () =>
            _open(context, '${pack.revision}/source', _PackSource(pack: pack)),
        child: const Text('ที่มาของชุดเรียน'),
      ),
      const SizedBox(height: 12),
      if (_reviewedCount > 0) ...[
        const Text('ผลจากรอบตัวอย่างเมื่อสักครู่'),
        Text('เปิดทบทวนแล้ว $_reviewedCount จาก ${pack.words.length} คำ'),
      ] else
        const Text('ยังไม่ได้เริ่มทบทวนตัวอย่าง'),
      const SizedBox(height: 12),
      FilledButton.tonal(
        onPressed: pack.words.isEmpty ? null : _chooseReview,
        child: const Text('เลือกวิธีฝึก'),
      ),
    ],
  );
}

List<Widget> _wordRows(_LearningPack pack) => [
  for (final (spelling, meaning) in pack.words)
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(spelling),
      subtitle: Text(meaning),
    ),
];

class _PackReview extends StatefulWidget {
  const _PackReview({required this.pack, required this.onCompleted});

  final _LearningPack pack;
  final ValueChanged<int> onCompleted;

  @override
  State<_PackReview> createState() => _PackReviewState();
}

class _PackReviewState extends State<_PackReview> {
  int _index = 0;
  bool _revealed = false;
  bool _finished = false;

  void _advance() {
    if (_finished || !_revealed) return;
    if (_index + 1 == widget.pack.words.length) {
      setState(() => _finished = true);
      widget.onCompleted(_index + 1);
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    if (_finished) {
      return _PackPage(
        title: 'ทบทวนครบ ${pack.words.length} คำแล้ว',
        returnLabel: 'กลับไปดูชุดที่เพิ่งฝึก',
        children: [Text(pack.title), ..._wordRows(pack)],
      );
    }

    final (spelling, meaning) = pack.words[_index];
    final text = Theme.of(context).textTheme;
    return _PackPage(
      title: _revealed ? 'เทียบกับคำที่นึกไว้' : 'นึกความหมาย',
      returnLabel: 'กลับไปดูชุดเรียน',
      children: [
        Text('${pack.title} · คำที่ ${_index + 1} จาก ${pack.words.length}'),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(spelling, style: text.headlineMedium),
        ),
        if (_revealed)
          Semantics(
            liveRegion: true,
            child: Text(meaning, style: text.titleLarge),
          )
        else
          const Text('ลองนึกความหมายด้วยตัวเอง'),
        const SizedBox(height: 24),
        if (_revealed) ...[
          FilledButton(
            onPressed: _advance,
            child: Text(
              _index + 1 == pack.words.length ? 'จบการทบทวน' : 'ทบทวนคำถัดไป',
            ),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _revealed = false),
            child: const Text('ลองนึกอีกครั้ง'),
          ),
        ] else
          FilledButton(
            onPressed: () => setState(() => _revealed = true),
            child: const Text('เปิดคำแปล'),
          ),
      ],
    );
  }
}

class _PackSource extends StatelessWidget {
  const _PackSource({required this.pack});

  final _LearningPack pack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canonicalWords = pack.words
        .map((word) => '${word.$1}\t${word.$2}')
        .join('\n');
    final digest = sha256.convert(utf8.encode(canonicalWords)).toString();
    return _PackPage(
      title: 'ที่มาของชุดเรียน',
      returnLabel: 'กลับไปดูชุดเรียน',
      children: [
        Text('${pack.title} · ${pack.revision}', style: text.titleLarge),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text('ผู้จัดทำ', style: text.titleMedium),
        ),
        const Text('ตัวอย่างประกอบการออกแบบของ LexiQuest'),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text('สถานะการตรวจ', style: text.titleMedium),
        ),
        const Text('ร่างตัวอย่าง ยังไม่เผยแพร่ให้ผู้เรียน'),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text('รหัสตรวจสอบรายการคำ · SHA-256', style: text.titleMedium),
        ),
        Text(
          digest,
          textDirection: TextDirection.ltr,
          style: text.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

void _open(BuildContext context, String name, Widget screen) {
  if (ModalRoute.isCurrentOf(context) != true) return;
  AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: 'vocabulary/learning-packs/$name',
      builder: (_) => screen,
    ),
  );
}

class _PackPage extends StatelessWidget {
  const _PackPage({
    required this.title,
    required this.returnLabel,
    required this.children,
  });

  final String title;
  final String returnLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, title),
    ),
    body: AdaptiveContentPane(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ...children,
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: Text(returnLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    ),
  );
}
