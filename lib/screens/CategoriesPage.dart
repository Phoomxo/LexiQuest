import 'package:flutter/material.dart';

class CategoriesPage extends StatefulWidget {
  @override
  _CategoriesPageState createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  // รายการหมวดหมู่
  List<String> categories = []; // เก็บชื่อหมวดหมู่

  // ตัวควบคุมข้อความใน TextField สำหรับเพิ่มหมวดหมู่
  final TextEditingController _categoryController = TextEditingController();

  // ฟังก์ชันเปิด Popup สำหรับเพิ่มหมวดหมู่
  void _showAddCategoryPopup() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('เพิ่มหมวดหมู่'),
          content: TextField(
            controller: _categoryController,
            decoration: InputDecoration(
              labelText: 'ชื่อหมวดหมู่',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (_categoryController.text.isNotEmpty) {
                  setState(() {
                    categories.add(_categoryController.text); // เพิ่มชื่อหมวดหมู่
                  });
                  _categoryController.clear();
                  Navigator.pop(context); // ปิด Popup
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text('ยืนยัน'),
            ),
            ElevatedButton(
              onPressed: () {
                _categoryController.clear();
                Navigator.pop(context); // ปิด Popup
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('ยกเลิก'),
            ),
          ],
        );
      },
    );
  }

  // ฟังก์ชันสำหรับไปยังหน้าหมวดหมู่ที่เลือก
  void _goToCategory(String categoryName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VocabularyPage(categoryName: categoryName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('หมวดหมู่คำศัพท์'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddCategoryPopup, // กดแล้วเปิด Popup
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // จำนวนคอลัมน์ในตาราง
            crossAxisSpacing: 16, // ระยะห่างระหว่างคอลัมน์
            mainAxisSpacing: 16, // ระยะห่างระหว่างแถว
          ),
          itemCount: categories.length, // จำนวนหมวดหมู่ที่แสดง
          itemBuilder: (context, index) {
            final category = categories[index];
            return GestureDetector(
              onTap: () => _goToCategory(category), // ไปยังหน้าคำศัพท์ของหมวดนี้
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300], // สีพื้นหลังของหมวดหมู่
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    category,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// หน้าคำศัพท์ในหมวดหมู่
class VocabularyPage extends StatelessWidget {
  final String categoryName;

  VocabularyPage({required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('คำศัพท์ในหมวด: $categoryName'),
      ),
      body: Center(
        child: Text(
          'เพิ่มคำศัพท์ในหมวด "$categoryName"',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
