import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

// In-process SDK-shaped transaction driver, not a preflight sentinel. The real
// gateway executes every read/write branch; no network or participant data.
void main() {
  for (final loss in [
    'none',
    'consent-after-operation',
    'consent-after-entity',
    'owner-fence-after-entity',
    'firebase-after-entity',
    'firebase-during-final-authority',
    'retry',
  ]) {
    test(
      'actual research transaction revalidates $loss before staging writes',
      () async {
        final auth = _Auth();
        var authorized = true;
        late _Firestore firestore;
        firestore = _Firestore(
          afterRead: (read) async {
            await Future<void>.value();
            if ((loss == 'consent-after-operation' && read == 1) ||
                ({
                      'consent-after-entity',
                      'owner-fence-after-entity',
                    }.contains(loss) &&
                    read == 2)) {
              authorized = false;
            }
            if (loss == 'firebase-after-entity' && read == 2) {
              auth.uid = 'other';
            }
          },
          beforeRetry: loss == 'retry' ? () => authorized = false : null,
        );
        final gateway = FirestoreSyncGateway(
          firestore: firestore,
          auth: auth,
          researchMeasurementRollout:
              const ResearchMeasurementSyncRollout.localEmulatorV1(
                deployedRulesRevision: researchMeasurementV1RulesRevision,
              ),
          researchAuthorizer: (_) async {
            await Future<void>.value();
            if (loss == 'firebase-during-final-authority' &&
                firestore.reads == 2) {
              auth.uid = 'other';
            }
            return authorized;
          },
        );
        final mutation = _mutation();
        if (loss == 'none') {
          expect(await gateway.push(mutation), isA<PushAcknowledged>());
          expect(firestore.committed, hasLength(2));
          expect(firestore.stagedCounts, [2]);
        } else {
          await expectLater(
            gateway.push(mutation),
            throwsA(isA<SyncFailure>()),
          );
          expect(firestore.committed, isEmpty);
          expect(firestore.stagedCounts, loss == 'retry' ? [2, 0] : [0]);
        }
      },
    );
  }

  for (final mode in ['conflict', 'pull']) {
    for (final state in ['server', 'cached', 'pending', 'uid-changed']) {
      test(
        '$mode provenance requires authenticated committed server data: $state',
        () async {
          final auth = _Auth();
          final db = _Firestore(
            afterRead: (_) async {
              if (state == 'uid-changed') auth.uid = 'other';
            },
            cached: state == 'cached',
            pending: state == 'pending',
          );
          final mutation = _mutation();
          final data = FirestoreSyncCodec.encodeEntity(
            mutation,
            serverTimestamp: Timestamp.fromDate(DateTime.utc(2026, 9, 5, 12)),
          );
          db.committed['field_users/uid/motivation_responses/response:a'] =
              data;
          final gateway = FirestoreSyncGateway(
            firestore: db,
            auth: auth,
            researchMeasurementRollout:
                const ResearchMeasurementSyncRollout.localEmulatorV1(
                  deployedRulesRevision: researchMeasurementV1RulesRevision,
                ),
            researchAuthorizer: (_) async => true,
          );
          Future<SyncEntity> read() async => mode == 'conflict'
              ? (await gateway.push(mutation) as PushConflict).cloudEntity
              : (await gateway.pull(
                  firebaseUid: 'uid',
                  collection: mutation.collection,
                  after: null,
                  limit: 10,
                )).changes.single;
          if (state != 'server') {
            await expectLater(read(), throwsA(isA<SyncFailure>()));
          } else {
            final entity = await read();
            expect(entity.serverReadProvenance, isNotNull);
            expect(
              entity.serverReadProvenance!.matchesEntity(
                firebaseUid: 'uid',
                entity: entity,
              ),
              isTrue,
            );
            expect(
              FirestoreSyncCodec.decodeEntity(
                collection: mutation.collection,
                documentId: mutation.entityId,
                data: data,
                expectedFirebaseUid: 'uid',
              ).serverReadProvenance,
              isNull,
            );
          }
          expect(
            db.stagedCounts.every((stagedCount) => stagedCount == 0),
            isTrue,
          );
        },
      );
    }
  }
}

PushMutation _mutation() => PushMutation(
  operationId: 'synthetic-response-operation',
  firebaseUid: 'uid',
  collection: SyncCollection.motivationResponses,
  entityId: 'response:a',
  operationKind: SyncOperationKind.upsert,
  payloadVersion: 1,
  baseRevision: 0,
  localRevision: 1,
  clientUpdatedAtUtc: DateTime.utc(2026, 9, 5, 12),
  ownerGateToken: 'synthetic-gate',
  payload: {
    'id': 'response:a',
    'ownerId': 'owner:a',
    'runId': 'run:a',
    'itemId': 'baseline',
    'itemCatalogVersion': '1',
    'responseCode': 'high',
    'ordinalValue': 100,
    'answeredAtUtcMs': 1788609600000,
    'permitId': 'permit:a',
    'permitPayloadSha256': 'a' * 64,
    'permitRevision': 1,
  },
);

final class _Auth implements FirebaseAuth {
  String uid = 'uid';
  @override
  User get currentUser => _User(uid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Firestore implements FirebaseFirestore {
  _Firestore({
    required this.afterRead,
    this.beforeRetry,
    this.cached = false,
    this.pending = false,
  });
  final bool cached;
  final bool pending;
  final Future<void> Function(int read) afterRead;
  final void Function()? beforeRetry;
  final committed = <String, Map<String, dynamic>>{};
  final stagedCounts = <int>[];
  var reads = 0;
  @override
  Settings get settings =>
      const Settings(host: 'localhost:8080', sslEnabled: false);
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final transaction = _Transaction(this);
      try {
        final result = await handler(transaction);
        if (attempt == 0 && beforeRetry != null) {
          beforeRetry!();
          continue;
        }
        committed.addAll(transaction.pending);
        return result;
      } finally {
        stagedCounts.add(transaction.pending.length);
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK-shaped test double only; never shipped or used as a Firestore extension.
// ignore: subtype_of_sealed_class
final class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Document(db, '$path/$id');
  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => this;
  @override
  Query<Map<String, dynamic>> limit(int limit) => this;
  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    await db.afterRead(++db.reads);
    return _QuerySnapshot(db, path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String child) =>
      _Collection(db, '$path/$child');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(id, db.committed[path], db: db);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _Snapshot<T> implements DocumentSnapshot<T> {
  _Snapshot(this.id, this.value, {required this.db});
  final _Firestore db;
  final T? value;
  @override
  final String id;
  @override
  bool get exists => value != null;
  @override
  T? data() => value;
  @override
  SnapshotMetadata get metadata => _Metadata(db);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Transaction implements Transaction {
  _Transaction(this.db);
  final _Firestore db;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    final value = db.committed[ref.path];
    await db.afterRead(++db.reads);
    return _Snapshot<T>(ref.id, value as T?, db: db);
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    pending[ref.path] = {
      for (final entry in (data as Map<String, dynamic>).entries)
        entry.key: entry.value is FieldValue
            ? Timestamp.fromDate(DateTime.utc(2026, 9, 5, 12))
            : entry.value,
    };
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata(this.db);
  final _Firestore db;
  @override
  bool get isFromCache => db.cached;
  @override
  bool get hasPendingWrites => db.pending;
}

// SDK-shaped read fixtures only.
// ignore: subtype_of_sealed_class
final class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.db, this.path);
  final _Firestore db;
  final String path;
  @override
  SnapshotMetadata get metadata => _Metadata(db);
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [
    for (final e in db.committed.entries)
      if (e.key.startsWith('$path/'))
        _QueryDocument(db, e.key.split('/').last, e.value),
  ];
}

// ignore: subtype_of_sealed_class
final class _QueryDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.db, this.id, this.value);
  final _Firestore db;
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  SnapshotMetadata get metadata => _Metadata(db);
}
