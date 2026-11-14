import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'phonetic_explorer_screen.dart';
import 'select_category_for_quiz.dart';
import 'vocab_list_screen.dart';

enum _SetActivity { playlist, dictation }

class ListeningPracticeMenuScreen extends StatefulWidget {
  const ListeningPracticeMenuScreen({super.key, required this.fieldFeatures});

  final FieldFeatureRegistry fieldFeatures;

  static bool isAvailable(BuildContext context, FieldFeatureRegistry field) =>
      field.isVisible(FieldFeature.speechPractice) &&
      (AppDependenciesScope.maybeOf(
            context,
          )?.features.isVisible(Feature.speechPractice) ??
          true);

  @override
  State<ListeningPracticeMenuScreen> createState() =>
      _ListeningPracticeMenuScreenState();
}

bool _hasVocabulary(AppDependencies? scope, FieldFeatureRegistry field) =>
    scope != null &&
    scope.vocabulary != null &&
    field.isVisible(FieldFeature.vocabulary) &&
    scope.features.isVisible(Feature.vocabulary);

class _ListeningPracticeMenuScreenState
    extends State<ListeningPracticeMenuScreen> {
  bool _selectingSet = false;

  Future<void> _chooseSet(_SetActivity activity) async {
    final scope = AppDependenciesScope.maybeOf(context);
    final hubRoute = ModalRoute.of(context);
    if (_selectingSet ||
        hubRoute?.isCurrent != true ||
        scope == null ||
        !_hasVocabulary(scope, widget.fieldFeatures) ||
        !ListeningPracticeMenuScreen.isAvailable(
          context,
          widget.fieldFeatures,
        )) {
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _selectingSet = true);
    try {
      final ownerId = scope.database == null
          ? (await scope.vocabulary!.owners.getOrCreateActiveOwner()).id
          : await scope.readActiveOwnerId();
      if (!mounted ||
          !identical(scope, AppDependenciesScope.maybeOf(context)) ||
          hubRoute?.isCurrent != true ||
          !_hasVocabulary(scope, widget.fieldFeatures) ||
          !ListeningPracticeMenuScreen.isAvailable(
            context,
            widget.fieldFeatures,
          )) {
        return;
      }
      if (ownerId == null) {
        _showSetError(context);
        return;
      }
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/listening/${activity.name}/set',
          builder: (_) => _ListeningSetPicker(
            scope: scope,
            fieldFeatures: widget.fieldFeatures,
            ownerId: ownerId,
            activity: activity,
            onReturnFromDictation: () => navigator.popUntil(
              (route) => identical(route, hubRoute) || route.isFirst,
            ),
          ),
        ),
      );
    } on Object {
      if (mounted && hubRoute?.isCurrent == true) _showSetError(context);
    } finally {
      if (mounted) setState(() => _selectingSet = false);
    }
  }

  void _openIpa() {
    if (_selectingSet ||
        ModalRoute.isCurrentOf(context) != true ||
        !ListeningPracticeMenuScreen.isAvailable(
          context,
          widget.fieldFeatures,
        )) {
      return;
    }
    final voice = AppDependenciesScope.maybeOf(context)?.voice;
    unawaited(
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/listening/phonetic',
          builder: (_) => PhoneticExplorerScreen(
            voice: voice,
            returnLabel: 'กลับไปเลือกแบบฝึกฟัง',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = ListeningPracticeMenuScreen.isAvailable(
      context,
      widget.fieldFeatures,
    );
    final canChooseSet = _hasVocabulary(
      AppDependenciesScope.maybeOf(context),
      widget.fieldFeatures,
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ฟังและพูด'),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (available) ...[
                if (canChooseSet) ...[
                  ListTile(
                    leading: const Icon(Icons.queue_music_outlined),
                    title: const Text('ฟังชุดคำ'),
                    subtitle: const Text('ฟังคำศัพท์ในชุดเดียวกันต่อเนื่อง'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selectingSet
                        ? null
                        : () => _chooseSet(_SetActivity.playlist),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('เขียนตามเสียง'),
                    subtitle: const Text('เลือกคำจากคลัง ฟังแล้วลองสะกด'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selectingSet
                        ? null
                        : () => _chooseSet(_SetActivity.dictation),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('ฝึกเสียงทีละคำ'),
                  subtitle: const Text('ดูคำอ่านและฟังเสียงตัวอย่าง'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _selectingSet ? null : _openIpa,
                ),
              ] else
                const Text('แบบฝึกฟังยังไม่พร้อมใช้งาน'),
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

void _showSetError(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('เปิดชุดคำไม่ได้ กรุณาลองใหม่')));
}

class _ListeningSetPicker extends StatefulWidget {
  const _ListeningSetPicker({
    required this.scope,
    required this.fieldFeatures,
    required this.ownerId,
    required this.activity,
    required this.onReturnFromDictation,
  });

  final AppDependencies scope;
  final FieldFeatureRegistry fieldFeatures;
  final String ownerId;
  final _SetActivity activity;
  final VoidCallback onReturnFromDictation;

  @override
  State<_ListeningSetPicker> createState() => _ListeningSetPickerState();
}

class _ListeningSetPickerState extends State<_ListeningSetPicker> {
  StreamSubscription<void>? _ownerChanges;
  bool _invalidated = false;

  bool get _available =>
      !_invalidated &&
      identical(widget.scope, AppDependenciesScope.maybeOf(context)) &&
      _hasVocabulary(widget.scope, widget.fieldFeatures) &&
      ListeningPracticeMenuScreen.isAvailable(context, widget.fieldFeatures);

  @override
  void initState() {
    super.initState();
    _ownerChanges = widget.scope.watchLocalOwnerWrites()?.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!identical(widget.scope, AppDependenciesScope.maybeOf(context))) {
      _invalidated = true;
    }
  }

  void _invalidate() {
    if (mounted && !_invalidated) setState(() => _invalidated = true);
  }

  Future<void> _openSet(BuildContext from, VocabularyCategory category) async {
    if (!_available || category.ownerId != widget.ownerId) return;
    final vocabulary = widget.scope.vocabulary!;
    try {
      final ownerId = _ownerChanges == null
          ? (await vocabulary.owners.getOrCreateActiveOwner()).id
          : await widget.scope.readActiveOwnerId();
      if (!mounted ||
          !from.mounted ||
          !_available ||
          ModalRoute.isCurrentOf(from) != true) {
        return;
      }
      if (ownerId != widget.ownerId) {
        _invalidate();
        return;
      }
      final dictation = widget.activity == _SetActivity.dictation;
      await AppNavigator.pushPage<void>(
        from,
        AppPage<void>(
          name: 'learning/listening/${widget.activity.name}/words',
          builder: (_) => VocabListScreen(
            categoryId: category.id,
            categoryName: category.name,
            expectedOwnerId: ownerId,
            vocabulary: vocabulary,
            selectForDictation: dictation,
            onReturnFromDictation: dictation
                ? widget.onReturnFromDictation
                : null,
          ),
        ),
      );
    } on Object {
      if (from.mounted && ModalRoute.isCurrentOf(from) == true) {
        _showSetError(from);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_ownerChanges?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_available) {
      return SelectCategoryForQuiz(
        vocabulary: widget.scope.vocabulary,
        expectedOwnerId: widget.ownerId,
        onSelect: _openSet,
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'เลือกหมวดหมู่'),
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('ชุดคำไม่พร้อมใช้งาน กรุณากลับไปเลือกแบบฝึกฟัง'),
        ),
      ),
    );
  }
}
