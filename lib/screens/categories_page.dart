import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../runtime/app_dependencies.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';
import 'vocab_list_screen.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.vocabulary, this.onOpenMenu});

  final VocabularyUseCases? vocabulary;
  final VoidCallback? onOpenMenu;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  var _retryEpoch = 0;

  VocabularyUseCases? _useCases(BuildContext context) =>
      widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;

  @override
  Widget build(BuildContext context) {
    final useCases = _useCases(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'คลังคำศัพท์'),
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
      body: AdaptiveContentPane(
        child: useCases == null
            ? const _LocalDataUnavailable()
            : StreamBuilder<List<VocabularyCategory>>(
                key: ValueKey<int>(_retryEpoch),
                stream: useCases.watchCategories(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _FailureState(
                      onRetry: () => setState(() => _retryEpoch++),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'กำลังโหลดหมวดหมู่',
                      ),
                    );
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
                            tooltip: 'ลบหมวดหมู่ ${category.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                _confirmDelete(context, useCases, category),
                          ),
                          onTap: () {
                            AppNavigator.pushPage<void>(
                              context,
                              AppPage<void>(
                                name: 'vocabulary/category',
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
    var name = '';
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            if (busy) return;
            if (name.trim().isEmpty) {
              setDialogState(() => error = 'กรอกชื่อหมวดหมู่');
              return;
            }
            setDialogState(() {
              busy = true;
              error = null;
            });
            try {
              await useCases.createCategory(name);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } on InvalidVocabularyFailure {
              if (dialogContext.mounted) {
                setDialogState(
                  () => error = 'กรอกชื่อหมวดหมู่ไม่เกิน 80 ตัวอักษร',
                );
              }
            } on DuplicateVocabularyFailure {
              if (dialogContext.mounted) {
                setDialogState(() => error = 'มีหมวดหมู่นี้แล้ว');
              }
            } catch (_) {
              if (dialogContext.mounted) {
                setDialogState(() => error = 'บันทึกหมวดหมู่ไม่สำเร็จ');
              }
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => busy = false);
              }
            }
          }

          return PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('เพิ่มหมวดหมู่'),
              content: TextField(
                key: const ValueKey('category-name-field'),
                autofocus: true,
                enabled: !busy,
                maxLength: maxCategoryNameLength,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'ชื่อหมวดหมู่',
                  errorText: error,
                ),
                onChanged: (value) {
                  name = value;
                  if (error != null) setDialogState(() => error = null);
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  key: const ValueKey('save-category'),
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'กำลังบันทึก…' : 'บันทึก'),
                ),
              ],
            ),
          );
        },
      ),
    );
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
          Semantics(liveRegion: true, child: Text('อ่านหมวดหมู่ไม่สำเร็จ')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
