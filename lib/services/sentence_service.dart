import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/sentence_model.dart';

class SentenceService {
  static const String apiUrl =
      "https://649d-124-120-129-51.ngrok-free.app/generate_sentence/"; // ✅ ตรวจสอบให้แน่ใจว่า URL ถูกต้อง

  /// เรียก API เพื่อให้โมเดลสร้างประโยค
  static Future<SentenceModel?> fetchSentence(String word) async {
    try {
      final response = await http
          .get(Uri.parse("$apiUrl?word=$word"))
          .timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      debugPrint(
        "📡 API Response: ${response.body}",
      ); // ตรวจสอบว่า API ส่งค่ากลับมาหรือไม่

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        // ตรวจสอบ JSON Structure
        if (data is Map<String, dynamic> && data.containsKey("sentence")) {
          return SentenceModel.fromJson(data["sentence"]);
        } else {
          debugPrint("❌ API Error: JSON structure is incorrect.");
        }
      } else {
        debugPrint("❌ API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ API Request Failed: $e");
    }
    return null; // ถ้า API ใช้ไม่ได้ คืนค่า null
  }
}
