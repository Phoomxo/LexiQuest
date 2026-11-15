import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

typedef _LearningPack = ({
  String title,
  String level,
  String objective,
  String revision,
  List<(String, String)> words,
});

const _samplePacks = <_LearningPack>[
  (
    title: 'การเดินทาง',
    level: 'A2',
    objective: 'อ่านป้ายที่สถานี',
    revision: 'LQ-TR-01',
    words: [('station', 'สถานี'), ('platform', 'ชานชาลา')],
  ),
  (
    title: 'ของใช้ในครัว',
    level: 'A1',
    objective: 'เรียกชื่อของที่ใช้ทุกวัน',
    revision: 'LQ-KT-01',
    words: [('cup', 'ถ้วย'), ('spoon', 'ช้อน')],
  ),
];

class LearningPackCatalogScreen extends StatelessWidget {
  const LearningPackCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => _PackPage(
    title: 'เลือกชุดคำศัพท์',
    returnLabel: 'กลับคลังคำ',
    children: [
      const Text('ชุดเรียนตัวอย่างในเครื่อง'),
      const SizedBox(height: 12),
      for (final pack in _samplePacks)
        Card.outlined(
          child: ListTile(
            title: Text(pack.title),
            subtitle: Text('${pack.level} · ${pack.objective}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _open(context, pack.revision, _PackDetails(pack: pack)),
          ),
        ),
    ],
  );
}

class _PackDetails extends StatelessWidget {
  const _PackDetails({required this.pack});

  final _LearningPack pack;

  @override
  Widget build(BuildContext context) => _PackPage(
    title: pack.title,
    returnLabel: 'ดูชุดเรียนทั้งหมด',
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
            title: 'คำศัพท์ในชุด',
            returnLabel: 'กลับไปดูชุดเรียน',
            children: [
              for (final (spelling, meaning) in pack.words)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(spelling),
                  subtitle: Text(meaning),
                ),
            ],
          ),
        ),
        child: const Text('คำศัพท์ในชุด'),
      ),
      OutlinedButton(
        onPressed: () =>
            _open(context, '${pack.revision}/source', _PackSource(pack: pack)),
        child: const Text('ที่มาของชุดเรียน'),
      ),
    ],
  );
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
