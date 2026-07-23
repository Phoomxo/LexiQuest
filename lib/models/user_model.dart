class AppUser {
  final String uid;
  final String firstName;
  final String lastName;
  final int age;
  final String email;

  AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.email,
  });

  // สร้าง AppUser จากข้อมูลใน Firestore (DocumentSnapshot)
  factory AppUser.fromMap(Map<String, dynamic> data, String uid) {
    return AppUser(
      uid: uid,
      firstName: data['first_name'] ?? '',
      lastName: data['last_name'] ?? '',
      age: data['age'] ?? 0,
      email: data['email'] ?? '',
    );
  }

  int? get points => null;

  // แปลง AppUser เป็น Map เพื่อบันทึกใน Firestore
  Map<String, dynamic> toMap() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'age': age,
      'email': email,
    };
  }
}

class UserModel {
  final String id;
  final int points;

  UserModel({required this.id, required this.points});

  // Factory method สำหรับสร้าง UserModel จาก Firestore Document
  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(id: id, points: data['points'] ?? 0);
  }

  // แปลง UserModel object เป็น Map เพื่อบันทึกใน Firestore
  Map<String, dynamic> toMap() {
    return {'points': points};
  }
}
