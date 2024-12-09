import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVocabScreen extends StatefulWidget {
  final QueryDocumentSnapshot? vocab;

  AddVocabScreen({this.vocab, required String categoryName});

  @override
  _AddVocabScreenState createState() => _AddVocabScreenState();
}

class _AddVocabScreenState extends State<AddVocabScreen> {
  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _meaningController = TextEditingController();
  final CollectionReference _vocabCollection =
      FirebaseFirestore.instance.collection('vocab');

  @override
  void initState() {
    super.initState();
    if (widget.vocab != null) {
      _wordController.text = widget.vocab!['word'];
      _meaningController.text = widget.vocab!['meaning'];
    }
  }

  Future<void> _saveVocab() async {
    if (widget.vocab == null) {
      await _vocabCollection.add({
        'word': _wordController.text,
        'meaning': _meaningController.text,
      });
    } else {
      await _vocabCollection.doc(widget.vocab!.id).update({
        'word': _wordController.text,
        'meaning': _meaningController.text,
      });
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.vocab == null ? 'Add Vocabulary' : 'Edit Vocabulary'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Word',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _meaningController,
              decoration: InputDecoration(
                labelText: 'Meaning',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _saveVocab,
              child: Text('Save', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
