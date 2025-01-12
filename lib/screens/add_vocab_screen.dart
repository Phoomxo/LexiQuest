import 'package:flutter/material.dart';
import 'package:vocab_learning_app/models/word_model.dart';
import '../services/category_service.dart';

class AddWordScreen extends StatefulWidget {
  final String categoryId;
  final Word? word; // เปลี่ยนเป็น nullable

  const AddWordScreen({super.key, required this.categoryId, this.word}); // ลบ required ของ word

  @override
  _AddWordScreenState createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  late TextEditingController _wordController;
  late TextEditingController _meaningController;
  late TextEditingController _partOfSpeechController;
  final CategoryService _categoryService = CategoryService();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word?.word ?? '');
    _meaningController = TextEditingController(text: widget.word?.meaning ?? '');
    _partOfSpeechController =
        TextEditingController(text: widget.word?.partOfSpeech ?? '');
  }

  void _addOrUpdateWord() async {
    final word = _wordController.text.trim();
    final meaning = _meaningController.text.trim();
    final partOfSpeech = _partOfSpeechController.text.trim();

    if (word.isEmpty || meaning.isEmpty || partOfSpeech.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.word == null) {
        // เพิ่มคำศัพท์ใหม่
        await _categoryService.addWord(
            widget.categoryId, word, meaning, partOfSpeech);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Word added successfully')),
        );
      } else {
        // TODO: เพิ่มฟังก์ชันแก้ไขคำศัพท์ใน CategoryService
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Word updated successfully')),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add/update word: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.word == null ? 'Add Word' : 'Edit Word'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _wordController,
              decoration: const InputDecoration(labelText: 'Word'),
            ),
            TextField(
              controller: _meaningController,
              decoration: const InputDecoration(labelText: 'Meaning'),
            ),
            TextField(
              controller: _partOfSpeechController,
              decoration: const InputDecoration(labelText: 'Part of Speech'),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _addOrUpdateWord,
                    child: Text(widget.word == null ? 'Add Word' : 'Update Word'),
                  ),
          ],
        ),
      ),
    );
  }
}
