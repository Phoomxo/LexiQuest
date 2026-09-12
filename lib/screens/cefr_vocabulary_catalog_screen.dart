import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/vocabulary/application/cefr_catalog_import.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/cefr_vocabulary_catalog.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';
import 'cefr_vocabulary_detail_screen.dart';

class CefrVocabularyCatalogScreen extends StatefulWidget {
  const CefrVocabularyCatalogScreen({super.key, this.catalog, this.vocabulary});
  final Future<CefrVocabularyCatalog>? catalog;
  final VocabularyUseCases? vocabulary;
  @override
  State<CefrVocabularyCatalogScreen> createState() => _CatalogState();
}

class _CatalogState extends State<CefrVocabularyCatalogScreen> {
  late Future<CefrVocabularyCatalog> _catalog =
      widget.catalog ?? CefrVocabularyCatalog.load();
  String _query = '';
  String? _level;
  bool _busy = false;

  VocabularyUseCases? get _vocabulary {
    if (widget.vocabulary != null) return widget.vocabulary;
    final dependencies = AppDependenciesScope.maybeOf(context);
    return dependencies?.features.isEnabled(Feature.vocabulary) == true
        ? dependencies?.vocabulary
        : null;
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _licenses() async {
    try {
      final texts = await Future.wait(
        [
          'assets/content/cefr_editorial/NOTICE.txt',
          'assets/content/cefr_expanded/NOTICE.txt',
          for (final name in ['NOTICE.txt', 'LICENSE.txt', 'LICENSE-th.txt'])
            'assets/content/cefr_starter/$name',
        ].map(rootBundle.loadString),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('แหล่งข้อมูลและสิทธิ์ใช้งาน'),
          scrollable: true,
          content: SelectableText(texts.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
    } catch (_) {
      _message('ยังเปิดรายละเอียดแหล่งข้อมูลไม่ได้');
    }
  }

  Future<void> _chooseMeaning(
    CefrVocabularyCatalog catalog,
    CefrCatalogWord word,
  ) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) =>
            CefrVocabularyDetailScreen(word: word, canAdd: _vocabulary != null),
      ),
    );
    if (index != null && mounted) await _add(catalog, word, index);
  }

  Future<void> _add(
    CefrVocabularyCatalog catalog,
    CefrCatalogWord word,
    int index,
  ) async {
    final vocabulary = _vocabulary;
    if (_busy || vocabulary == null) return;
    setState(() => _busy = true);
    try {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      final categories = (await vocabulary.watchCategories().first)
          .where(
            (category) =>
                category.ownerId == owner.id &&
                !category.isReadOnly &&
                !category.isDeleted,
          )
          .toList();
      if (!mounted) return;
      if (categories.isEmpty) {
        _message('สร้างหมวดหมู่ในแท็บคลังคำศัพท์ก่อน แล้วกลับมาเลือกคำได้เลย');
        return;
      }
      final category = await showDialog<VocabularyCategory>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('เพิ่มลงหมวดหมู่'),
          children: [
            for (final category in categories)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, category),
                child: Text(category.name),
              ),
          ],
        ),
      );
      if (category == null || !mounted) return;
      if (!identical(_vocabulary, vocabulary)) {
        throw StateError('Vocabulary availability changed');
      }
      await CefrCatalogImport(vocabulary: vocabulary, catalog: catalog).add(
        wordId: word.id,
        meaningIndex: index < 0 ? 0 : index,
        useEditorial: index < 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      _message('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้');
    } on CategoryWordLimitFailure catch (_) {
      _message('หมวดหมู่นี้ครบ 50 คำแล้ว กรุณาเลือกหมวดหมู่อื่น');
    } on VocabularyNotFoundFailure catch (_) {
      _message('หมวดหมู่เปลี่ยนไปแล้ว กรุณาเลือกใหม่');
    } catch (_) {
      _message('ยังเพิ่มคำไม่ได้ กรุณาลองใหม่ ข้อมูลเดิมยังคงอยู่');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('คำศัพท์ CEFR'),
      actions: [
        IconButton(
          tooltip: 'แหล่งข้อมูลและสิทธิ์ใช้งาน',
          onPressed: _licenses,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: FutureBuilder<CefrVocabularyCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ยังเปิดคลังคำศัพท์ไม่ได้'),
                TextButton(
                  onPressed: () =>
                      setState(() => _catalog = CefrVocabularyCatalog.load()),
                  child: const Text('ลองใหม่'),
                ),
              ],
            ),
          );
        }
        final catalog = snapshot.data;
        if (catalog == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final words = catalog.search(query: _query, level: _level);
        final inventoryCount = _level == 'C2'
            ? catalog.search(level: 'C2').length
            : catalog.search().length;
        final theme = Theme.of(context);
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'เลือกคำที่อยากเรียน',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ชุดหลัก 5,000 คำ · A1–C1\nชุดเสริม C2 อีก 500 คำ · ใช้ออฟไลน์ได้',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const ValueKey('cefr-catalog-search'),
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาคำศัพท์หรือคำแปล',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _level ?? 'ALL',
                      items: [
                        for (final level in [
                          'ALL',
                          'A1',
                          'A2',
                          'B1',
                          'B2',
                          'C1',
                          'C2',
                        ])
                          DropdownMenuItem(
                            value: level,
                            child: Text(
                              level == 'ALL'
                                  ? 'ชุดหลัก A1–C1'
                                  : level == 'C2'
                                  ? 'ชุดเสริม C2'
                                  : 'ระดับ $level',
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => _level = value == 'ALL' ? null : value,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'พบ ${words.length} จาก $inventoryCount คำ',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ตรวจภาษาเบื้องต้น ${catalog.editorialCount} / ${catalog.words.length} คำในคลัง',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (catalog.editorialLoadFailed)
                      TextButton(
                        onPressed: () => setState(
                          () => _catalog = CefrVocabularyCatalog.load(),
                        ),
                        child: const Text('โหลดตัวอย่างไม่สำเร็จ · ลองใหม่'),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            if (words.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('ไม่พบคำศัพท์ที่ตรงกับการค้นหา')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.builder(
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    final word = words[index];
                    return Card.outlined(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: ValueKey('cefr-word-${word.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        title: Text(
                          '${word.word} · ${word.cefrLevel}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${word.partOfSpeechThai} · ${word.practiceUsageNotice ?? word.editorial?.meaning ?? word.meanings.first}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy
                            ? null
                            : () => _chooseMeaning(catalog, word),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
