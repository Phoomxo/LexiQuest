final class LearningRecordValidation {
  const LearningRecordValidation._();

  static void identifier(String value, String name, {int maxLength = 200}) {
    if (value.trim().isEmpty || value.length > maxLength) {
      throw ArgumentError.value(
        value,
        name,
        'must be non-empty and at most $maxLength characters',
      );
    }
  }

  static void opaqueIdentifier(String value, String name) {
    identifier(value, name);
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'must contain only opaque identifier characters',
      );
    }
  }

  static DateTime utc(DateTime value) => value.toUtc();

  static void finiteAtLeast(double value, String name, double minimum) {
    if (!value.isFinite || value < minimum) {
      throw ArgumentError.value(value, name, 'must be finite and >= $minimum');
    }
  }

  static void finiteRange(
    double value,
    String name,
    double minimum,
    double maximum,
  ) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw ArgumentError.value(
        value,
        name,
        'must be finite and between $minimum and $maximum',
      );
    }
  }

  static void schemaVersion(int value) {
    if (value != 1) {
      throw ArgumentError.value(value, 'schemaVersion', 'must be 1');
    }
  }
}
