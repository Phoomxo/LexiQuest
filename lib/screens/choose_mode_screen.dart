import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../services/ai_reading_content_adapter.dart';

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

  LearningUseCases? get _learning =>
      widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= _loadProgress();
  }

  @override
  void didUpdateWidget(covariant ChooseModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _refresh();
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    return loader == null
        ? Future.error(StateError('progress dependency unavailable'))
        : Future<ProgressSnapshot>.sync(loader);
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
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
            ? 160
            : M3Theme.appBarToolbarHeight(context),
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
          16,
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
                  const SizedBox(height: 16),
                  if (hasDue)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (nextWord != null) ...[
                            Text(
                              'ลองนึกความหมายก่อนเปิดคำแปล',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              nextWord,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 16),
                          ],
                          FilledButton.icon(
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
          const SizedBox(height: 24),
          Text('ฝึกเพิ่มเติม', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._activities(),
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

  List<Widget> _activities({bool all = false}) {
    final canQuiz = _features.isVisible(FieldFeature.quiz);
    final canReview = _features.isVisible(FieldFeature.srs);
    final canWeakness = _features.isVisible(FieldFeature.weakness);
    final canReading = _features.isVisible(FieldFeature.reading);
    final canViewProgress = _features.isVisible(FieldFeature.mastery);
    return [
      if (all && canQuiz) ...[
        _LearningTile(
          icon: Icons.quiz_outlined,
          title: 'ฝึกคำศัพท์',
          subtitle: 'ฝึกคำแปล แล้วดูคำที่ควรทบทวน',
          onTap: () => _push(context, QuizScreen(learning: _learning)),
        ),
        _LearningTile(
          icon: Icons.category_outlined,
          title: 'ฝึกตามหมวดหมู่',
          subtitle: 'เลือกจากหมวดหมู่ที่บันทึกในเครื่อง',
          onTap: () => _openCategoryQuiz(context),
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
      if (canWeakness)
        _LearningTile(
          icon: Icons.healing_outlined,
          title: 'ฝึกจุดอ่อน',
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

  Future<void> _openCategoryQuiz(BuildContext context) async {
    final categoryId = await AppNavigator.pushPage<String>(
      context,
      AppPage<String>(
        name: 'learning/category-selector',
        builder: (_) => const SelectCategoryForQuiz(),
      ),
    );
    if (categoryId != null && context.mounted) {
      await _push(
        context,
        QuizScreen(categoryId: categoryId, learning: _learning),
      );
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
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
