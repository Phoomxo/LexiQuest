import '../models/background_model.dart';

class BackgroundService {
  BackgroundModel _currentBackground = BackgroundModel();

  /// ดึง URL ของพื้นหลังปัจจุบัน
  BackgroundModel get currentBackground => _currentBackground;

  /// ตั้งค่า URL ของพื้นหลังใหม่
  void setBackground(String url) {
    _currentBackground = BackgroundModel(backgroundUrl: url);
  }
}
