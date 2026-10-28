import 'package:flutter_test/flutter_test.dart';

import 'device-profile-timings-capture.dart';

void main() {
  test('capture preserves original report map values and removal identity', () {
    final capture = ProfileTimingsCapture();
    final raw = <String, dynamic>{
      'frame_build_times': <int>[100, 200],
      'frame_rasterizer_times': <int>[300, 150],
    };
    capture['ordinary'] = 17;
    capture['adventureMapListFrameTiming:0'] = raw;
    expect(capture['ordinary'], 17);
    expect(capture.remove('adventureMapListFrameTiming:0'), same(raw));
    expect(capture.containsKey('adventureMapListFrameTiming:0'), isFalse);
    raw['frame_build_times'][0] = 999;
    expect(capture.transitions.single['buildUs'], <int>[100, 200]);
    expect(capture.remove('ordinary'), 17);
  });

  test('only approved bounded timing arrays enter diagnostics', () {
    final capture = ProfileTimingsCapture();
    capture['private'] = <String, dynamic>{'secret': 'synthetic-canary'};
    capture.remove('private');
    capture['adventureMapListFrameTiming:0'] = <String, dynamic>{
      'frame_build_times': <int>[1],
      'frame_rasterizer_times': <int>[2],
      'private': 'synthetic-canary',
    };
    capture.remove('adventureMapListFrameTiming:0');
    expect(capture.transitions.single.keys.toSet(), <String>{
      'transition',
      'showList',
      'buildUs',
      'rasterUs',
    });
    expect(capture.transitions.toString(), isNot(contains('synthetic-canary')));
  });

  test(
    'invalid duplicate and oversized timing reports do not alter removal',
    () {
      final capture = ProfileTimingsCapture();
      final invalid = <String, dynamic>{
        'frame_build_times': List<int>.filled(501, 1),
        'frame_rasterizer_times': List<int>.filled(501, 2),
      };
      capture['adventureMapListFrameTiming:0'] = invalid;
      expect(capture.remove('adventureMapListFrameTiming:0'), same(invalid));
      expect(capture.transitions, isEmpty);
      expect(capture.errors, <String>['invalid-timing-shape']);
      final valid = <String, dynamic>{
        'frame_build_times': <int>[1],
        'frame_rasterizer_times': <int>[2],
      };
      capture['adventureMapListFrameTiming:0'] = valid;
      capture.remove('adventureMapListFrameTiming:0');
      capture['adventureMapListFrameTiming:0'] = valid;
      expect(capture.remove('adventureMapListFrameTiming:0'), same(valid));
      expect(capture.transitions, hasLength(1));
      expect(capture.errors, contains('duplicate-transition'));
    },
  );

  test('rejects noninteger negative mismatched and out of range input', () {
    for (final raw in <Map<String, dynamic>>[
      {
        'frame_build_times': <num>[1.5],
        'frame_rasterizer_times': <int>[2],
      },
      {
        'frame_build_times': <int>[-1],
        'frame_rasterizer_times': <int>[2],
      },
      {
        'frame_build_times': <int>[1],
        'frame_rasterizer_times': <int>[2, 3],
      },
      {'frame_build_times': <int>[], 'frame_rasterizer_times': <int>[]},
    ]) {
      final capture = ProfileTimingsCapture();
      capture['adventureMapListFrameTiming:0'] = raw;
      expect(capture.remove('adventureMapListFrameTiming:0'), same(raw));
      expect(capture.transitions, isEmpty);
      expect(capture.errors, isNotEmpty);
    }
    final capture = ProfileTimingsCapture();
    capture['adventureMapListFrameTiming:20'] = 19;
    expect(capture.remove('adventureMapListFrameTiming:20'), 19);
    expect(capture.transitions, isEmpty);
  });
}
