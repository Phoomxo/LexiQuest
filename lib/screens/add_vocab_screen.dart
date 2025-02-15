import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vocab_learning_app/models/word_model.dart';
import '../services/category_service.dart';

class AddWordScreen extends StatefulWidget {
  final String categoryId;
  final Word? word;

  const AddWordScreen({super.key, required this.categoryId, this.word});

  @override
  _AddWordScreenState createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  late TextEditingController _wordController;
  late TextEditingController _meaningController;
  late TextEditingController _partOfSpeechController;
  final CategoryService _categoryService = CategoryService();

  bool _isLoading = false;
  List<String> _suggestedWords = [];

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word?.word ?? '');
    _meaningController = TextEditingController(text: widget.word?.meaning ?? '');
    _partOfSpeechController = TextEditingController(text: widget.word?.partOfSpeech ?? '');
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestedWords = []);
      return;
    }
    final url = Uri.parse('https://api.datamuse.com/words?sp=$query*');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      setState(() {
        _suggestedWords = data.map<String>((word) => word['word']).toList();
      });
    }
  }

  Future<void> _fetchWordDetails(String word) async {
    final translationUrl = Uri.parse('https://api.mymemory.translated.net/get?q=$word&langpair=en|th');
    final translationResponse = await http.get(translationUrl);
    if (translationResponse.statusCode == 200) {
      final Map<String, dynamic> translationData = json.decode(translationResponse.body);
      final String translatedText = translationData['responseData']['translatedText'] ?? word;
      setState(() {
        _meaningController.text = translatedText;
      });
    }

    final posUrl = Uri.parse('https://api.datamuse.com/words?sp=$word&md=p');
    final posResponse = await http.get(posUrl);
    if (posResponse.statusCode == 200) {
      final List posData = json.decode(posResponse.body);
      if (posData.isNotEmpty && posData[0]['tags'] != null) {
        String posTag = posData[0]['tags'].firstWhere(
          (tag) => tag.startsWith('n') || tag.startsWith('v') || tag.startsWith('adj') || tag.startsWith('adv'),
          orElse: () => 'unknown'
        );
        setState(() {
          _partOfSpeechController.text = _convertPosTag(posTag);
        });
      }
    }
  }

  String _convertPosTag(String tag) {
    switch (tag) {
      case 'n': return 'Noun';
      case 'v': return 'Verb';
      case 'adj': return 'Adjective';
      case 'adv': return 'Adverb';
      default: return 'Unknown';
    }
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

    setState(() => _isLoading = true);

    try {
      if (widget.word == null) {
        await _categoryService.addWord(widget.categoryId, word, meaning, partOfSpeech);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Word added successfully')),
        );
      } else {
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
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.word == null ? 'Add Word' : 'Edit Word')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                await _fetchSuggestions(textEditingValue.text);
                return _suggestedWords;
              },
              onSelected: (String selection) {
                setState(() {
                  _wordController.text = selection;
                });
                _fetchWordDetails(selection);
              },
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  onChanged: (value) {
                    _fetchWordDetails(value);
                  },
                  decoration: const InputDecoration(labelText: 'Word'),
                );
              },
            ),
            TextField(
              controller: _meaningController,
              decoration: const InputDecoration(labelText: 'Meaning (Translated)'),
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
