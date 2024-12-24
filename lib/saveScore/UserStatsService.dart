import 'package:cloud_firestore/cloud_firestore.dart';

class UserStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ฟังก์ชันอัปเดต user_stats
  Future<void> updateUserStats({
    required String userId,
    required List<Map<String, dynamic>> vocabList,
  }) async {
    try {
      // อ้างอิงถึง subcollection 'words' ของ user_stats
      final CollectionReference userStatsCollection = _firestore
          .collection('user_stats')
          .doc(userId)
          .collection('words');

      for (var vocab in vocabList) {
        final docRef = userStatsCollection.doc(vocab['vocab_id']);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          // หากเอกสารมีอยู่แล้ว ให้อัปเดตข้อมูล
          await docRef.update({
            'times_correct': FieldValue.increment(vocab['is_correct'] ? 1 : 0),
            'times_wrong': FieldValue.increment(!vocab['is_correct'] ? 1 : 0),
            'last_attempt': Timestamp.now(),
          });
        } else {
          // หากเอกสารยังไม่มี ให้เพิ่มใหม่
          await docRef.set({
            'times_correct': vocab['is_correct'] ? 1 : 0,
            'times_wrong': !vocab['is_correct'] ? 1 : 0,
            'last_attempt': Timestamp.now(),
          });
        }
      }
      print('User stats updated successfully!');
    } catch (e) {
      print('Error updating user stats: $e');
    }
  }
}
