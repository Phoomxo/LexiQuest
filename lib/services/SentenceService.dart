import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/SentenceModel.dart';

class SentenceService {
  static const String apiUrl = "http://192.168.146.225:8000/generate_sentence/"; // ✅ แก้เป็น 127.0.0.1

  /// ✅ เรียก API เพื่อให้โมเดลสร้างประโยค
  static Future<SentenceModel?> fetchSentence(String word) async {
    try {
      final response = await http.get(Uri.parse("$apiUrl?word=$word"));

      print("📡 API Response: ${response.body}"); // ✅ Debug: ดูว่า API ส่งค่ากลับมาหรือไม่

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        // ✅ ตรวจสอบ JSON Structure
        if (data is Map<String, dynamic> && data.containsKey("sentence")) {
          return SentenceModel.fromJson(data["sentence"]);
        }
      } else {
        print("❌ API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ API Request Failed: $e");
    }
    return null; // ❌ ถ้า API ใช้ไม่ได้ คืนค่า null
  }
}
