final class AccountValidation {
  AccountValidation._();

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String? emailError(String value) {
    final email = normalizeEmail(value);
    if (email.isEmpty) return 'กรุณากรอกอีเมล';
    if (!_emailPattern.hasMatch(email)) return 'รูปแบบอีเมลไม่ถูกต้อง';
    return null;
  }

  static String? passwordError(String value) {
    if (value.length < 8 ||
        !_letterPattern.hasMatch(value) ||
        !_numberPattern.hasMatch(value)) {
      return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร และมีทั้งตัวอักษรและตัวเลข';
    }
    return null;
  }

  static String? confirmationError(String password, String confirmation) {
    if (confirmation.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
    if (password != confirmation) return 'รหัสผ่านไม่ตรงกัน';
    return null;
  }

  static String? nameError(String value) =>
      value.trim().isEmpty ? 'กรุณากรอกชื่อ' : null;

  static String? firstNameError(String value) => nameError(value);

  static String? lastNameError(String value) => nameError(value);

  static String? ageError(Object? value) {
    final age = switch (value) {
      int value => value,
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (age == null || age < 6 || age > 120) {
      return 'อายุต้องอยู่ระหว่าง 6 ถึง 120 ปี';
    }
    return null;
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  // Dart core does not expose Unicode general-category classification. Until
  // the product adopts a dedicated Unicode-classification dependency, this
  // password contract recognizes Latin and Thai letters plus ASCII and Thai
  // decimal digits. Other characters may be present but do not satisfy either
  // required character class.
  static final _letterPattern = RegExp(
    r'[A-Za-z'
    r'\u0E01-\u0E2E'
    r'\u0E30'
    r'\u0E32-\u0E33'
    r'\u0E40-\u0E45]',
  );
  static final _numberPattern = RegExp(r'[0-9\u0E50-\u0E59]');
}
