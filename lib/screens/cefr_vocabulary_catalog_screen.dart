import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/vocabulary/application/cefr_catalog_import.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/cefr_vocabulary_catalog.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'cefr_vocabulary_detail_screen.dart';

class CefrVocabularyCatalogScreen extends StatefulWidget {
  const CefrVocabularyCatalogScreen({
    super.key,
    this.catalog,
    this.vocabulary,
    this.catalogLoader,
  });
  final Future<CefrVocabularyCatalog>? catalog;
  final Future<CefrVocabularyCatalog> Function()? catalogLoader;
  final VocabularyUseCases? vocabulary;
  @override
  State<CefrVocabularyCatalogScreen> createState() => _CatalogState();
}

class _CatalogState extends State<CefrVocabularyCatalogScreen>
    with WidgetsBindingObserver {
  Future<CefrVocabularyCatalog>? _catalog;
  final _search = TextEditingController();
  AppDependencies? _dependencies;
  int _generation = 0;
  int _readEpoch = 0;
  int _bindingEpoch = 0;
  bool _active = false;
  bool _opening = false;
  bool _pending = false;
  bool _exited = false;
  bool _foreground = true;
  int _importEpoch = 0;
  Route<VocabularyCategory>? _picker;
  bool get _importVisible =>
      mounted &&
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent != false ||
          _picker?.isCurrent == true);
  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _read();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final active = _visible;
    if (!identical(dependencies, _dependencies)) {
      _bindingEpoch++;
      _generation++;
    }
    if (active != _active) _generation++;
    if (_busy && (!identical(dependencies, _dependencies) || !_importVisible)) {
      _importEpoch++;
    }
    _dependencies = dependencies;
    _active = active;
  }

  @override
  void didUpdateWidget(CefrVocabularyCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog) ||
        !identical(oldWidget.catalogLoader, widget.catalogLoader) ||
        !identical(oldWidget.vocabulary, widget.vocabulary))
      _importEpoch++;
    if (!identical(oldWidget.catalog, widget.catalog) ||
        !identical(oldWidget.catalogLoader, widget.catalogLoader)) {
      _bindingEpoch++;
      _read();
    }
    if (!identical(oldWidget.vocabulary, widget.vocabulary)) {
      _bindingEpoch++;
      _generation++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _importEpoch++;
      _foreground = state == AppLifecycleState.resumed;
      _generation++;
      _bindingEpoch++;
      _active = _visible;
    });
  }

  void _read() {
    final epoch = ++_readEpoch;
    _generation++;
    _pending = true;
    _catalog = Future<CefrVocabularyCatalog>.sync(
      () =>
          widget.catalogLoader?.call() ??
          widget.catalog ??
          CefrVocabularyCatalog.load(),
    );
    // Observe immediately, including synchronous failures and retries before build.
    _catalog!.then<void>(
      (_) {
        if (mounted && epoch == _readEpoch) _pending = false;
      },
      onError: (Object _, StackTrace __) {
        if (mounted && epoch == _readEpoch) _pending = false;
      },
    );
  }

  bool _current(int generation) =>
      mounted &&
      !_exited &&
      generation == _generation &&
      _visible &&
      (_dependencies == null ||
          _dependencies!.features.isEnabled(Feature.reading));
  bool _allowed(int generation) => _current(generation) && !_opening && !_busy;

  void _retry(int generation) {
    if (!_allowed(generation) || _pending) return;
    setState(() {
      _read();
    });
  }

  void _change(int generation, VoidCallback change) {
    if (!_allowed(generation)) return;
    setState(change);
  }

  void _exit() {
    _importEpoch++;
    _exited = true;
    _generation++;
    _bindingEpoch++;
  }

  @override
  void dispose() {
    _exit();
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

  Future<void> _licenses(int generation) async {
    if (!_allowed(generation)) return;
    _opening = true;
    final lease = ++_generation;
    try {
      final texts = await Future.wait(
        [
          'assets/content/cefr_editorial/NOTICE.txt',
          'assets/content/cefr_expanded/NOTICE.txt',
          for (final name in ['NOTICE.txt', 'LICENSE.txt', 'LICENSE-th.txt'])
            'assets/content/cefr_starter/$name',
        ].map(rootBundle.loadString),
      );
      if (!_current(lease)) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _CatalogLicenses(texts: texts),
      );
    } catch (_) {
      if (_current(lease)) _message('ยังเปิดรายละเอียดแหล่งข้อมูลไม่ได้');
    } finally {
      _opening = false;
      if (mounted && !_exited) setState(() {});
    }
  }

  Future<void> _chooseMeaning(
    int generation,
    CefrVocabularyCatalog catalog,
    CefrCatalogWord word,
  ) async {
    if (!_allowed(generation)) return;
    _opening = true;
    _generation++;
    final binding = _bindingEpoch;
    final vocabulary = _vocabulary;
    final explicitVocabulary = widget.vocabulary;
    final production = _dependencies != null;
    try {
      final index = await AppNavigator.pushPage<int>(
        context,
        AppPage<int>(
          name: 'home/learn/reading/cefr/vocabulary/detail',
          builder: (_) {
            final child = CefrVocabularyDetailScreen(
              word: word,
              canAdd: explicitVocabulary != null,
              resolveVocabulary: explicitVocabulary == null && production,
            );
            return production
                ? ProductionFeatureGate(
                    feature: Feature.reading,
                    builder: (_) => child,
                  )
                : child;
          },
        ),
      );
      // The popped child completes before the parent TickerMode is restored.
      // Revalidate on the frame that makes the original catalog interactive.
      if (index != null) await WidgetsBinding.instance.endOfFrame;
      if (index != null &&
          mounted &&
          !_exited &&
          _visible &&
          binding == _bindingEpoch &&
          identical(vocabulary, _vocabulary)) {
        await _add(catalog, word, index);
      }
    } finally {
      _opening = false;
      if (mounted && !_exited) setState(() {});
    }
  }

  Future<void> _add(
    CefrVocabularyCatalog catalog,
    CefrCatalogWord word,
    int index,
  ) async {
    final vocabulary = _vocabulary;
    if (_busy || vocabulary == null || !_importVisible) return;
    final epoch = ++_importEpoch;
    bool allowed() =>
        mounted &&
        epoch == _importEpoch &&
        _importVisible &&
        identical(vocabulary, _vocabulary) &&
        (_dependencies == null ||
            (_dependencies!.features.isEnabled(Feature.reading) &&
                _dependencies!.features.isEnabled(Feature.vocabulary)));
    String? ownerId;
    bool submitted = false;
    Future<bool> currentOwner() async {
      if (!allowed()) return false;
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      return allowed() && (ownerId == null || owner.id == ownerId);
    }

    Future<void> messageIfCurrent(String text) async {
      try {
        if (await currentOwner()) _message(text);
      } catch (_) {
        if (allowed()) _message('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่');
      }
    }

    setState(() => _busy = true);
    try {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      ownerId = owner.id;
      if (!allowed()) return;
      final categories = (await vocabulary.watchCategories().first)
          .where(
            (category) =>
                category.ownerId == owner.id &&
                !category.isReadOnly &&
                !category.isDeleted,
          )
          .toList();
      if (!await currentOwner()) return;
      if (categories.isEmpty) {
        _message('สร้างหมวดหมู่ในแท็บคลังคำศัพท์ก่อน แล้วกลับมาเลือกคำได้เลย');
        return;
      }
      final route = DialogRoute<VocabularyCategory>(
        context: context,
        builder: (_) => _ImportCategoryPicker(
          categories: categories,
          allowed: allowed,
          currentOwner: currentOwner,
          retire: () {
            if (epoch == _importEpoch) _importEpoch++;
          },
        ),
      );
      _picker = route;
      final category = await Navigator.of(context).push(route);
      _picker = null;
      await WidgetsBinding.instance.endOfFrame;
      if (category == null || !await currentOwner()) return;
      submitted = true;
      await CefrCatalogImport(vocabulary: vocabulary, catalog: catalog).add(
        wordId: word.id,
        meaningIndex: index < 0 ? 0 : index,
        useEditorial: index < 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
        mutationAllowed: allowed,
      );
      if (await currentOwner()) {
        _message('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้');
      }
    } on CategoryWordLimitFailure catch (_) {
      await messageIfCurrent('หมวดหมู่นี้ครบ 50 คำแล้ว กรุณาเลือกหมวดหมู่อื่น');
    } on VocabularyNotFoundFailure catch (_) {
      await messageIfCurrent('หมวดหมู่เปลี่ยนไปแล้ว กรุณาเลือกใหม่');
    } catch (_) {
      await messageIfCurrent(
        submitted
            ? 'ยังยืนยันผลการเพิ่มคำไม่ได้ กรุณาตรวจคลังหรือลองใหม่'
            : 'ยังเพิ่มคำไม่ได้ กรุณาลองใหม่ ข้อมูลเดิมยังคงอยู่',
      );
    } finally {
      _picker = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('คำศัพท์ CEFR'),
          actions: [
            IconButton(
              tooltip: 'แหล่งข้อมูลและสิทธิ์ใช้งาน',
              onPressed: () => _licenses(generation),
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
                      onPressed: () => _retry(generation),
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
                          controller: _search,
                          decoration: const InputDecoration(
                            labelText: 'ค้นหาคำศัพท์หรือคำแปล',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) => _change(generation, () {
                            _query = value;
                          }),
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
                          onChanged: (value) {
                            if (![
                              'ALL',
                              'A1',
                              'A2',
                              'B1',
                              'B2',
                              'C1',
                              'C2',
                            ].contains(value))
                              return;
                            _change(generation, () {
                              _level = value == 'ALL' ? null : value;
                            });
                          },
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
                            onPressed: () => _retry(generation),
                            child: const Text(
                              'โหลดตัวอย่างไม่สำเร็จ · ลองใหม่',
                            ),
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
                      child: Center(
                        child: Text('ไม่พบคำศัพท์ที่ตรงกับการค้นหา'),
                      ),
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
                                : () =>
                                      _chooseMeaning(generation, catalog, word),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogLicenses extends StatefulWidget {
  const _CatalogLicenses({required this.texts});
  final List<String> texts;
  @override
  State<_CatalogLicenses> createState() => _CatalogLicensesState();
}

class _CatalogLicensesState extends State<_CatalogLicenses>
    with WidgetsBindingObserver {
  bool _closed = false;
  bool _foreground = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _closed) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _generation++;
    });
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    final visible =
        ModalRoute.of(context)?.isCurrent == true &&
        TickerMode.valuesOf(context).enabled;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closed = true;
      },
      child: AlertDialog(
        title: const Text('แหล่งข้อมูลและสิทธิ์ใช้งาน'),
        scrollable: true,
        content: SelectableText(widget.texts.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted ||
                  _closed ||
                  !_foreground ||
                  !visible ||
                  generation != _generation ||
                  ModalRoute.of(context)?.isCurrent != true)
                return;
              _closed = true;
              Navigator.pop(context);
            },
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

class _ImportCategoryPicker extends StatefulWidget {
  const _ImportCategoryPicker({
    required this.categories,
    required this.allowed,
    required this.currentOwner,
    required this.retire,
  });
  final List<VocabularyCategory> categories;
  final bool Function() allowed;
  final Future<bool> Function() currentOwner;
  final VoidCallback retire;
  @override
  State<_ImportCategoryPicker> createState() => _ImportCategoryPickerState();
}

class _ImportCategoryPickerState extends State<_ImportCategoryPicker>
    with WidgetsBindingObserver {
  bool _closed = false;
  bool _pending = false;
  bool _foreground = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) widget.retire();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    widget.retire();
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _generation++;
    });
  }

  bool current(int generation) =>
      mounted &&
      !_closed &&
      _foreground &&
      generation == _generation &&
      ModalRoute.of(context)?.isCurrent == true &&
      TickerMode.valuesOf(context).enabled;
  Future<void> choose(int generation, VocabularyCategory category) async {
    if (!current(generation) || _pending || !widget.allowed()) return;
    _pending = true;
    try {
      if (!await widget.currentOwner() || !current(generation)) return;
      _closed = true;
      Navigator.pop(context, category);
    } catch (_) {
      if (current(generation)) {
        setState(
          () => _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองเลือกอีกครั้ง',
        );
      }
    } finally {
      _pending = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    return PopScope<VocabularyCategory>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closed = true;
      },
      child: SimpleDialog(
        title: const Text('เพิ่มลงหมวดหมู่'),
        children: [
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          for (final category in widget.categories)
            SimpleDialogOption(
              onPressed: () => choose(generation, category),
              child: Text(category.name),
            ),
          TextButton(
            onPressed: () {
              if (!current(generation)) return;
              _closed = true;
              Navigator.pop(context);
            },
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }
}
