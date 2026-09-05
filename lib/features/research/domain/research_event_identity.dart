import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'motivation_study_protocol.dart';

/// UUID v7 carries the exact occurrence millisecond. The frozen EventsV2
/// DateTime columns use legacy epoch seconds; never alter that global mapping.
String researchEventId(String identity, DateTime occurredAtUtc) {
  requireResearchUtc(occurredAtUtc);
  final ms = occurredAtUtc.millisecondsSinceEpoch;
  if (ms > 0xffffffffffff) {
    throw const FormatException('Event timestamp out of range');
  }
  final time = ms.toRadixString(16).padLeft(12, '0');
  final hash = sha256.convert(utf8.encode(identity)).toString();
  final variant = (int.parse(hash[3], radix: 16) & 3 | 8).toRadixString(16);
  return '${time.substring(0, 8)}-${time.substring(8)}-7${hash.substring(0, 3)}-$variant${hash.substring(4, 7)}-${hash.substring(7, 19)}';
}

DateTime researchEventOccurrence(String eventId, DateTime storedOccurrence) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(eventId)) {
    throw const FormatException('Invalid research event identity');
  }
  final ms = int.parse(
    eventId.substring(0, 8) + eventId.substring(9, 13),
    radix: 16,
  );
  if (ms ~/ 1000 != storedOccurrence.millisecondsSinceEpoch ~/ 1000) {
    throw const FormatException('Research occurrence mismatch');
  }
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
