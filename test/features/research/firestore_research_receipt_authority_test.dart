import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/research/data/firestore_research_receipt_authority.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

// Synthetic IDs/documents only. Fakes isolate the SDK, never DB authorization.
void main() {
  late AppDatabase db;
  late DateTime now;
  late String? uid;
  late int reads;
  late Map<String, Object?> data;
  late ResearchReceiptKind kind;
  late Future<void> Function()? duringRead;
  const owner = 'owner:synthetic';
  const receipt = 'receipt:synthetic';
  const firebaseUid = 'synthetic-uid';
  const path = 'field_users/$firebaseUid/research_receipts/$receipt';
  final decision = DateTime.utc(2026, 9, 5, 10).millisecondsSinceEpoch;

  Map<String, Object?> valid(ResearchReceiptKind k) => {
    'kind': k.name,
    'ownerId': owner,
    'active': true,
    'expiresAtUtcMs': DateTime.utc(2026, 9, 6).millisecondsSinceEpoch,
    if (k == ResearchReceiptKind.consent) ...{
      'consentVersion': 3,
      'decidedAtUtcMs': decision,
    },
  };

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 9, 5, 12);
    uid = firebaseUid;
    reads = 0;
    kind = ResearchReceiptKind.consent;
    data = valid(kind);
    duringRead = null;
    await db
        .into(db.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: owner,
            firebaseUid: const Value(firebaseUid),
            accountState: const Value('signedIn'),
            createdAtUtcMs: 0,
          ),
        );
    await db
        .into(db.researchConsents)
        .insert(
          ResearchConsentsCompanion.insert(
            id: 'consent:synthetic',
            ownerId: owner,
            consentVersion: 3,
            consentState: 'accepted',
            decidedAtUtcMs: decision,
          ),
        );
  });
  tearDown(() => db.close());

  FirestoreResearchReceiptAuthority authority({
    bool exists = true,
    bool cached = false,
    bool pending = false,
    String documentPath = path,
    Duration timeout = const Duration(seconds: 5),
    ResearchReceiptReader? reader,
    int version = 3,
  }) => FirestoreResearchReceiptAuthority.withReader(
    database: db,
    consentVersion: version,
    nowUtc: () => now,
    currentFirebaseUid: () => uid,
    readTimeout: timeout,
    readReceipt:
        reader ??
        ({required firebaseUid, required receiptId}) async {
          reads++;
          expect(firebaseUid, uid);
          expect(receiptId, receipt);
          await duringRead?.call();
          return ResearchReceiptDocument(
            documentPath: documentPath,
            exists: exists,
            isFromCache: cached,
            hasPendingWrites: pending,
            data: data,
          );
        },
  );

  Future<bool> check([FirestoreResearchReceiptAuthority? a]) =>
      (a ?? authority()).isActive(
        ownerId: owner,
        receiptId: receipt,
        kind: kind,
        evaluatedAtUtc: now,
      );

  for (final k in ResearchReceiptKind.values) {
    test(
      'server ${k.name} accepts exactly ${k == ResearchReceiptKind.consent ? 6 : 4} fields',
      () async {
        kind = k;
        data = valid(k);
        expect(await check(), isTrue);
        expect(reads, 1);
        expect((await db.select(db.outboxOperations).get()), isEmpty);
        expect(
          (await db.select(db.researchConsents).getSingle()).decidedAtUtcMs,
          decision,
        );
      },
    );
  }

  final invalidFields = <String, Map<String, Object?>>{
    'owner mismatch': {'ownerId': 'owner:other'},
    'kind mismatch': {'kind': 'guardianPermission'},
    'inactive': {'active': false},
    'numeric active': {'active': 1},
    'string expiry': {'expiresAtUtcMs': '1790000000000'},
    'fractional expiry': {'expiresAtUtcMs': 1790000000000.0},
    'negative expiry': {'expiresAtUtcMs': -1},
    'out of range expiry': {'expiresAtUtcMs': 8640000000000001},
    'wrong consent version': {'consentVersion': 2},
    'string consent version': {'consentVersion': '3'},
    'stale consent decision': {'decidedAtUtcMs': decision - 1},
    'extra authority field': {'issuer': 'client'},
  };
  for (final entry in invalidFields.entries) {
    test('denies ${entry.key}', () async {
      data.addAll(entry.value);
      expect(await check(), isFalse);
    });
  }
  for (final key in valid(ResearchReceiptKind.consent).keys) {
    test('denies missing $key', () async {
      data.remove(key);
      expect(await check(), isFalse);
    });
  }
  for (final k in [
    ResearchReceiptKind.guardianPermission,
    ResearchReceiptKind.learnerAssent,
  ]) {
    test('${k.name} rejects consent-only extra pins', () async {
      kind = k;
      data = {...valid(k), 'consentVersion': 3, 'decidedAtUtcMs': decision};
      expect(await check(), isFalse);
    });
  }
  test(
    'missing document denies',
    () async => expect(await check(authority(exists: false)), isFalse),
  );
  test(
    'cached document denies',
    () async => expect(await check(authority(cached: true)), isFalse),
  );
  test(
    'pending SDK writes deny',
    () async => expect(await check(authority(pending: true)), isFalse),
  );
  test(
    'different returned document path denies',
    () async =>
        expect(await check(authority(documentPath: '$path-other')), isFalse),
  );
  test('null document data denies', () async {
    expect(
      await check(
        authority(
          reader: ({required firebaseUid, required receiptId}) async =>
              ResearchReceiptDocument(
                documentPath: path,
                exists: true,
                isFromCache: false,
                hasPendingWrites: false,
                data: null,
              ),
        ),
      ),
      isFalse,
    );
  });
  test('unavailable server denies without propagating error', () async {
    duringRead = () async => throw StateError('synthetic unavailable');
    expect(await check(), isFalse);
  });

  final localChanges = <String, String>{
    'inactive owner': 'UPDATE local_owners SET is_active = 0',
    'owner binding changed':
        "UPDATE local_owners SET firebase_uid = 'other-uid'",
    'missing owner binding': 'UPDATE local_owners SET firebase_uid = NULL',
    'declined consent':
        "UPDATE research_consents SET consent_state = 'declined'",
    'withdrawn consent':
        'UPDATE research_consents SET withdrawn_at_utc_ms = $decision',
    'wrong local version': 'UPDATE research_consents SET consent_version = 2',
    'future local decision':
        'UPDATE research_consents SET decided_at_utc_ms = ${DateTime.utc(2026, 9, 7).millisecondsSinceEpoch}',
    'missing consent': 'DELETE FROM research_consents',
  };
  for (final entry in localChanges.entries) {
    test('${entry.key} prevents network read', () async {
      await db.customUpdate(entry.value);
      expect(await check(), isFalse);
      expect(reads, 0);
    });
    test('${entry.key} during await denies previously valid receipt', () async {
      duringRead = () => db.customUpdate(entry.value).then((_) {});
      expect(await check(), isFalse);
    });
  }
  test(
    'decision changed during await denies even matching new remote receipt',
    () async {
      duringRead = () async {
        await db.customUpdate(
          'UPDATE research_consents SET decided_at_utc_ms = ${decision + 1}',
        );
        data['decidedAtUtcMs'] = decision + 1;
      };
      expect(await check(), isFalse);
    },
  );
  test('multiple active owners deny before read', () async {
    await db
        .into(db.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'owner:other', createdAtUtcMs: 0),
        );
    expect(await check(), isFalse);
    expect(reads, 0);
  });
  for (final changedUid in <String?>[null, 'other-uid']) {
    test('auth $changedUid before read denies', () async {
      uid = changedUid;
      expect(await check(), isFalse);
      expect(reads, 0);
    });
    test('auth $changedUid during await denies', () async {
      duringRead = () async {
        uid = changedUid;
      };
      expect(await check(), isFalse);
    });
  }
  test('expiry at exact evaluation millisecond denies', () async {
    data['expiresAtUtcMs'] = now.millisecondsSinceEpoch;
    expect(await check(), isFalse);
  });
  test('expiry crossed during read denies', () async {
    data['expiresAtUtcMs'] = now
        .add(const Duration(milliseconds: 1))
        .millisecondsSinceEpoch;
    duringRead = () async {
      now = now.add(const Duration(milliseconds: 1));
    };
    expect(await check(), isFalse);
  });
  test('clock rollback during read denies', () async {
    duringRead = () async {
      now = now.subtract(const Duration(milliseconds: 1));
    };
    expect(await check(), isFalse);
  });
  test('future evaluation denies before read', () async {
    expect(
      await authority().isActive(
        ownerId: owner,
        receiptId: receipt,
        kind: kind,
        evaluatedAtUtc: now.add(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(reads, 0);
  });
  test('non-UTC evaluation denies before read', () async {
    expect(
      await authority().isActive(
        ownerId: owner,
        receiptId: receipt,
        kind: kind,
        evaluatedAtUtc: now.toLocal(),
      ),
      isFalse,
    );
    expect(reads, 0);
  });
  for (final badId in [
    '',
    '.',
    '..',
    'nested/receipt',
    ' receipt',
    'a\n',
    'x' * 129,
  ]) {
    test(
      'malformed receipt segment ${badId.length} denies before read',
      () async {
        expect(
          await authority().isActive(
            ownerId: owner,
            receiptId: badId,
            kind: kind,
            evaluatedAtUtc: now,
          ),
          isFalse,
        );
        expect(reads, 0);
      },
    );
  }
  test(
    'bounded timeout denies and late server result cannot resurrect',
    () async {
      final pending = Completer<ResearchReceiptDocument>();
      final a = authority(
        timeout: const Duration(milliseconds: 20),
        reader: ({required firebaseUid, required receiptId}) => pending.future,
      );
      final result = await check(a).timeout(const Duration(seconds: 1));
      expect(result, isFalse);
      pending.complete(
        ResearchReceiptDocument(
          documentPath: path,
          exists: true,
          isFromCache: false,
          hasPendingWrites: false,
          data: data,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(result, isFalse);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );
  for (final timeout in [
    Duration.zero,
    const Duration(microseconds: -1),
    const Duration(seconds: 11),
  ]) {
    test('rejects unbounded or invalid timeout $timeout', () {
      expect(() => authority(timeout: timeout), throwsArgumentError);
    });
  }
  test('rejects invalid configured consent version', () {
    expect(() => authority(version: 0), throwsArgumentError);
  });

  test('genuine SDK factory requests exact path with Source.server', () async {
    final sdk = _Firestore(_Snapshot(data, path));
    final a = FirestoreResearchReceiptAuthority(
      database: db,
      firestore: sdk,
      auth: _Auth(() => uid),
      consentVersion: 3,
      nowUtc: () => now,
    );
    expect(await check(a), isTrue);
    expect(sdk.requestedPath, path);
    expect(sdk.reference.options?.source, Source.server);
  });
  for (final cached in [true, false]) {
    test(
      'SDK factory maps ${cached ? 'cache' : 'pending-write'} metadata to denial',
      () async {
        final sdk = _Firestore(
          _Snapshot(data, path, cached: cached, pending: !cached),
        );
        final a = FirestoreResearchReceiptAuthority(
          database: db,
          firestore: sdk,
          auth: _Auth(() => uid),
          consentVersion: 3,
          nowUtc: () => now,
        );
        expect(await check(a), isFalse);
      },
    );
  }
  test('SDK factory reads current auth again after server await', () async {
    final sdk = _Firestore(_Snapshot(data, path));
    sdk.reference.beforeReturn = () {
      uid = null;
    };
    final a = FirestoreResearchReceiptAuthority(
      database: db,
      firestore: sdk,
      auth: _Auth(() => uid),
      consentVersion: 3,
      nowUtc: () => now,
    );
    expect(await check(a), isFalse);
  });
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.uid);
  final String? Function() uid;
  @override
  User? get currentUser => uid() == null ? null : _User(uid()!);
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Firestore extends Fake implements FirebaseFirestore {
  _Firestore(_Snapshot snapshot) : reference = _Reference(snapshot);
  final _Reference reference;
  String? requestedPath;
  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    requestedPath = documentPath;
    return reference;
  }
}

// SDK-only test double verifies the actual factory's get options; no writes.
// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.snapshot);
  final _Snapshot snapshot;
  final _ReadProbe _probe = _ReadProbe();
  GetOptions? get options => _probe.options;
  set beforeReturn(void Function()? callback) => _probe.beforeReturn = callback;
  @override
  String get path => snapshot.path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    _probe.options = options;
    _probe.beforeReturn?.call();
    return snapshot;
  }
}

class _ReadProbe {
  GetOptions? options;
  void Function()? beforeReturn;
}

// SDK-only test double exposes server data/metadata to the real factory.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value, this.path, {this.cached = false, this.pending = false});
  final Map<String, Object?> value;
  final String path;
  final bool cached;
  final bool pending;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => value;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _Reference(this);
  @override
  SnapshotMetadata get metadata => _Metadata(cached, pending);
}

class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}
