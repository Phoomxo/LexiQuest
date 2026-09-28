import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/native_stale_fixture.dart';

void main() {
  test('CF run identity is restricted to the fresh isolated package', () {
    expect(runIsolatedStalePackage('cf-synthetic-01'), nativeStalePackage);
    expect(() => runIsolatedStalePackage('ce-synthetic-01'), throwsStateError);
    expect(() => runIsolatedStalePackage('cf-'), throwsStateError);
  });

  test('CF Android sandbox path must belong to the fresh package', () {
    expect(
      nativeStaleSandboxMatches(
        canonical: '/data/user/0/$nativeStalePackage/files',
        runId: 'cf-synthetic-01',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      nativeStaleSandboxMatches(
        canonical: '/data/user/0/com.lexiquest.app.nativeDraftCe/files',
        runId: 'cf-synthetic-01',
        isAndroid: true,
      ),
      isFalse,
    );
  });
}
