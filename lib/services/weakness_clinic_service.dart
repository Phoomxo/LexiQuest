import '../models/srs_item.dart';

class WeaknessClinicService {
  const WeaknessClinicService();

  /// Curates top weakness items (Box 1 or low ease factor) into a specialized practice deck.
  List<SrsItem> curateWeaknessDeck(List<SrsItem> allItems, {int limit = 10}) {
    final copy = List<SrsItem>.from(allItems);
    copy.sort((a, b) {
      final boxCompare = a.boxLevel.compareTo(b.boxLevel);
      if (boxCompare != 0) return boxCompare;
      return a.easeFactor.compareTo(b.easeFactor);
    });
    return copy.take(limit).toList();
  }
}
