import 'package:flutter/material.dart';

class ShopPage extends StatefulWidget {
  @override
  _ShopPageState createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  // รายการวอลเปเปอร์
  final List<String> wallpapers = [
    'Wallpaper 1',
    'Wallpaper 2',
    'Wallpaper 3',
    'Wallpaper 4',
    'Wallpaper 5',
  ];

  // สถานะการซื้อวอลเปเปอร์
  String? selectedWallpaper; // วอลเปเปอร์ที่ถูกเลือกใช้อยู่
  Set<String> purchasedWallpapers = {}; // วอลเปเปอร์ที่ซื้อแล้ว

  // ฟังก์ชันแสดง Popup ยืนยันการซื้อ
  void _showPurchasePopup(String wallpaper) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('ยืนยันการซื้อ'),
          content: Text('คุณต้องการซื้อ $wallpaper หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // ปิด Popup
              },
              child: Text('ยกเลิก', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  purchasedWallpapers.add(wallpaper); // เพิ่มในรายการที่ซื้อแล้ว
                });
                Navigator.pop(context); // ปิด Popup
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$wallpaper ถูกซื้อสำเร็จ!')),
                );
              },
              child: Text('ยืนยัน', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        );
      },
    );
  }

  // ฟังก์ชันแสดง Popup ยืนยันการเปลี่ยนวอลเปเปอร์
  void _showChangeWallpaperPopup(String wallpaper) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('ยืนยันการเปลี่ยนพื้นหลัง'),
          content: Text('คุณต้องการเปลี่ยนพื้นหลังเป็น $wallpaper หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // ปิด Popup
              },
              child: Text('ยกเลิก', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedWallpaper = wallpaper; // เปลี่ยนวอลเปเปอร์
                });
                Navigator.pop(context); // ปิด Popup
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('เปลี่ยนพื้นหลังเป็น $wallpaper สำเร็จ!')),
                );
              },
              child: Text('ยืนยัน', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ร้านค้า',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: wallpapers.length,
          itemBuilder: (context, index) {
            final wallpaper = wallpapers[index];
            final isPurchased = purchasedWallpapers.contains(wallpaper);
            final isSelected = wallpaper == selectedWallpaper;

            return GestureDetector(
              onTap: () {
                if (isPurchased) {
                  _showChangeWallpaperPopup(wallpaper); // Popup เปลี่ยนวอลเปเปอร์
                } else {
                  _showPurchasePopup(wallpaper); // Popup ซื้อวอลเปเปอร์
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.green[100] : Colors.grey[300], // เปลี่ยนสีถ้าเลือก
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected
                      ? Border.all(color: Colors.green, width: 3)
                      : null,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        wallpaper,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isPurchased)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            isSelected ? 'กำลังใช้งาน' : 'ซื้อแล้ว',
                            style: TextStyle(
                              color: isSelected ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
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
