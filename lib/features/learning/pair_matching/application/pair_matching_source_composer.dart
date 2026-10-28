import '../../../review/domain/review_queue_item.dart';
import '../../../today_hub/domain/today_hub_models.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_plan.dart';

/// Explicit curator-owned manifest, never a caller's `isCurated` assertion.
/// Delivery defaults to an empty manifest; rollout must supply reviewed pins.
final class PairCuratedAllowlist {
  PairCuratedAllowlist({
    required this.version,
    required Iterable<PairLexicalItem> items,
  }) : items = List.unmodifiable(items) {
    if (version.isEmpty ||
        version.length > 256 ||
        this.items.map((i) => i.canonicalIdentity).toSet().length !=
            this.items.length) {
      // Repeated provenance inputs are harmless only when the pin is identical.
      final seen = <String, PairLexicalItem>{};
      for (final item in this.items) {
        final prior = seen[item.canonicalIdentity];
        if (prior != null && !_samePin(prior, item)) {
          throw ArgumentError('Conflicting curated pins');
        }
        seen[item.canonicalIdentity] = item;
      }
      if (version.isEmpty || version.length > 256) {
        throw ArgumentError('Invalid allowlist version');
      }
    }
  }
  factory PairCuratedAllowlist.disabled() =>
      PairCuratedAllowlist(version: 'disabled-v1', items: const []);
  final String version;
  final List<PairLexicalItem> items;
  bool accepts(PairLexicalItem item) =>
      items.any((pin) => _samePin(pin, item)) &&
      item.sourceLocale == 'en' &&
      item.targetLocale == 'th';
  PairLexicalItem? _snapshot(ReviewQueueItem item) {
    for (final pin in items) {
      if (pin.wordId == item.identity.id &&
          pin.contentRevision == item.identity.revision &&
          pin.checksum == item.snapshot.coreChecksumSha256 &&
          pin.spelling == item.spelling &&
          pin.meaning == item.meaning) {
        return pin.withReasons(
          item.reasons.map(
            (r) => switch (r) {
              ReviewQueueReason.dueSrs => PairSourceReason.dueSrs,
              ReviewQueueReason.incorrectAnswer =>
                PairSourceReason.incorrectAnswer,
              ReviewQueueReason.reported => PairSourceReason.reported,
              ReviewQueueReason.saved => PairSourceReason.saved,
            },
          ),
        );
      }
    }
    return null;
  }
}

/// A captured input, not a reader. No Today reload/query exists on this seam.
final class PairSourceSnapshot {
  PairSourceSnapshot.learn({
    required this.ownerId,
    required this.reference,
    required Iterable<PairLexicalItem> items,
    Set<String> deletedWordIds = const {},
    Set<String> reportedWordIds = const {},
  }) : surface = PairSourceSurface.learn,
       selectedCount = null,
       items = List.unmodifiable(items),
       deletedWordIds = Set.unmodifiable(deletedWordIds),
       reportedWordIds = Set.unmodifiable(reportedWordIds);
  PairSourceSnapshot._({
    required this.ownerId,
    required this.reference,
    required this.surface,
    required Iterable<PairLexicalItem> items,
    this.selectedCount,
  }) : items = List.unmodifiable(items),
       deletedWordIds = const {},
       reportedWordIds = const {};
  factory PairSourceSnapshot.review({
    required String ownerId,
    required String reference,
    required List<ReviewQueueItem> selection,
    required PairCuratedAllowlist allowlist,
  }) => PairSourceSnapshot._(
    ownerId: ownerId,
    reference: reference,
    surface: PairSourceSurface.review,
    selectedCount: selection.length,
    items: selection.map(allowlist._snapshot).whereType<PairLexicalItem>(),
  );
  factory PairSourceSnapshot.today({
    required TodayHubSnapshot snapshot,
    required PairCuratedAllowlist allowlist,
  }) => PairSourceSnapshot._(
    ownerId: snapshot.ownerId,
    reference: 'today:${snapshot.evaluatedAtUtc.millisecondsSinceEpoch}',
    surface: PairSourceSurface.today,
    items: snapshot.reviewWork
        .map(
          (w) => allowlist._snapshot(
            ReviewQueueItem(snapshot: w.snapshot, provenance: w.provenance),
          ),
        )
        .whereType<PairLexicalItem>(),
  );
  final String ownerId;
  final String reference;
  final PairSourceSurface surface;
  final int? selectedCount;
  final List<PairLexicalItem> items;
  final Set<String> deletedWordIds;
  final Set<String> reportedWordIds;
}

sealed class PairPlanResolution {
  const PairPlanResolution();
}

final class PairPlanReady extends PairPlanResolution {
  const PairPlanReady(this.plan);
  final PairMatchingPlanV1 plan;
}

enum PairPlanUnavailableReason {
  ownerChanged,
  sourceChanged,
  insufficientSafeContent,
  unsupportedPurpose,
  unsafeContent,
}

final class PairPlanUnavailable extends PairPlanResolution {
  const PairPlanUnavailable(this.reason);
  final PairPlanUnavailableReason reason;
}

final class PairPlanNeedsDensityChoice extends PairPlanResolution {
  const PairPlanNeedsDensityChoice();
}

final class PairPlanNeedsDensityConfirmation extends PairPlanResolution {
  const PairPlanNeedsDensityConfirmation();
  PairDensity get offeredDensity => PairDensity.compact4;
}

final class PairMatchingSourceComposer {
  const PairMatchingSourceComposer({required this.allowlist});
  final PairCuratedAllowlist allowlist;
  PairPlanResolution adventure({
    required String ownerId,
    required PairMatchingPlanV1 acceptedPlan,
  }) => ownerId == acceptedPlan.ownerId
      ? PairPlanReady(acceptedPlan)
      : const PairPlanUnavailable(PairPlanUnavailableReason.ownerChanged);

  PairPlanResolution compose({
    required PairMatchingLaunchIntent launch,
    required PairSourceSnapshot source,
    required PairDensityPreferences preferences,
    required int shuffleSeed,
    bool canPrompt = false,
    bool acceptCompactFallback = false,
  }) {
    if (launch.ownerId != source.ownerId ||
        launch.ownerId != preferences.ownerId) {
      return const PairPlanUnavailable(PairPlanUnavailableReason.ownerChanged);
    }
    if (launch.sourceSurface != source.surface ||
        launch.sourceSnapshotRef != source.reference) {
      return const PairPlanUnavailable(PairPlanUnavailableReason.sourceChanged);
    }
    if (launch.sessionPurpose != PairSessionPurpose.learning ||
        launch.sourceSurface == PairSourceSurface.adventure ||
        launch.sourceSurface == PairSourceSurface.history) {
      return const PairPlanUnavailable(
        PairPlanUnavailableReason.unsupportedPurpose,
      );
    }
    final density = preferences.resolve(
      requested: launch.requestedDensity,
      canPrompt: canPrompt,
    );
    if (density == null) return const PairPlanNeedsDensityChoice();
    final merged = <String, PairLexicalItem>{};
    final rejected = <String>{
      ...source.deletedWordIds,
      ...source.reportedWordIds,
    };
    for (final item in source.items) {
      final prior = merged[item.wordId];
      if (prior != null && !_samePin(prior, item)) rejected.add(item.wordId);
      merged[item.wordId] = prior == null
          ? item
          : prior.withReasons({...prior.sourceReasons, ...item.sourceReasons});
    }
    final safe = merged.values
        .where(
          (i) =>
              !rejected.contains(i.wordId) &&
              !i.sourceReasons.contains(PairSourceReason.reported) &&
              allowlist.accepts(i),
        )
        .toList();
    final en = <String, List<String>>{}, th = <String, List<String>>{};
    for (final item in safe) {
      final a = pairVisibleKey(item.spelling, 'en'),
          b = pairVisibleKey(item.meaning, 'th');
      if (a == null || b == null) {
        rejected.add(item.wordId);
        continue;
      }
      (en[a] ??= []).add(item.wordId);
      (th[b] ??= []).add(item.wordId);
    }
    for (final group in [...en.values, ...th.values]) {
      if (group.length > 1) rejected.addAll(group);
    }
    safe.removeWhere((i) => rejected.contains(i.wordId));
    if (source.surface == PairSourceSurface.review &&
        (safe.length != source.selectedCount ||
            (safe.length != 4 && safe.length != 6) ||
            safe.length > density.pairCount)) {
      return const PairPlanUnavailable(PairPlanUnavailableReason.sourceChanged);
    }
    if (source.surface == PairSourceSurface.learn) {
      safe.sort((a, b) {
        final ar = a.sourceReasons
            .map((r) => r.index)
            .reduce((x, y) => x < y ? x : y);
        final br = b.sourceReasons
            .map((r) => r.index)
            .reduce((x, y) => x < y ? x : y);
        final r = ar.compareTo(br);
        return r != 0 ? r : a.canonicalIdentity.compareTo(b.canonicalIdentity);
      });
    }
    if (safe.length < 4) {
      return const PairPlanUnavailable(
        PairPlanUnavailableReason.insufficientSafeContent,
      );
    }
    var resolved = density;
    if (safe.length < density.pairCount) {
      if (!acceptCompactFallback) {
        return const PairPlanNeedsDensityConfirmation();
      }
      resolved = PairDensity.compact4;
    }
    return PairPlanReady(
      PairMatchingPlanV1(
        ownerId: launch.ownerId,
        learningSessionId: pairSessionId(launch.ownerId, launch.operationId),
        entryKind: source.surface,
        sourceSnapshotId: source.reference,
        createdAtUtc: launch.createdAtUtc,
        orderedLexicalItems: safe.take(resolved.pairCount),
        direction: launch.requestedDirection,
        density: resolved,
        shuffleSeed: shuffleSeed,
        timerPreset: launch.timerPreset,
        allowlistVersion: allowlist.version,
      ),
    );
  }
}

bool _samePin(PairLexicalItem a, PairLexicalItem b) =>
    a.wordId == b.wordId &&
    a.contentRevision == b.contentRevision &&
    a.checksum == b.checksum &&
    a.spelling == b.spelling &&
    a.meaning == b.meaning &&
    a.sourceLocale == b.sourceLocale &&
    a.targetLocale == b.targetLocale;

/// Deliberately bounded normalization, not a claim to implement all Unicode.
/// ASCII English plus Latin-1 accents and Thai are supported. Other scripts,
/// format controls and unsupported combining marks fail closed. Decomposition
/// preserves accents and Thai marks; canonical combining order is stable.
String? pairVisibleKey(String value, String locale) {
  var text = value.toLowerCase().trim().replaceAll(RegExp(r' +'), ' ');
  const composed = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const decomposed = [
    'a\u0300',
    'a\u0301',
    'a\u0302',
    'a\u0303',
    'a\u0308',
    'a\u030a',
    'c\u0327',
    'e\u0300',
    'e\u0301',
    'e\u0302',
    'e\u0308',
    'i\u0300',
    'i\u0301',
    'i\u0302',
    'i\u0308',
    'n\u0303',
    'o\u0300',
    'o\u0301',
    'o\u0302',
    'o\u0303',
    'o\u0308',
    'u\u0300',
    'u\u0301',
    'u\u0302',
    'u\u0308',
    'y\u0301',
    'y\u0308',
  ];
  if (locale == 'en') {
    for (var i = 0; i < composed.length; i++) {
      text = text.replaceAll(composed[i], decomposed[i]);
    }
    if (!RegExp(
          r'^[a-z0-9 \-\x27\u0300-\u0303\u0308\u030a\u0327]+$',
        ).hasMatch(text) ||
        !RegExp('[a-z]').hasMatch(text)) {
      return null;
    }
  } else if (locale == 'th') {
    if (!RegExp(r'^[\u0e01-\u0e3a\u0e40-\u0e4e0-9 \-]+$').hasMatch(text) ||
        !RegExp(r'[\u0e01-\u0e2e]').hasMatch(text)) {
      return null;
    }
    // Thai shaping treats SARA AM and NIKHAHIT + SARA AA alike.
    // Fold that bounded visible equivalence and tone/nikhahit order while
    // retaining every tone mark (this is not generic NFKC mark removal).
    text = text
        .replaceAll('\u0e33', '\u0e4d\u0e32')
        .replaceAllMapped(
          RegExp(r'\u0e4d([\u0e48-\u0e4b])'),
          (m) => '${m[1]}\u0e4d',
        );
  } else {
    return null;
  }
  int combining(int r) => r == 0x327
      ? 202
      : [0x300, 0x301, 0x302, 0x303, 0x308, 0x30a].contains(r)
      ? 230
      : r == 0xe38 || r == 0xe39
      ? 103
      : r == 0xe3a
      ? 9
      : r >= 0xe48 && r <= 0xe4b
      ? 107
      : 0;
  final runes = text.runes.toList();
  for (var i = 1; i < runes.length; i++) {
    var j = i;
    final c = combining(runes[j]);
    while (c != 0 && j > 0 && combining(runes[j - 1]) > c) {
      final previous = runes[j - 1];
      runes[j - 1] = runes[j];
      runes[j] = previous;
      j--;
    }
  }
  return String.fromCharCodes(runes);
}
