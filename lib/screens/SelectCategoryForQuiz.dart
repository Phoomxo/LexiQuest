import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SelectCategoryForQuiz extends StatefulWidget {
  const SelectCategoryForQuiz({super.key});

  @override
  _SelectCategoryForQuizState createState() => _SelectCategoryForQuizState();
}

class _SelectCategoryForQuizState extends State<SelectCategoryForQuiz> {
  List<Map<String, dynamic>> availableCategories = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAvailableCategories();
  }

  Future<void> _fetchAvailableCategories() async {
    final categoriesSnapshot =
        await FirebaseFirestore.instance.collection('categories').get();

    List<Map<String, dynamic>> filteredCategories = [];

    for (var categoryDoc in categoriesSnapshot.docs) {
      final wordsSnapshot = await categoryDoc.reference.collection('words').get();

      if (wordsSnapshot.docs.length >= 5) {
        filteredCategories.add({
          'id': categoryDoc.id,
          'name': categoryDoc['category_name'],
        });
      }
    }

    setState(() {
      availableCategories = filteredCategories;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกหมวดหมู่สำหรับฝึก'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : availableCategories.isEmpty
              ? const Center(
                  child: Text('ไม่มีหมวดหมู่ที่มีคำศัพท์มากกว่า 5 คำ'),
                )
              : ListView.builder(
                  itemCount: availableCategories.length,
                  itemBuilder: (context, index) {
                    final category = availableCategories[index];
                    return ListTile(
                      title: Text(category['name']),
                      onTap: () {
                        Navigator.pop(context, category['id']);
                      },
                    );
                  },
                ),
    );
  }
}
