import 'package:flutter/material.dart';
import '../services/category_service.dart';
import '../models/category_model.dart';
import 'ChooseModeScreen.dart';
import 'CategoriesPage.dart';

class Home extends StatelessWidget {
  final CategoryService _categoryService = CategoryService();

  Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แบบฝึกหัดคำศัพท์',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.category),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CategoriesPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),

          // 🎯 แถบแสดงความก้าวหน้า
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                const Text(
                  "ความก้าวหน้า",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: 0.4, // เปอร์เซ็นต์การเรียนรู้ (0.0 - 1.0)
                  backgroundColor: Colors.grey.shade300,
                  color: Colors.blueAccent,
                  minHeight: 8,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 🔥 แสดงหมวดหมู่จากฐานข้อมูล Firestore
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: StreamBuilder<List<Category>>(
                stream: _categoryService.getCategoriesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดหมวดหมู่'));
                  }

                  final categories = snapshot.data ?? [];
                  if (categories.isEmpty) {
                    return const Center(child: Text('ไม่มีหมวดหมู่ในขณะนี้'));
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.2,
                      mainAxisSpacing: 15,
                      crossAxisSpacing: 15,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];

                      return _buildCategoryCard(
                        category.name,
                        Icons.category, // ใช้ไอคอนหมวดหมู่ทั่วไป
                        Colors.blueAccent, // ใช้สีเริ่มต้น
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // 🟢 ปุ่มเริ่มเรียนรู้
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ChooseModeScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'เริ่มเรียนรู้',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 📌 ฟังก์ชันสร้างการ์ดหมวดหมู่คำศัพท์
  Widget _buildCategoryCard(String title, IconData icon, Color color) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          // TODO: เพิ่มการนำทางไปยังหน้าของหมวดหมู่นี้
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
