import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

class CategoriesPage extends StatelessWidget {
  final CollectionReference _categoriesCollection =
      FirebaseFirestore.instance.collection('categories');

  // ฟังก์ชันลบหมวดหมู่
  Future<void> _deleteCategory(BuildContext context, String categoryId, String categoryName) async {
    // แสดง Dialog ยืนยันการลบ
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Category'),
        content: Text('Are you sure you want to delete the category "$categoryName"?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Delete'),
            onPressed: () async {
              await _categoriesCollection.doc(categoryId).delete();
              Navigator.pop(context); // ปิด Dialog หลังจากลบ
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Categories'),
      ),
      body: StreamBuilder(
        stream: _categoriesCollection.snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading categories.'));
          }
          final categories = snapshot.data!.docs;
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final DocumentSnapshot category = categories[index];
              return GestureDetector(
                onLongPress: () {
                  // เรียกฟังก์ชันลบหมวดหมู่
                  _deleteCategory(context, category.id, category['category_name']);
                },
                onTap: () {
                   Navigator.pop(context, category.id);
                  // เปิดหน้า VocabListScreen สำหรับดูคำศัพท์ในหมวดหมู่
                  Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => VocabListScreen(
      categoryId: category.id,
      categoryName: category['category_name'],
    ),
  ),
);

                },
                child: Card(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
  title: Text(category['category_name']),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VocabListScreen(
          categoryId: category.id,
          categoryName: category['category_name'],
        ),
      ),
    );
  },
)
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // เพิ่มหมวดหมู่ใหม่
          TextEditingController _addController = TextEditingController();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Add Category'),
              content: TextField(
                controller: _addController,
                decoration: InputDecoration(labelText: 'Category Name'),
              ),
              actions: [
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text('Add'),
                  onPressed: () async {
                    await _categoriesCollection.add({
                      'category_name': _addController.text.trim(),
                      'created_at': Timestamp.now(),
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
