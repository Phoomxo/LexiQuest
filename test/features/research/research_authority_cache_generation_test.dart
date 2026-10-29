import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/research_authority_cache_harness.dart';

void main() {
  test(
    'verified consent decision identity remains exact until invalidated',
    () async {
      final fixture = await AuthorityCacheFixture.open();
      addTearDown(fixture.close);
      expect(await fixture.cache.refresh(), isTrue);
      final dynamic cache = fixture.cache;
      final decision = participationStart.subtract(const Duration(hours: 1));
      dynamic receipt() => cache.inspectReceipt(
        ownerId: 'owner-a',
        receiptId: 'synthetic-consent-receipt',
        kind: ResearchReceiptKind.consent,
      );
      expect(receipt().decidedAtUtc, decision);
      expect(receipt().consentVersion, 4);
      expect(
        receipt().expiresAtUtc,
        participationStart.add(const Duration(hours: 1)),
      );
      await fixture.study.database.customStatement(
        "UPDATE research_consents SET decided_at_utc_ms = decided_at_utc_ms + 1 WHERE owner_id = 'owner-a'",
      );
      // The caller must compare this verified identity to its current SQL row.
      expect(receipt().decidedAtUtc, decision);
      fixture.cache.invalidate();
      expect(receipt(), isNull);
    },
  );

  test(
    'receipt metadata fails closed for another owner, missing refs and expired memory',
    () async {
      final fixture = await AuthorityCacheFixture.open();
      addTearDown(fixture.close);
      expect(await fixture.cache.refresh(), isTrue);
      final dynamic cache = fixture.cache;
      dynamic receipt(String owner, String id, ResearchReceiptKind kind) =>
          cache.inspectReceipt(ownerId: owner, receiptId: id, kind: kind);
      expect(
        receipt(
          'owner-b',
          'synthetic-consent-receipt',
          ResearchReceiptKind.consent,
        ),
        isNull,
      );
      expect(
        receipt('owner-a', 'missing', ResearchReceiptKind.consent),
        isNull,
      );
      expect(
        receipt(
          'owner-a',
          'synthetic-consent-receipt',
          ResearchReceiptKind.guardianPermission,
        ),
        isNull,
      );
      expect(
        receipt(
          'owner-a',
          'synthetic-consent-receipt',
          ResearchReceiptKind.consent,
        ),
        isNotNull,
      );
      fixture.advance(const Duration(minutes: 11));
      expect(
        receipt(
          'owner-a',
          'synthetic-consent-receipt',
          ResearchReceiptKind.consent,
        ),
        isNull,
      );
    },
  );

  test(
    'read generation fences every refresh and lifecycle invalidation',
    () async {
      final fixture = await AuthorityCacheFixture.open();
      addTearDown(fixture.close);
      final dynamic cache = fixture.cache;
      int generation() => cache.readGeneration as int;

      var previous = generation();
      expect(await fixture.cache.refresh(), isTrue);
      expect(generation(), greaterThan(previous));
      previous = generation();
      expect(await fixture.cache.read(), isNotNull);
      expect(generation(), previous);

      fixture.gateway.fail = true;
      expect(await fixture.cache.refresh(), isFalse);
      expect(generation(), greaterThan(previous));
      previous = generation();
      expect(await fixture.cache.read(), isNull);

      fixture.cache.invalidate();
      expect(generation(), greaterThan(previous));
      previous = generation();
      fixture.cache.suspend();
      expect(generation(), greaterThan(previous));
      previous = generation();
      fixture.cache.resume();
      expect(generation(), greaterThan(previous));
      previous = generation();
      fixture.cache.dispose();
      expect(generation(), greaterThan(previous));
    },
  );
}
