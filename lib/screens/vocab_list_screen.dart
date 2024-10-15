import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_vocab_screen.dart';

class VocabListScreen extends StatelessWidget {
  final CollectionReference _vocabCollection =
      FirebaseFirestore.instance.collection('vocab');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vocabulary List', style: TextStyle(fontSize: 24)),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddVocabScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _vocabCollection.snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Something went wrong!'));
          }
          final vocabList = snapshot.data!.docs;
          return ListView.builder(
            itemCount: vocabList.length,
            itemBuilder: (context, index) {
              final vocab = vocabList[index];
              return Card(
                margin: EdgeInsets.all(10),
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  title: Text(
                    vocab['word'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(vocab['meaning']),
                  trailing: IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      _vocabCollection.doc(vocab.id).delete();
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddVocabScreen(vocab: vocab),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
