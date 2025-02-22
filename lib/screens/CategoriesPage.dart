import 'package:flutter/material.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import '../models/category_model.dart';
import '../services/category_service.dart';
import '/screens/vocab_list_screen.dart';


class CategoriesPage extends StatelessWidget {
  final CategoryService _categoryService = CategoryService();

  CategoriesPage({super.key});

  // Function to delete a category with confirmation dialog
  void _deleteCategory(BuildContext context, String categoryId, String categoryName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบหมวดหมู่'),
        content: Text('คุณต้องการลบ "$categoryName" ใช่หรือไม่?'),
        actions: [
          TextButton(
            child: const Text('ยกเลิก'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'ลบ',
              style: TextStyle(color: Colors.red),
            ),
            onPressed: () async {
              await _categoryService.deleteCategory(categoryId);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // Function to show the add category dialog
  void _showAddCategoryDialog(BuildContext context) {
    TextEditingController addController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มหมวดหมู่'),
        content: TextField(
          controller: addController,
          decoration: const InputDecoration(labelText: 'ชื่อหมวดหมู่'),
        ),
        actions: [
          TextButton(
            child: const Text('ยกเลิก'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('เพิ่ม'),
            onPressed: () async {
              final categoryName = addController.text.trim();
              if (categoryName.isNotEmpty) {
                await _categoryService.addCategory(categoryName);
              }
              Navigator.pop(context);
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
  title: const Text(
    'หมวดหมู่คำศัพท์',
    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
  ),
  centerTitle: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  flexibleSpace: Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.deepPurple, Colors.indigo],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ),
),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
        child: StreamBuilder<List<Category>>(
          stream: _categoryService.getCategoriesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล'));
            }

            final categories = snapshot.data ?? [];
            if (categories.isEmpty) {
              return const Center(child: Text('ไม่มีหมวดหมู่ในขณะนี้'));
            }

            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // แสดง 2 คอลัมน์
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];

                return GestureDetector(
                  onLongPress: () => _deleteCategory(context, category.id!, category.name),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VocabListScreen(
                          categoryId: category.id!,
                          categoryName: category.name,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getCategoryIcon(category.name),
                          size: 40,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          category.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),

      // 🟢 ปุ่มเพิ่มหมวดหมู่
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCategoryDialog(context),
        label: const Text('เพิ่มหมวดหมู่'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.green,
      ),
    );
  }

  // 📌 ฟังก์ชันกำหนดไอคอนให้แต่ละหมวด
  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'สัตว์':
        return Icons.pets;
      case 'อาหาร':
        return Icons.fastfood;
      case 'สถานที่':
        return Icons.location_on;
      case 'กีฬา':
        return Icons.sports_soccer;
      case 'อาชีพ':
        return Icons.work;
      case 'ตัวเลข':
        return Icons.numbers;
      default:
        return Icons.category; // ไอคอนเริ่มต้น
    }
  }
}
