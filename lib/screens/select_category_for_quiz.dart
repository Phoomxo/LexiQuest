import 'package:flutter/material.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../runtime/app_dependencies.dart';

class SelectCategoryForQuiz extends StatefulWidget {
  const SelectCategoryForQuiz({
    super.key,
    this.vocabulary,
    this.onSelect,
    this.expectedOwnerId,
  });

  final VocabularyUseCases? vocabulary;
  final Future<void> Function(BuildContext, VocabularyCategory)? onSelect;
  final String? expectedOwnerId;

  @override
  State<SelectCategoryForQuiz> createState() => _SelectCategoryForQuizState();
}

class _SelectCategoryForQuizState extends State<SelectCategoryForQuiz> {
  var _retryEpoch = 0;
  bool _opening = false;
  Stream<String?>? _ownerChanges;
  AppDependencies? _dependencies;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!identical(dependencies, _dependencies)) {
      _dependencies = dependencies;
      _ownerChanges = dependencies?.watchActiveOwnerId();
    }
  }

  Future<void> _select(VocabularyCategory category) async {
    final onSelect = widget.onSelect;
    if (onSelect == null) {
      Navigator.pop(context, category.id);
      return;
    }
    if (_opening) return;
    _opening = true;
    try {
      await onSelect(context, category);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vocabulary =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกหมวดหมู่')),
      body: _ownerChanges != null && widget.expectedOwnerId != null
          ? StreamBuilder<String?>(
              key: ObjectKey(_ownerChanges),
              stream: _ownerChanges,
              builder: (context, owner) {
                if (owner.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'กำลังตรวจบัญชีผู้เรียน',
                    ),
                  );
                }
                if (owner.data != widget.expectedOwnerId) {
                  return const _CategoryMessage('เปลี่ยนผู้ใช้แล้ว');
                }
                return _categories(vocabulary);
              },
            )
          : _categories(vocabulary),
    );
  }

  Widget _categories(VocabularyUseCases? vocabulary) => vocabulary == null
      ? const _CategoryMessage('ไม่สามารถเปิดคลังคำศัพท์ในเครื่องได้')
      : StreamBuilder<List<VocabularyCategory>>(
          key: ValueKey<int>(_retryEpoch),
          stream: vocabulary.watchCategories(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _CategoryFailure(
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
            final categories = snapshot.data!
                .where(
                  (category) =>
                      widget.expectedOwnerId == null ||
                      category.ownerId == widget.expectedOwnerId,
                )
                .toList(growable: false);
            if (categories.isEmpty) {
              return _CategoryMessage(
                'ยังไม่มีหมวดหมู่ เพิ่มคำศัพท์จากแท็บคำศัพท์ก่อนเริ่มแบบทดสอบ',
                actionLabel: 'กลับไปหน้าเรียน',
                onAction: () => Navigator.maybePop(context),
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
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _select(category),
                  ),
                );
              },
            );
          },
        );
}

class _CategoryFailure extends StatelessWidget {
  const _CategoryFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                'อ่านหมวดหมู่ไม่สำเร็จ กรุณาลองใหม่',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}

class _CategoryMessage extends StatelessWidget {
  const _CategoryMessage(this.message, {this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
