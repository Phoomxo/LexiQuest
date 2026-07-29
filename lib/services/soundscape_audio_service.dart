enum SoundscapeType {
  alphaWaves('Alpha Waves (8-12Hz)', 'คลื่นสมองเพิ่มสมาธิ'),
  lofiBeats('Lo-Fi Study Beats', 'จังหวะผ่อนคลาย'),
  rainSound('Soft Rain', 'เสียงฝนตกเบาๆ'),
  off('Off', 'ปิดเสียงแบ็กกราวด์');

  final String nameEn;
  final String description;

  const SoundscapeType(this.nameEn, this.description);
}

class SoundscapeAudioService {
  SoundscapeType _currentType = SoundscapeType.off;

  SoundscapeType get currentType => _currentType;

  void setSoundscape(SoundscapeType type) {
    _currentType = type;
  }

  void stop() {
    _currentType = SoundscapeType.off;
  }
}
