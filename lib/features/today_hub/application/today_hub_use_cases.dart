import '../domain/today_hub_models.dart';

typedef TodayHubActiveOwnerId = Future<String> Function();
typedef TodayHubUtcNow = DateTime Function();

abstract interface class TodayHubSnapshotLoader {
  Future<TodayHubSnapshot> load();
}

/// Read-only application boundary for the canonical Today Hub composition.
final class TodayHubUseCases implements TodayHubSnapshotLoader {
  TodayHubUseCases({
    required this._activeOwnerId,
    required this._reader,
    required this._nowUtc,
    required this._timezoneId,
  });

  final TodayHubActiveOwnerId _activeOwnerId;
  final TodayHubReader _reader;
  final TodayHubUtcNow _nowUtc;
  final String _timezoneId;

  @override
  Future<TodayHubSnapshot> load() async {
    final ownerId = await _activeOwnerId();
    final sampledAtUtc = _nowUtc();
    final evaluatedAtUtc = DateTime.fromMillisecondsSinceEpoch(
      sampledAtUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
    return _reader.compose(
      TodayHubRequest(
        ownerId: ownerId,
        evaluatedAtUtc: evaluatedAtUtc,
        timezoneId: _timezoneId,
      ),
    );
  }
}
