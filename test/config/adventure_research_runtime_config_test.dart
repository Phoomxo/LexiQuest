import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/adventure_research_runtime_config.dart';
import '../support/motivation_research_fixture.dart';

void main() {
  test(
    'configured authority is exactly one explicit instance or deferred database factory',
    () async {
      final f = MotivationResearchFixture();
      addTearDown(f.database.close);
      final keys = {'synthetic': '04${'0' * 128}'};
      expect(
        () => AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: keys,
        ),
        throwsFormatException,
      );
      expect(
        () => AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: keys,
          receipts: f.authority,
          createReceipts: (_) => f.authority,
        ),
        throwsFormatException,
      );
      var calls = 0;
      final config = AdventureResearchRuntimeConfig.configured(
        study: f.study,
        issuerPublicKeys: keys,
        createReceipts: (_) {
          calls++;
          return f.authority;
        },
      );
      expect(config.enabled, isTrue);
      expect(config.receipts, isNull);
      expect(calls, 0);
    },
  );
  test('research ships without an instrument, issuer or receipt authority', () {
    const c = AdventureResearchRuntimeConfig.off();
    expect(c.enabled, isFalse);
    expect(c.study, isNull);
    expect(c.receipts, isNull);
    expect(c.issuerPublicKeys, isEmpty);
  });
  test(
    'configured research requires explicit issuer and freezes caller keys',
    () async {
      final f = MotivationResearchFixture();
      addTearDown(f.database.close);
      expect(
        () => AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: {},
          receipts: f.authority,
        ),
        throwsFormatException,
      );
      final keys = {'synthetic': '04${'0' * 128}'};
      final c = AdventureResearchRuntimeConfig.configured(
        study: f.study,
        issuerPublicKeys: keys,
        receipts: f.authority,
      );
      keys.clear();
      expect(c.issuerPublicKeys, hasLength(1));
      expect(() => c.issuerPublicKeys.clear(), throwsUnsupportedError);
    },
  );
}
