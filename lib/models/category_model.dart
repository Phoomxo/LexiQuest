import 'package:cloud_firestore/cloud_firestore.dart';

class Category {
  final String? id;
  final String name;
  final DateTime createdAt;

  Category({this.id, required this.name, required this.createdAt});

  // สร้าง Category object จาก Firestore Document
  factory Category.fromDocumentSnapshot(DocumentSnapshot doc) {
    return Category(
      id: doc.id,
      name: doc['category_name'],
      createdAt: (doc['created_at'] as Timestamp).toDate(),
    );
  }

  // แปลง Category object เป็น Map สำหรับบันทึกลง Firestore
  Map<String, dynamic> toMap() {
    return {'category_name': name, 'created_at': Timestamp.fromDate(createdAt)};
  }
}
