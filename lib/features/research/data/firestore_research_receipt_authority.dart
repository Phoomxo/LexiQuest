import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/local/app_database.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/research_participation_permit.dart';

/// Explicit I/O trust boundary. Alternate readers must attest server freshness;
/// normal application composition should use the SDK factory below.
typedef ResearchReceiptReader =
    Future<ResearchReceiptDocument> Function({
      required String firebaseUid,
      required String receiptId,
    });

final class ResearchReceiptDocument {
  ResearchReceiptDocument({
    required this.documentPath,
    required this.exists,
    required this.isFromCache,
    required this.hasPendingWrites,
    required Map<String, Object?>? data,
  }) : data = data == null ? null : Map.unmodifiable(data);

  final String documentPath;
  final bool exists;
  final bool isFromCache;
  final bool hasPendingWrites;
  final Map<String, Object?>? data;
}

/// Read-only receipt checks against current server data and local consent.
///
/// Does not create/refresh receipts, grant consent, or enable research. Compose
/// with the runtime's existing database; ownership remains with the caller.
/// Permit signature/protocol/revocation checks remain the permit validator's job.
final class FirestoreResearchReceiptAuthority
    implements ResearchReceiptAuthority {
  factory FirestoreResearchReceiptAuthority({
    required AppDatabase database,
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required int consentVersion,
    required DateTime Function() nowUtc,
    Duration readTimeout = const Duration(seconds: 5),
  }) => FirestoreResearchReceiptAuthority.withReader(
    database: database,
    currentFirebaseUid: () => auth.currentUser?.uid,
    readReceipt: ({required firebaseUid, required receiptId}) async {
      final document = await firestore
          .doc(_receiptPath(firebaseUid, receiptId))
          .get(const GetOptions(source: Source.server));
      // Source.server can still contain latency-compensated local writes.
      return ResearchReceiptDocument(
        documentPath: document.reference.path,
        exists: document.exists,
        isFromCache: document.metadata.isFromCache,
        hasPendingWrites: document.metadata.hasPendingWrites,
        data: document.data(),
      );
    },
    consentVersion: consentVersion,
    nowUtc: nowUtc,
    readTimeout: readTimeout,
  );

  factory FirestoreResearchReceiptAuthority.withReader({
    required AppDatabase database,
    required String? Function() currentFirebaseUid,
    required ResearchReceiptReader readReceipt,
    required int consentVersion,
    required DateTime Function() nowUtc,
    Duration readTimeout = const Duration(seconds: 5),
  }) {
    if (consentVersion <= 0 || consentVersion > 2147483647) {
      throw ArgumentError('Invalid configured consent version');
    }
    if (readTimeout <= Duration.zero ||
        readTimeout > const Duration(seconds: 10)) {
      throw ArgumentError('Receipt timeout must be positive and at most 10s');
    }
    return FirestoreResearchReceiptAuthority._(
      database,
      currentFirebaseUid,
      readReceipt,
      consentVersion,
      nowUtc,
      readTimeout,
    );
  }

  FirestoreResearchReceiptAuthority._(
    this._database,
    this._currentFirebaseUid,
    this._readReceipt,
    this._consentVersion,
    this._nowUtc,
    this._readTimeout,
  );

  final AppDatabase _database;
  final String? Function() _currentFirebaseUid;
  final ResearchReceiptReader _readReceipt;
  final int _consentVersion;
  final DateTime Function() _nowUtc;
  final Duration _readTimeout;

  static final _code = RegExp(r'^[A-Za-z0-9_.:\-]{1,128}$');
  static const _coreFields = {'kind', 'ownerId', 'active', 'expiresAtUtcMs'};
  static const _consentFields = {
    ..._coreFields,
    'consentVersion',
    'decidedAtUtcMs',
  };

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    var timedOut = false;
    try {
      return await _check(
        ownerId: ownerId,
        receiptId: receiptId,
        kind: kind,
        evaluatedAtUtc: evaluatedAtUtc,
        timedOut: () => timedOut,
      ).timeout(
        _readTimeout,
        onTimeout: () {
          timedOut = true;
          return false;
        },
      );
    } on Object {
      // No document contents, IDs, auth state, or SDK errors are logged.
      return false;
    }
  }

  Future<bool> _check({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
    required bool Function() timedOut,
  }) async {
    final started = _nowUtc();
    final uid = _currentFirebaseUid();
    if (!_validUtc(started) ||
        !_validUtc(evaluatedAtUtc) ||
        evaluatedAtUtc.isAfter(started) ||
        !_validCode(ownerId) ||
        !_validCode(receiptId) ||
        !_safeUid(uid)) {
      return false;
    }

    final before = await _binding(ownerId, uid!, evaluatedAtUtc);
    if (timedOut() || before == null || _currentFirebaseUid() != uid) {
      return false;
    }
    final document = await _readReceipt(firebaseUid: uid, receiptId: receiptId);
    // An SDK read cannot be cancelled by Future.timeout. Do not continue local
    // checks (or start another read) if its result arrives after our deadline.
    if (timedOut() ||
        _currentFirebaseUid() != uid ||
        document.documentPath != _receiptPath(uid, receiptId) ||
        !document.exists ||
        document.isFromCache ||
        document.hasPendingWrites) {
      return false;
    }
    final data = document.data;
    final fields = kind == ResearchReceiptKind.consent
        ? _consentFields
        : _coreFields;
    if (data == null ||
        data.length != fields.length ||
        !data.keys.every(fields.contains) ||
        data['kind'] != kind.name ||
        data['ownerId'] != ownerId ||
        data['active'] != true ||
        !_epoch(data['expiresAtUtcMs'])) {
      return false;
    }
    if (kind == ResearchReceiptKind.consent &&
        (data['consentVersion'] is! int ||
            data['consentVersion'] != _consentVersion ||
            data['decidedAtUtcMs'] is! int ||
            data['decidedAtUtcMs'] != before['decided_at_utc_ms'])) {
      return false;
    }

    final after = await _binding(ownerId, uid, evaluatedAtUtc);
    final finished = _nowUtc();
    return !timedOut() &&
        after != null &&
        _currentFirebaseUid() == uid &&
        before.length == after.length &&
        before.keys.every((key) => before[key] == after[key]) &&
        _validUtc(finished) &&
        !finished.isBefore(started) &&
        (data['expiresAtUtcMs']! as int) > finished.millisecondsSinceEpoch;
  }

  Future<Map<String, Object?>?> _binding(
    String ownerId,
    String uid,
    DateTime evaluatedAtUtc,
  ) async {
    if (_currentFirebaseUid() != uid) return null;
    // A single bounded statement snapshots identity and consent consistently.
    // Never keep a database transaction/owner lock across external authority I/O.
    final rows = await _database
        .customSelect(
          '''
      SELECT o.id AS owner_id, o.firebase_uid, o.account_state,
             o.created_at_utc_ms, o.upgraded_at_utc_ms,
             c.id AS consent_id, c.consent_version, c.consent_state,
             c.decided_at_utc_ms, c.withdrawn_at_utc_ms
      FROM local_owners o
      LEFT JOIN research_consents c
        ON c.owner_id = o.id AND c.consent_version = ?
      WHERE o.is_active = 1 ORDER BY o.id LIMIT 2
    ''',
          variables: [Variable.withInt(_consentVersion)],
        )
        .get();
    if (_currentFirebaseUid() != uid || rows.length != 1) return null;
    final row = rows.single.data;
    if (row['owner_id'] != ownerId ||
        row['firebase_uid'] != uid ||
        row['consent_version'] != _consentVersion ||
        row['consent_state'] != 'accepted' ||
        row['withdrawn_at_utc_ms'] != null ||
        !_epoch(row['decided_at_utc_ms']) ||
        (row['decided_at_utc_ms']! as int) >
            evaluatedAtUtc.millisecondsSinceEpoch) {
      return null;
    }
    return row;
  }

  static String _receiptPath(String uid, String receiptId) =>
      'field_users/$uid/research_receipts/$receiptId';

  static bool _validCode(String value) =>
      value != '.' &&
      value != '..' &&
      _code.hasMatch(value) &&
      value == value.trim();

  static bool _safeUid(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.length <= 128 &&
      value == value.trim() &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.runes.any((r) => r < 0x20 || r == 0x7f);

  static bool _epoch(Object? value) =>
      value is int && value >= 0 && value <= 8640000000000000;

  static bool _validUtc(DateTime value) =>
      value.isUtc && value.microsecondsSinceEpoch >= 0;
}
