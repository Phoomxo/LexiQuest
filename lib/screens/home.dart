import 'package:flutter/material.dart';
import '../services/category_service.dart';
import '../models/category_model.dart';
import 'main_navigation_screen.dart';

class Home extends StatelessWidget {
  final CategoryService _categoryService = CategoryService();

  Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แบบฝึกหัดคำศัพท์',
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

      body: Column(
        children: [
          const SizedBox(height: 16),

          // 🎯 แถบแสดงความก้าวหน้าแบบ Glassmorphic Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.track_changes, color: Colors.deepPurple),
                          SizedBox(width: 8),
                          Text(
                            "ความก้าวหน้าการเรียนรู้ประจำวัน",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      Chip(
                        backgroundColor: Colors.amber.shade100,
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          '40%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: 0.4,
                      backgroundColor: Colors.deepPurple.shade100,
                      color: Colors.amber,
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

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
                    return const Center(
                      child: Text('เกิดข้อผิดพลาดในการโหลดหมวดหมู่'),
                    );
                  }

                  final categories = snapshot.data ?? [];
                  if (categories.isEmpty) {
                    return const Center(child: Text('ไม่มีหมวดหมู่ในขณะนี้'));
                  }

                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                        Icons.category,
                        Colors.blueAccent,
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
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MainNavigationScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.play_circle_fill,
                  size: 24,
                  color: Colors.white,
                ),
                label: const Text(
                  'เข้าสู่ศูนย์การเรียนรู้ LexiQuest (Start)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
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
      color: Colors.white.withValues(alpha: 0.9), // ✅ ทำให้การ์ดโปร่งใสเล็กน้อย
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: Colors.deepPurple,
            ), // ✅ เปลี่ยนสีไอคอนให้เข้ากับธีม
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
