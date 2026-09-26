import 'dart:async';
import 'package:flutter/material.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';

import '../navigation/app_routes.dart';
import '../services/local_reading_catalog.dart';
import 'cefr_article_reader_screen.dart';
import 'cefr_vocabulary_catalog_screen.dart';

/// Local reading practice does not invent a vocabulary session or CEFR result.
/// Each production child resolves its own live reading authority.
class LocalReadingLibraryScreen extends StatefulWidget {
  const LocalReadingLibraryScreen({
    super.key,
    required this.onVocabularyPractice,
  });
  final FutureOr<void> Function() onVocabularyPractice;

  @override
  State<LocalReadingLibraryScreen> createState() => _LocalReadingLibraryState();
}

class _LocalReadingLibraryState extends State<LocalReadingLibraryScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  int _generation = 0;
  bool _active = false;
  bool _opening = false;
  bool _exited = false;
  bool _foreground = true;
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final active = _visible;
    if (!identical(dependencies, _dependencies) || active != _active)
      _generation++;
    _dependencies = dependencies;
    _active = active;
  }

  @override
  void didUpdateWidget(LocalReadingLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onVocabularyPractice, widget.onVocabularyPractice))
      _generation++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _generation++;
      _active = _visible;
    });
  }

  Future<void> _open(int generation, FutureOr<void> Function() action) async {
    if (!mounted ||
        _exited ||
        _opening ||
        generation != _generation ||
        !_visible)
      return;
    if (_dependencies != null &&
        _dependencies!.features.isEnabled(Feature.reading) != true)
      return;
    _opening = true;
    _generation++;
    try {
      await action();
    } finally {
      _opening = false;
      if (mounted && !_exited) setState(() {});
    }
  }

  Future<void> _push(String name, WidgetBuilder builder) async {
    final production = _dependencies != null;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: name,
        builder: (childContext) => production
            ? ProductionFeatureGate(feature: Feature.reading, builder: builder)
            : builder(childContext),
      ),
    );
  }

  void _exit() {
    _exited = true;
    _generation++;
  }

  @override
  void dispose() {
    _exit();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ชุดบทอ่านเริ่มต้น')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'เลือกบทอ่านของคุณ',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              LocalReadingCatalog.notice,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 28),
            Text(
              'บทอ่านตามระดับ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (final level in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
              Card.outlined(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  title: Text(
                    '$level · ${LocalReadingCatalog.forLevel(level).title}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(generation, () async {
                    final selected = LocalReadingCatalog.forLevel(level);
                    await _push(
                      'home/learn/reading/article',
                      (_) => CefrArticleReaderScreen(
                        title: selected.title,
                        content: '${selected.text}\n\n${selected.reflection}',
                        cefrLevel: selected.level,
                        contentNotice:
                            '${LocalReadingCatalog.notice}\nอ่านฝึกได้โดยไม่เปลี่ยนระดับหรือความก้าวหน้าคำศัพท์',
                      ),
                    );
                  }),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'คำศัพท์และการฝึก',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(20),
              ),
              key: const ValueKey('reading-library-vocabulary-catalog'),
              onPressed: () => _open(
                generation,
                () => _push(
                  'home/learn/reading/cefr/vocabulary',
                  (_) => const CefrVocabularyCatalogScreen(),
                ),
              ),
              child: const Text('คลังคำศัพท์ 5,000 คำ + ชุดเสริม C2'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(20),
              ),
              onPressed: () => _open(generation, widget.onVocabularyPractice),
              child: const Text('ฝึกจากคำศัพท์ที่มีระดับ'),
            ),
          ],
        ),
      ),
    );
  }
}
