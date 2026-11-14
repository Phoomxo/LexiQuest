import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/registries/feature_registry.dart';
import '../services/ai_reading_content_adapter.dart';
import '../widgets/handwriting_scratchpad.dart';

import 'associative_reading_session_screen.dart';
import 'categories_page.dart';
import 'mastery_dashboard_screen.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';
import '../navigation/app_routes.dart';
import 'srs_flashcards_screen.dart';
import 'weakness_clinic_screen.dart';

class ChooseModeScreen extends StatefulWidget {
  const ChooseModeScreen({
    super.key,
    this.loader,
    this.learning,
    this.featureRegistry,
    this.onOpenMenu,
    this.onOpenLibrary,
    this.isActive = true,
  });

  final ProgressLoader? loader;
  final LearningUseCases? learning;
  final FieldFeatureRegistry? featureRegistry;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onOpenLibrary;
  final bool isActive;

  @override
  State<ChooseModeScreen> createState() => _ChooseModeScreenState();
}

class _ChooseModeScreenState extends State<ChooseModeScreen> {
  Future<ProgressSnapshot>? _load;
  ProgressLoader? _loader;
  bool _selectingCategory = false;

  ProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  LearningUseCases? get _learning {
    final scope = AppDependenciesScope.maybeOf(context);
    return scope == null ? widget.learning : scope.learning;
  }

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  bool get _wordPracticeVisible {
    final features = AppDependenciesScope.maybeOf(context)?.features;
    return _features.isVisible(FieldFeature.quiz) &&
        _features.isVisible(FieldFeature.vocabulary) &&
        (features?.isVisible(Feature.quiz) ?? true) &&
        (features?.isVisible(Feature.vocabulary) ?? true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load == null || _currentLoader != _loader) {
      _load = _loadProgress();
    }
  }

  @override
  void didUpdateWidget(covariant ChooseModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        (widget.isActive && !oldWidget.isActive)) {
      _load = _loadProgress();
    }
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _loader = _currentLoader;
    final next = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : Future<ProgressSnapshot>.sync(loader);
    next.ignore();
    return next;
  }

  void _refresh() {
    if (mounted) {
      final next = _loadProgress();
      setState(() {
        _load = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReview = _features.isVisible(FieldFeature.srs);
    final canReading = _features.isVisible(FieldFeature.reading);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 16.0
        : width < 600
        ? 24.0
        : ((width - 720) / 2).clamp(24.0, double.infinity).toDouble();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.rootAppBarToolbarHeight(context),
        title: Text(
          'ฝึกภาษา',
          maxLines: 2,
          softWrap: true,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        titleSpacing: horizontalPadding,
        actions: widget.onOpenMenu == null
            ? null
            : [
                IconButton(
                  key: const ValueKey<String>('shell-drawer-button'),
                  tooltip: 'เปิดเมนูเพิ่มเติม',
                  onPressed: widget.onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
              ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          24,
          horizontalPadding,
          24,
        ),
        children: [
          FutureBuilder<ProgressSnapshot>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'กำลังโหลดคำแนะนำการฝึก',
                  ),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text('โหลดคำแนะนำการฝึกไม่สำเร็จ'),
                    ),
                    TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองอีกครั้ง'),
                    ),
                  ],
                );
              }
              final progress = snapshot.requireData;
              final hasDue = canReview && progress.dueReviewCount > 0;
              final canLibrary = _features.isVisible(FieldFeature.vocabulary);
              final nextWord = progress.nextDueSpelling;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    hasDue
                        ? 'ถึงเวลาทบทวน ${progress.dueReviewCount} คำ'
                        : progress.vocabularyWordCount == 0
                        ? 'เพิ่มคำศัพท์เพื่อเริ่มฝึก'
                        : canReview
                        ? 'ทบทวนครบแล้ว'
                        : 'เลือกกิจกรรมฝึกภาษา',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (hasDue)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (progress.nextDueCategoryName
                              case final categoryName?) ...[
                            Text(
                              'จากชุด $categoryName',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (nextWord != null) ...[
                            Text(
                              'ลองนึกความหมายก่อนเปิดคำแปล',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              nextWord,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(165, 48),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              onPressed: () => _push(
                                context,
                                SrsFlashcardsScreen(learning: _learning),
                              ),
                              icon: const Icon(Icons.event_repeat_outlined),
                              label: Text(
                                nextWord == null
                                    ? 'ทบทวน ${progress.dueReviewCount} คำ'
                                    : 'ทบทวนคำนี้',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (canLibrary) ...[
                    Text(
                      progress.vocabularyWordCount == 0
                          ? 'เก็บคำที่อยากใช้ แล้วนำคำในชุดนั้นมาฝึก'
                          : 'ฝึกเพิ่มได้จากชุดคำศัพท์ของคุณ',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openLibrary,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('เลือกชุดคำศัพท์'),
                    ),
                  ] else if (canReading)
                    const Text('เลือกกิจกรรมอ่านด้านล่าง')
                  else
                    const Text('ยังไม่มีกิจกรรมที่เปิดใช้งานในหน้านี้'),
                ],
              );
            },
          ),
          const SizedBox(height: 48),
          Text(
            'ฝึกเพิ่มเติม',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          FutureBuilder<ProgressSnapshot>(
            future: _load,
            builder: (_, snapshot) => Column(
              children: _activities(
                progress:
                    snapshot.connectionState == ConnectionState.done &&
                        !snapshot.hasError
                    ? snapshot.data
                    : null,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _push(
              context,
              Scaffold(
                appBar: AppBar(
                  toolbarHeight: M3Theme.appBarToolbarHeight(context),
                  title: M3Theme.appBarTitle(context, 'เลือกวิธีฝึก'),
                ),
                body: ListView(
                  padding: EdgeInsets.all(horizontalPadding),
                  children: _activities(all: true),
                ),
              ),
            ),
            child: const Text('ดูแบบฝึกทั้งหมด'),
          ),
        ],
      ),
    );
  }

  List<Widget> _activities({bool all = false, ProgressSnapshot? progress}) {
    final canQuiz = _features.isVisible(FieldFeature.quiz);
    final canReview = _features.isVisible(FieldFeature.srs);
    final canWeakness = _features.isVisible(FieldFeature.weakness);
    final canReading = _features.isVisible(FieldFeature.reading);
    final canViewProgress = _features.isVisible(FieldFeature.mastery);
    return [
      if (!all &&
          canQuiz &&
          _features.isVisible(FieldFeature.vocabulary) &&
          (progress?.vocabularyWordCount ?? 0) > 0 &&
          (progress?.dueReviewCount ?? 0) > 0)
        _LearningTile(
          icon: Icons.menu_book_outlined,
          title: 'ฝึกจากชุดคำ',
          subtitle: 'เลือกชุดคำศัพท์ของคุณแล้วเริ่มฝึก',
          onTap: _openLibrary,
        ),
      if (all && canQuiz) ...[
        _LearningTile(
          icon: Icons.quiz_outlined,
          title: 'ฝึกคำศัพท์',
          subtitle: 'ฝึกคำแปล แล้วดูคำที่ควรทบทวน',
          onTap: () => _push(
            context,
            QuizScreen(learning: _learning, featureRegistry: _features),
          ),
        ),
        _LearningTile(
          icon: Icons.category_outlined,
          title: 'ฝึกตามหมวดหมู่',
          subtitle: 'เลือกจากหมวดหมู่ที่บันทึกในเครื่อง',
          onTap: () => _openCategoryQuiz(context),
        ),
      ],
      if (all && _wordPracticeVisible) ...[
        _LearningTile(
          icon: Icons.translate_outlined,
          title: 'เลือกคำอังกฤษจากความหมายไทย',
          subtitle: 'อ่านความหมาย แล้วเลือกคำจากชุดของคุณ',
          onTap: () =>
              _openCategoryQuiz(context, kind: QuizPromptKind.spellingChoice),
        ),
        _LearningTile(
          icon: Icons.description_outlined,
          title: 'อ่านนิยามแล้วหาคำ',
          subtitle: 'โจทย์นิยามภาษาอังกฤษสำหรับคำที่มีข้อมูลรองรับ',
          onTap: () =>
              _openCategoryQuiz(context, kind: QuizPromptKind.definitionChoice),
        ),
        _LearningTile(
          icon: Icons.draw_outlined,
          title: 'กระดานฝึกเขียน',
          subtitle: 'เลือกคำจากชุดของคุณ เขียนแล้วเทียบกับคำเฉลย',
          onTap: _openHandwriting,
        ),
      ],
      if (all && canReview)
        _LearningTile(
          icon: Icons.event_repeat_outlined,
          title: 'ทบทวนคำศัพท์ที่ถึงกำหนด',
          subtitle: 'ทบทวนคำที่ถึงเวลาแล้วตามประวัติการเรียน',
          onTap: () => _push(context, SrsFlashcardsScreen(learning: _learning)),
        ),
      if (canReading)
        _LearningTile(
          icon: Icons.menu_book_outlined,
          title: 'อ่านเรื่องสั้นและจำคำศัพท์',
          subtitle: 'อ่าน ทบทวนจากความจำ และแต่งประโยคด้วยคำเป้าหมาย',
          onTap: () => _openReading(context),
        ),
      if (all && canViewProgress)
        _LearningTile(
          icon: Icons.analytics_outlined,
          title: 'ภาพรวมการเรียน',
          subtitle: 'ดูความก้าวหน้าจากคำตอบที่บันทึกไว้',
          onTap: () => _push(
            context,
            MasteryDashboardScreen(
              loader: widget.loader,
              featureRegistry: _features,
            ),
          ),
        ),
      if (canWeakness && (all || progress?.weaknesses.isNotEmpty == true))
        _LearningTile(
          icon: Icons.healing_outlined,
          title: 'ฝึกคำที่ตอบผิด',
          subtitle: 'ฝึกคำที่เคยตอบผิดได้โดยไม่ต้องรอวันทบทวน',
          onTap: () => _push(
            context,
            WeaknessClinicScreen(
              loader: widget.loader,
              learning: _learning,
              featureRegistry: _features,
            ),
          ),
        ),
    ];
  }

  void _openLibrary() {
    if (widget.onOpenLibrary case final open?) {
      open();
    } else {
      _push(context, const CategoriesPage());
    }
  }

  Future<void> _openCategoryQuiz(
    BuildContext context, {
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
  }) async {
    if (_selectingCategory) return;
    _selectingCategory = true;
    final scope = AppDependenciesScope.maybeOf(context);
    final learning = _learning;
    final vocabulary = scope?.vocabulary;
    try {
      if (learning == null ||
          (kind != QuizPromptKind.meaningChoice &&
              (vocabulary == null || !_wordPracticeVisible))) {
        throw StateError('word practice unavailable');
      }
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (!context.mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !identical(learning, _learning)) {
        return;
      }
      final categoryId = await AppNavigator.pushPage<String>(
        context,
        AppPage<String>(
          name: 'learning/category-selector',
          builder: (_) => kind != QuizPromptKind.meaningChoice && scope != null
              ? _HandwritingOwner(
                  scope: scope,
                  ownerId: owner.id,
                  child: SelectCategoryForQuiz(vocabulary: vocabulary),
                )
              : SelectCategoryForQuiz(vocabulary: vocabulary),
        ),
      );
      if (categoryId == null ||
          !context.mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !identical(learning, _learning)) {
        return;
      }
      final currentOwner = await learning.owners.getOrCreateActiveOwner();
      if (!context.mounted ||
          currentOwner.id != owner.id ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !identical(learning, _learning) ||
          (kind != QuizPromptKind.meaningChoice && !_wordPracticeVisible)) {
        return;
      }
      await _push(
        context,
        QuizScreen(
          categoryId: categoryId,
          learning: _learning,
          featureRegistry: _features,
          promptKind: kind,
          expectedOwnerId: owner.id,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังเปิดแบบฝึกจากชุดคำนี้ไม่ได้ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      _selectingCategory = false;
    }
  }

  Future<void> _openHandwriting() async {
    final scope = AppDependenciesScope.maybeOf(context);
    final vocabulary = scope?.vocabulary;
    if (scope == null || vocabulary == null || !_wordPracticeVisible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังเปิดกระดานฝึกเขียนไม่ได้')),
      );
      return;
    }
    try {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      if (!mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !_wordPracticeVisible) {
        return;
      }
      final categoryId = await AppNavigator.pushPage<String>(
        context,
        AppPage(
          name: 'learning/category-selector',
          builder: (_) => _HandwritingOwner(
            scope: scope,
            ownerId: owner.id,
            child: SelectCategoryForQuiz(vocabulary: vocabulary),
          ),
        ),
      );
      if (categoryId == null ||
          !mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !_wordPracticeVisible) {
        return;
      }
      final current = await vocabulary.owners.getOrCreateActiveOwner();
      if (!mounted ||
          current.id != owner.id ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !_wordPracticeVisible) {
        return;
      }
      await _push(
        context,
        _HandwritingOwner(
          scope: scope,
          ownerId: owner.id,
          child: _HandwritingWords(
            categoryId: categoryId,
            ownerId: owner.id,
            scope: scope,
          ),
        ),
      );
    } on Object {
      if (mounted && identical(scope, AppDependenciesScope.maybeOf(context))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยังเปิดกระดานฝึกเขียนไม่ได้')),
        );
      }
    }
  }

  Future<void> _openReading(BuildContext context) async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final learning = _learning;
    if (learning == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังเปิดกิจกรรมอ่านไม่ได้ในขณะนี้')),
      );
      return;
    }
    final words = await learning.prepareReading();
    if (!context.mounted) return;
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เพิ่มคำศัพท์อย่างน้อย 1 คำก่อนเริ่มอ่าน'),
        ),
      );
      return;
    }
    final targetWords = words
        .map((word) => word.spelling)
        .toList(growable: false);
    final passage = await AiReadingContentAdapter().generatePassage(
      cefrLevel: 'B1',
      targetWords: targetWords,
      forceOffline: true,
    );
    if (!context.mounted) return;
    final owner = await learning.owners.getOrCreateActiveOwner();
    if (!context.mounted) return;
    await _push(
      context,
      AssociativeReadingSessionScreen(
        cefrLevel: passage.cefrLevel,
        targetWords: passage.targetWords,
        passageText: passage.passageText,
        documentId:
            '${passage.contentId}:${DateTime.now().microsecondsSinceEpoch}',
        learning: learning,
        associativeLearning: dependencies?.associativeLearning,
        targetWordIds: {for (final word in words) word.spelling: word.id},
        ownerId: owner.id,
      ),
    );
  }

  Future<void> _push(BuildContext context, Widget screen) async {
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: 'learning/activity', builder: (_) => screen),
    );
    _refresh();
  }
}

class _HandwritingOwner extends StatefulWidget {
  const _HandwritingOwner({
    required this.scope,
    required this.ownerId,
    required this.child,
  });
  final AppDependencies scope;
  final String ownerId;
  final Widget child;

  @override
  State<_HandwritingOwner> createState() => _HandwritingOwnerState();
}

class _HandwritingOwnerState extends State<_HandwritingOwner> {
  int _request = 0;
  bool _checking = true;
  bool _admitted = false;

  @override
  void initState() {
    super.initState();
    widget.scope.progressUpdates?.addListener(_recheck);
    _recheck();
  }

  Future<void> _recheck() async {
    final request = ++_request;
    final expectedOwner = widget.ownerId;
    if (!_checking) {
      setState(() => _checking = true);
    }
    bool admitted;
    try {
      final owner = await widget.scope.vocabulary!.owners
          .getOrCreateActiveOwner();
      admitted = owner.id == expectedOwner;
    } on Object {
      admitted = false;
    }
    if (mounted && request == _request) {
      setState(() {
        _checking = false;
        _admitted = admitted;
      });
    }
  }

  @override
  void dispose() {
    widget.scope.progressUpdates?.removeListener(_recheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppDependenciesScope.maybeOf(context);
    if (!identical(scope, widget.scope) || (!_checking && !_admitted)) {
      return Scaffold(
        appBar: AppBar(),
        body: const SafeArea(child: Center(child: Text('เปลี่ยนผู้ใช้แล้ว'))),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_admitted)
          Offstage(
            offstage: _checking,
            child: ExcludeFocus(excluding: _checking, child: widget.child),
          ),
        if (_checking)
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}

class _HandwritingWords extends StatefulWidget {
  const _HandwritingWords({
    required this.categoryId,
    required this.ownerId,
    required this.scope,
  });
  final String categoryId, ownerId;
  final AppDependencies scope;
  @override
  State<_HandwritingWords> createState() => _HandwritingWordsState();
}

class _HandwritingWordsState extends State<_HandwritingWords> {
  late final _words = widget.scope.vocabulary!.watchWords(widget.categoryId);
  late final _categories = widget.scope.vocabulary!.watchCategories();
  String? _wordId;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _categories,
    builder: (context, categorySnapshot) {
      final category = categorySnapshot.data
          ?.where(
            (c) => c.id == widget.categoryId && c.ownerId == widget.ownerId,
          )
          .firstOrNull;
      if (category == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('กระดานฝึกเขียน')),
          body: Center(
            child: categorySnapshot.connectionState == ConnectionState.waiting
                ? const CircularProgressIndicator()
                : const Text('ชุดคำนี้ไม่พร้อมใช้งาน'),
          ),
        );
      }
      return StreamBuilder<List<VocabularyWord>>(
        stream: _words,
        builder: (context, wordsSnapshot) {
          final words = (wordsSnapshot.data ?? const <VocabularyWord>[]).where(
            (word) =>
                word.ownerId == widget.ownerId &&
                word.categoryId == category.id &&
                !word.isDeleted,
          );
          final selected = words
              .where((word) => word.id == _wordId)
              .firstOrNull;
          return PopScope<void>(
            canPop: selected == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && selected != null) {
                setState(() => _wordId = null);
              }
            },
            child: Scaffold(
              appBar: AppBar(title: Text(category.name)),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (selected != null)
                      HandwritingScratchpad(
                        key: ValueKey((
                          selected.ownerId,
                          selected.id,
                          selected.localRevision,
                          selected.spelling,
                          selected.meaning,
                          selected.partOfSpeech,
                        )),
                        spelling: selected.spelling,
                        meaning: selected.meaning,
                        onDone: () => setState(() => _wordId = null),
                      )
                    else if (wordsSnapshot.hasError)
                      const Text('โหลดคำศัพท์ไม่สำเร็จ')
                    else if (wordsSnapshot.connectionState ==
                        ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (words.isEmpty)
                      const Text('ยังไม่มีคำในชุดนี้')
                    else ...[
                      Text(
                        'เลือกคำที่ต้องการฝึกเขียน',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final word in words)
                        ListTile(
                          title: Text(word.spelling),
                          subtitle: Text(word.meaning),
                          onTap: () => setState(() => _wordId = word.id),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _LearningTile extends StatelessWidget {
  const _LearningTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          minVerticalPadding: 16,
          leading: Icon(icon),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 15),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
