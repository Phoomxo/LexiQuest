import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../navigation/app_routes.dart';
import 'vocab_list_screen.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.vocabulary, this.featureRegistry});

  final VocabularyUseCases? vocabulary;

  final FeatureRegistry? featureRegistry;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  VocabularyUseCases? _vocabulary;
  Stream<List<VocabularyCategory>>? _categories;

  void _bindVocabulary() {
    final next =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    if (identical(next, _vocabulary)) return;
    _vocabulary = next;
    _categories = next?.watchCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindVocabulary();
  }

  @override
  void didUpdateWidget(CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindVocabulary();
  }

  void _retry() {
    if (!_admitted) return;
    setState(() {
      // A new subscription resolves the active owner again, even when the
      // injected use-case object has not changed.
      _categories = _vocabulary?.watchCategories();
    });
  }

  FeatureRegistry? get _features =>
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => ProductionFeatureGate(
    feature: Feature.vocabulary,
    registry: _features,
    builder: _buildContent,
  );

  Widget _buildContent(BuildContext context) {
    final useCases = _vocabulary;
    return Scaffold(
      appBar: AppBar(title: const Text('คลังคำศัพท์')),
      body: useCases == null
          ? const _LocalDataUnavailable()
          : StreamBuilder<List<VocabularyCategory>>(
              key: ObjectKey(_categories),
              stream: _categories,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _FailureState(onRetry: _retry);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final categories = snapshot.data!;
                if (categories.isEmpty) {
                  return const Center(
                    child: Text(
                      'ยังไม่มีหมวดหมู่\nเพิ่มหมวดหมู่เพื่อเริ่มเก็บคำศัพท์',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    void openCategory() {
                      if (!_admitted) return;
                      final features = _features;
                      AppNavigator.pushPage<void>(
                        context,
                        AppPage<void>(
                          name: 'vocabulary/category',
                          builder: (_) => VocabListScreen(
                            featureRegistry: features,
                            vocabulary: widget.vocabulary,
                            categoryId: category.id,
                            categoryName: category.name,
                          ),
                        ),
                      );
                    }

                    return Card(
                      child: MenuActionBinding(
                        key: ValueKey(category.id),
                        ownerId: category.isReadOnly ? null : category.ownerId,
                        id: 'vocabulary/category/$index',
                        label: category.isReadOnly
                            ? 'เปิดหมวดอ่านอย่างเดียว ${category.name}'
                            : 'เปิดหมวดส่วนตัว ${category.name}',
                        onInvoke: openCategory,
                        child: ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(category.name),
                          subtitle: const Text('แตะเพื่อดูคำศัพท์'),
                          trailing: category.isReadOnly
                              ? null
                              : IconButton(
                                  tooltip: 'ลบหมวดหมู่',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _confirmDelete(
                                    context,
                                    useCases,
                                    category,
                                  ),
                                ),
                          onTap: openCategory,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: useCases == null
          ? null
          : MenuActionBinding(
              id: 'vocabulary/add-category',
              label: 'เพิ่มหมวดหมู่',
              onInvoke: () => _showAddCategory(context, useCases),
              child: FloatingActionButton.extended(
                key: const ValueKey('add-category'),
                heroTag: 'categories-add',
                onPressed: () => _showAddCategory(context, useCases),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มหมวดหมู่'),
              ),
            ),
    );
  }

  Future<void> _showAddCategory(
    BuildContext context,
    VocabularyUseCases useCases,
  ) async {
    if (!_admitted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _AddCategoryDialog(vocabulary: useCases, admitted: () => _admitted),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategory category,
  ) async {
    if (!_admitted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบหมวดหมู่'),
        content: Text('ลบ “${category.name}” และซ่อนคำศัพท์ในหมวดนี้หรือไม่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (accepted != true || !_admitted) return;
    try {
      await useCases.deleteCategory(category.id);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'ลบหมวดหมู่ไม่สำเร็จ');
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({required this.vocabulary, required this.admitted});
  final VocabularyUseCases vocabulary;
  final bool Function() admitted;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _formOwner;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bindLocalOwner();
  }

  Future<void> _bindLocalOwner() async {
    try {
      final owner = await widget.vocabulary.owners.getOrCreateActiveOwner();
      if (mounted) setState(() => _formOwner = owner.id);
    } catch (_) {
      // Optional tool admission must not block ordinary form interaction.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Map<String, Object?>> _save({String? expectedOwnerId}) async {
    if (!mounted || !widget.admitted() || _saving) return {'status': 'busy'};
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    bool allowed() =>
        mounted &&
        widget.admitted() &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.snapshot()['revision'] == revision);
    setState(() => _saving = true);
    try {
      final saved = await widget.vocabulary.createCategory(
        _controller.text,
        expectedOwnerId: expectedOwnerId,
        mutationAllowed: allowed,
      );
      // The ordinary button keeps its original completion path. Only the
      // optional MCP receipt needs a separate persisted-data verification.
      if (expectedOwnerId == null) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        }
        return {'status': 'invoked'};
      }
      final records = await widget.vocabulary.vocabulary
          .watchCategories(saved.ownerId)
          .first;
      final persisted = records
          .where(
            (record) =>
                record.id == saved.id &&
                record.ownerId == saved.ownerId &&
                record.name == saved.name &&
                record.normalizedName == saved.normalizedName &&
                record.localRevision == saved.localRevision &&
                !record.isDeleted,
          )
          .firstOrNull;
      if (persisted == null) return {'status': 'verification_failed'};
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
      return {
        'status': 'saved',
        'record': {
          'categoryId': persisted.id,
          'name': persisted.name,
          'revision': persisted.localRevision,
        },
      };
    } on InvalidVocabularyFailure {
      _message('กรุณากรอกชื่อหมวดหมู่ให้ถูกต้อง');
      return {'status': 'invalid'};
    } on DuplicateVocabularyFailure {
      _message('มีหมวดหมู่นี้แล้ว');
      return {'status': 'duplicate'};
    } catch (_) {
      _message('บันทึกหมวดหมู่ไม่สำเร็จ');
      return {'status': 'failed'};
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep bindings mounted even before optional AI is connected, so attaching
    // an owner does not replace the focused native form or discard its draft.
    return MenuActionBinding(
      id: 'vocabulary/category-fill',
      label: 'กรอกชื่อหมวดหมู่ (ยังไม่บันทึก)',
      ownerId: _formOwner,
      onInvoke: null,
      fields: const {'name': maxCategoryNameLength},
      onForm: _formOwner == null
          ? null
          : (values) {
              if (_saving || !widget.admitted()) return {'status': 'busy'};
              setState(() => _controller.text = values['name']!);
              return {'status': 'filled', 'values': values};
            },
      child: MenuActionBinding(
        id: 'vocabulary/category-save',
        label: 'บันทึกหมวดหมู่และตรวจผล',
        ownerId: _formOwner,
        revisionKey: _controller.text,
        onInvoke: null,
        onForm: _formOwner == null
            ? null
            : (_) => _save(expectedOwnerId: _formOwner),
        child: AlertDialog(
          title: const Text('เพิ่มหมวดหมู่'),
          scrollable: true,
          content: TextField(
            key: const ValueKey('category-name-field'),
            controller: _controller,
            autofocus: true,
            maxLength: maxCategoryNameLength,
            decoration: const InputDecoration(labelText: 'ชื่อหมวดหมู่'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const ValueKey('save-category'),
              onPressed: _saving ? null : () => _save(),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalDataUnavailable extends StatelessWidget {
  const _LocalDataUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'เปิดฐานข้อมูลในเครื่องไม่สำเร็จ\nกรุณาปิดและเปิดแอปใหม่',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('อ่านหมวดหมู่ไม่สำเร็จ'),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
