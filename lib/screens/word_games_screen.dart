import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning/domain/learning_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';

class WordGamesScreen extends StatefulWidget {
  const WordGamesScreen({super.key, this.featureRegistry});

  final FieldFeatureRegistry? featureRegistry;

  @override
  State<WordGamesScreen> createState() => _WordGamesScreenState();
}

class _WordGamesScreenState extends State<WordGamesScreen> {
  bool _opening = false;

  bool _available(AppDependencies? scope) {
    if (scope == null) return false;
    final field = widget.featureRegistry ?? scope.fieldFeatures;
    return scope.vocabulary != null &&
        scope.learning?.supportsDurableQuiz == true &&
        field.isVisible(FieldFeature.quiz) &&
        field.isVisible(FieldFeature.vocabulary) &&
        scope.features.isVisible(Feature.quiz) &&
        scope.features.isVisible(Feature.vocabulary);
  }

  Future<void> _open(QuizPromptKind kind) async {
    final scope = AppDependenciesScope.maybeOf(context);
    if (_opening || scope == null || !_available(scope)) return;
    final vocabulary = scope.vocabulary!;
    final learning = scope.learning!;
    setState(() => _opening = true);
    try {
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (!mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          !_available(scope) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/word-games/category',
          builder: (_) => SelectCategoryForQuiz(
            vocabulary: vocabulary,
            expectedOwnerId: owner.id,
            onSelect: (selector, category) async {
              try {
                final current = await learning.owners.getOrCreateActiveOwner();
                if (!mounted ||
                    !selector.mounted ||
                    !identical(scope, AppDependenciesScope.maybeOf(selector)) ||
                    !_available(scope) ||
                    ModalRoute.of(selector)?.isCurrent != true ||
                    current.id != owner.id ||
                    category.ownerId != current.id) {
                  return;
                }
                await AppNavigator.pushPage<void>(
                  selector,
                  AppPage<void>(
                    name: 'learning/word-games/${kind.name}',
                    builder: (_) => QuizScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                      expectedOwnerId: owner.id,
                      promptKind: kind,
                      featureRegistry: widget.featureRegistry,
                      returnLabel: 'เลือกเกมอื่น',
                    ),
                  ),
                  replace: true,
                );
              } on Object {
                if (selector.mounted &&
                    ModalRoute.of(selector)?.isCurrent == true) {
                  ScaffoldMessenger.of(selector).showSnackBar(
                    const SnackBar(content: Text('เปิดเกมจากชุดนี้ไม่สำเร็จ')),
                  );
                }
              }
            },
          ),
        ),
      );
    } on Object {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('เปิดเกมฝึกคำไม่สำเร็จ')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available(AppDependenciesScope.maybeOf(context));
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'เกมฝึกคำ'),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!available)
                const Text('ยังเปิดเกมจากคลังคำศัพท์ไม่ได้')
              else ...[
                ListTile(
                  leading: const Icon(Icons.abc),
                  title: const Text('เรียงตัวอักษร'),
                  subtitle: const Text('ประกอบคำจากตัวอักษรที่สลับกัน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _opening
                      ? null
                      : () => _open(QuizPromptKind.wordScramble),
                ),
                ListTile(
                  leading: const Icon(Icons.reorder),
                  title: const Text('เรียงประโยค'),
                  subtitle: const Text('วางคำตามลำดับให้ตรงกับความหมาย'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _opening
                      ? null
                      : () => _open(QuizPromptKind.sentenceScramble),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('กลับไปเลือกแบบฝึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
