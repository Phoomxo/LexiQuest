
import 'package:flutter/material.dart';
import '../models/word_model.dart';
import '../services/word_service.dart';
import 'add_vocab_screen.dart';

class VocabListScreen extends StatelessWidget {
  final String categoryId;
  final String categoryName; // เพิ่ม parameter นี้

  const VocabListScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName, // กำหนดให้ required
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final WordService wordService = WordService(categoryId: categoryId);

    void showDeleteConfirmationDialog(BuildContext context, Word word) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Word'),
          content: Text('Are you sure you want to delete "${word.word}"?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () async {
                await wordService.deleteWord(word.id!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Words in $categoryName'), // ใช้ categoryName ใน title
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Word>>(
        stream: wordService.getWordsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading words.'));
          }
          final words = snapshot.data ?? [];
          if (words.isEmpty) {
            return const Center(child: Text('No words added yet.'));
          }
          return ListView.builder(
            itemCount: words.length,
            itemBuilder: (context, index) {
              final word = words[index];
              return GestureDetector(
                onLongPress: () => showDeleteConfirmationDialog(context, word),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddWordScreen(
                        categoryId: categoryId,
                        word: word,
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(word.word),
                    subtitle: Text('${word.meaning} (${word.partOfSpeech})'),
                    trailing: const Icon(Icons.edit),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddWordScreen(
                categoryId: categoryId,
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
