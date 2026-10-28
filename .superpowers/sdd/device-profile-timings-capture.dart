import 'dart:collection';

/// Diagnostic only: observes completed timing reports without changing values
/// consumed by the original benchmark. Never retains arbitrary report fields.
final class ProfileTimingsCapture extends MapBase<String, dynamic> {
  final _values = <String, dynamic>{};
  final transitions = <Map<String, Object>>[];
  final errors = <String>[];
  final _seen = <int>{};
  static final _timingKey = RegExp(r'^adventureMapListFrameTiming:(\d+)$');

  @override
  dynamic operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, dynamic value) => _values[key] = value;

  @override
  Iterable<String> get keys => _values.keys;

  @override
  void clear() => _values.clear();

  @override
  dynamic remove(Object? key) {
    final value = _values.remove(key);
    final match = key is String ? _timingKey.firstMatch(key) : null;
    if (match == null) return value;
    final index = int.tryParse(match[1]!);
    if (index == null || index < 0 || index >= 20) {
      _error('out-of-range-transition');
      return value;
    }
    if (_seen.contains(index)) {
      _error('duplicate-transition');
      return value;
    }
    final build = value is Map ? value['frame_build_times'] : null;
    final raster = value is Map ? value['frame_rasterizer_times'] : null;
    if (!_timings(build) ||
        !_timings(raster) ||
        build.length != raster.length) {
      _error('invalid-timing-shape');
      return value;
    }
    _seen.add(index);
    transitions.add(<String, Object>{
      'transition': index,
      'showList': index.isEven,
      'buildUs': List<int>.unmodifiable((build as List).cast<int>()),
      'rasterUs': List<int>.unmodifiable((raster as List).cast<int>()),
    });
    return value;
  }

  static bool _timings(dynamic values) =>
      values is List &&
      values.isNotEmpty &&
      values.length <= 500 &&
      values.every((dynamic value) => value is int && value >= 0);

  void _error(String code) {
    if (errors.length < 25) errors.add(code);
  }
}
