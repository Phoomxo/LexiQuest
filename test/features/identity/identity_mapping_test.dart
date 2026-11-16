import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/identity_mapping.dart';

void main() {
  group('IdentityMapping — D3.3', () {
    test('guest identity has no Firebase UID', () {
      final guest = IdentityMapping.guest(
        localOwnerId: 'guest-123',
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      expect(guest.firebaseUid, isNull);
      expect(guest.state, IdentityState.guest);
      expect(guest.isAuthenticated, isFalse);
    });

    test('research pseudonym is separate from authentication IDs', () {
      final identity = IdentityMapping(
        localOwnerId: 'local-001',
        firebaseUid: 'fb-uid-001',
        learnerId: 'learner-001',
        researchPseudonym: 'pseudo-xyz',
        createdAtUtc: DateTime(2026, 1, 1),
        state: IdentityState.verified,
      );
      expect(identity.researchPseudonym, isNot(identity.firebaseUid));
      expect(identity.researchPseudonym, isNot(identity.learnerId));
      expect(identity.researchPseudonym, isNot(identity.localOwnerId));
    });

    test('identity can have multiple tenant memberships', () {
      final identity = IdentityMapping(
        localOwnerId: 'local-002',
        tenantMemberships: [
          TenantMembership(
            tenantId: 'school-1',
            role: 'student',
            joinedAtUtc: DateTime.utc(2026, 1, 1),
          ),
          TenantMembership(
            tenantId: 'school-2',
            role: 'student',
            joinedAtUtc: DateTime.utc(2026, 3, 1),
          ),
        ],
        createdAtUtc: DateTime.utc(2026, 1, 1),
        state: IdentityState.verified,
      );
      expect(identity.tenantMemberships.length, 2);
    });

    test('registered identity has Firebase UID and isAuthenticated = true', () {
      final identity = IdentityMapping(
        localOwnerId: 'local-003',
        firebaseUid: 'fb-uid-003',
        createdAtUtc: DateTime(2026, 2, 1),
        state: IdentityState.registered,
      );
      expect(identity.isAuthenticated, isTrue);
    });

    test('defaultConsentContext returns ConsentContext.none for guest', () {
      final guest = IdentityMapping.guest(
        localOwnerId: 'g',
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      final ctx = guest.defaultConsentContext();
      expect(ctx.researchConsentVersion, 0);
      expect(ctx.aiConsentGranted, isFalse);
    });

    test('tenantMemberships defaults to empty list', () {
      final guest = IdentityMapping.guest(
        localOwnerId: 'x',
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      expect(guest.tenantMemberships, isEmpty);
    });

    test('all IdentityState values are representable', () {
      for (final state in IdentityState.values) {
        final id = IdentityMapping(
          localOwnerId: 'test',
          createdAtUtc: DateTime.utc(2026, 1, 1),
          state: state,
        );
        expect(id.state, state);
      }
    });
  });
}
