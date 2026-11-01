import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

var _initialized = false;

void ensureLearningTimezonesInitialized() {
  if (_initialized) return;
  timezone_data.initializeTimeZones();
  _initialized = true;
}

final _ianaName = RegExp(r'^(?:UTC|[A-Za-z_+-]+(?:/[A-Za-z0-9_+.-]+)+)$');

String requireLearningTimezone(String value) {
  if (value.length > 100 || !_ianaName.hasMatch(value)) {
    throw const FormatException('Choose an IANA learning timezone');
  }
  ensureLearningTimezonesInitialized();
  if (!timezone.timeZoneDatabase.locations.containsKey(value)) {
    throw const FormatException('Unknown learning timezone');
  }
  return value;
}

List<String> get learningTimezoneIds {
  ensureLearningTimezonesInitialized();
  return List.unmodifiable(
    timezone.timeZoneDatabase.locations.keys.where(_ianaName.hasMatch).toList()
      ..sort(),
  );
}
