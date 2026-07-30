import 'package:flutter/material.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../runtime/app_dependencies.dart';
import 'vocab_list_screen.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, this.vocabulary});

  final VocabularyUseCases? vocabulary;

  VocabularyUseCases? _useCases(BuildContext context) =>
      vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;

  @override
  Widget build(BuildContext context) {
    final useCases = _useCases(context);
    return Scaffold(
      appBar: AppBar(title: const Text('คลังคำศัพท์')),
      body: useCases == null
          ? const _LocalDataUnavailable()
          : StreamBuilder<List<VocabularyCategory>>(
              stream: useCases.watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _FailureState(onRetry: () {});
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
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(category.name),
                        subtitle: const Text('แตะเพื่อดูคำศัพท์'),
                        trailing: IconButton(
                          tooltip: 'ลบหมวดหมู่',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _confirmDelete(context, useCases, category),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VocabListScreen(
                                categoryId: category.id,
                                categoryName: category.name,
                                vocabulary: useCases,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: useCases == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('add-category'),
              heroTag: 'categories-add',
              onPressed: () => _showAddCategory(context, useCases),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มหมวดหมู่'),
            ),
    );
  }

  Future<void> _showAddCategory(
    BuildContext context,
    VocabularyUseCases useCases,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เพิ่มหมวดหมู่'),
        content: TextField(
          key: const ValueKey('category-name-field'),
          controller: controller,
          autofocus: true,
          maxLength: maxCategoryNameLength,
          decoration: const InputDecoration(labelText: 'ชื่อหมวดหมู่'),
          onSubmitted: (_) =>
              _saveCategory(dialogContext, useCases, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            key: const ValueKey('save-category'),
            onPressed: () =>
                _saveCategory(dialogContext, useCases, controller.text),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _saveCategory(
    BuildContext context,
    VocabularyUseCases useCases,
    String name,
  ) async {
    try {
      await useCases.createCategory(name);
      if (context.mounted) Navigator.pop(context);
    } on InvalidVocabularyFailure {
      if (context.mounted) {
        _showMessage(context, 'กรุณากรอกชื่อหมวดหมู่ให้ถูกต้อง');
      }
    } on DuplicateVocabularyFailure {
      if (context.mounted) {
        _showMessage(context, 'มีหมวดหมู่นี้แล้ว');
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'บันทึกหมวดหมู่ไม่สำเร็จ');
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategory category,
  ) async {
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
    if (accepted != true) return;
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
