import 'package:flutter/material.dart';

import '../features/vocabulary/domain/vocabulary_category.dart';
import '../runtime/app_dependencies.dart';

class SelectCategoryForQuiz extends StatelessWidget {
  const SelectCategoryForQuiz({super.key});

  @override
  Widget build(BuildContext context) {
    final vocabulary = AppDependenciesScope.maybeOf(context)?.vocabulary;
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกหมวดหมู่')),
      body: vocabulary == null
          ? const _CategoryMessage('ไม่สามารถเปิดคลังคำศัพท์ในเครื่องได้')
          : StreamBuilder<List<VocabularyCategory>>(
              stream: vocabulary.watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _CategoryMessage(
                    'อ่านหมวดหมู่ไม่สำเร็จ กรุณาลองใหม่',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final categories = snapshot.data!;
                if (categories.isEmpty) {
                  return const _CategoryMessage(
                    'ยังไม่มีหมวดหมู่ เพิ่มคำศัพท์ก่อนเริ่ม Quiz',
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
                        onTap: () => Navigator.pop(context, category.id),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _CategoryMessage extends StatelessWidget {
  const _CategoryMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
