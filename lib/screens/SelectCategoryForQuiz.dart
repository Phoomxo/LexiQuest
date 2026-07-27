import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final categoriesSnapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('uid', isEqualTo: user.uid)
        .get();

    List<Map<String, dynamic>> filteredCategories = [];

    for (var categoryDoc in categoriesSnapshot.docs) {
      final wordsCountSnapshot =
          await categoryDoc.reference.collection('words').count().get();

      if ((wordsCountSnapshot.count ?? 0) >= 5) {
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7B1FA2), Color(0xFF2196F3)], // ม่วง -> ฟ้า
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : availableCategories.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่มีหมวดหมู่ที่มีคำศัพท์มากกว่า 5 คำ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: ListView.builder(
                    itemCount: availableCategories.length,
                    itemBuilder: (context, index) {
                      final category = availableCategories[index];
                      return Card(
                        color: const Color(0xFFB39DDB), // ม่วงอ่อน
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 6,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF673AB7), // ม่วงเข้ม
                            child: const Icon(Icons.category, color: Colors.white),
                          ),
                          title: Text(
                            category['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.white),
                          onTap: () {
                            Navigator.pop(context, category['id']);
                          },
                        ),
                      );
                    },
                  ),
                ),
      backgroundColor: const Color(0xFFEDE7F6), // สีม่วงอ่อนเป็นพื้นหลัง
    );
  }
}
