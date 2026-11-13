import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/data/local/shared_preferences_account_deletion_journal.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_full_account_exporter.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';

const _channel = MethodChannel('com.lexiquest.app/export');
const _key = 'delete:synthetic-full-account-0001';
final _now = DateTime.utc(2026, 11, 14, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.open();
    fixture.installPicker();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    fixture.selection?.completeIfPending(fixture.destination);
    fixture.writeGate?.completeIfPending(null);
    await fixture.database.close();
    final tempRoot = Directory.systemTemp.absolute.path;
    final target = fixture.directory.absolute.path;
    expect(target.startsWith('$tempRoot${Platform.pathSeparator}'), isTrue);
    await fixture.directory.delete(recursive: true);
  });

  test('full account receipt describes the saved owner A JSON bytes', () async {
    final beforeA = (await fixture.snapshot('owner-a')).sha256;
    final beforeB = (await fixture.snapshot('owner-b')).sha256;
    final receipt = await fixture.exporter.export(ownerId: 'owner-a');
    final bytes = await fixture.saved.readAsBytes();
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;

    expect(receipt.ownerId, 'owner-a');
    expect(receipt.artifactId, isNotEmpty);
    expect(receipt.artifactSha256, sha256.convert(bytes).toString());
    expect(receipt.bytesWritten, bytes.length);
    expect(receipt.schemaVersion, fixture.database.schemaVersion);
    expect(receipt.coveredScopes, requiredFullAccountExportScopes);
    expect(receipt.completedAtUtc, _now);
    expect(payload['ownerId'], 'owner-a');
    expect(payload['schemaVersion'], receipt.schemaVersion);
    expect(data.keys.toSet(), requiredFullAccountExportScopes);
    expect((data['vocabulary_words'] as List).single['spelling'], 'private-a');
    expect((data['answer_attempts'] as List).single['id'], 'attempt-a');
    expect((data['reward_transactions'] as List).single['amount'], 7);
    expect(utf8.decode(bytes), isNot(contains('private-b')));
    expect(utf8.decode(bytes), isNot(contains('uid-b')));
    expect(fixture.calls, ['selectExportDestination', 'writeExportFile']);
    expect((await fixture.snapshot('owner-a')).sha256, beforeA);
    expect((await fixture.snapshot('owner-b')).sha256, beforeB);
  });

  test('receipt waits for the actual file save acknowledgement', () async {
    fixture.writeGate = Completer<void>();
    var completed = false;
    final pending = fixture.exporter
        .export(ownerId: 'owner-a')
        .then<Object>(
          (receipt) {
            completed = true;
            return receipt;
          },
          onError: (Object error) {
            completed = true;
            return error;
          },
        );
    await Future.any([fixture.writeStarted.future, pending.then((_) {})]);
    expect(fixture.calls, ['selectExportDestination', 'writeExportFile']);
    expect(completed, isFalse);
    expect(await fixture.saved.exists(), isFalse);
    fixture.writeGate!.complete();
    expect(await pending, isA<FullAccountExportReceipt>());
    expect(await fixture.saved.exists(), isTrue);
  });

  test('inactive B cannot export while A is active', () async {
    await expectLater(
      fixture.exporter.export(ownerId: 'owner-b'),
      throwsA(_failure(AccountDeletionFailureCode.ownerChanged)),
    );
    expect(fixture.calls, isEmpty);
    expect(await fixture.saved.exists(), isFalse);
  });

  test(
    'owner change in an open picker discards A before sending bytes',
    () async {
      fixture.selection = Completer<Map<String, String>?>();
      final pending = _outcome(fixture.exporter.export(ownerId: 'owner-a'));
      await Future.any([fixture.pickerStarted.future, pending.then((_) {})]);
      expect(fixture.calls, ['selectExportDestination']);
      await fixture.activateB();
      final beforeA = (await fixture.snapshot('owner-a')).sha256;
      final beforeB = (await fixture.snapshot('owner-b')).sha256;
      fixture.selection!.complete(fixture.destination);

      expect(await pending, isA<AccountDeletionException>());
      expect(fixture.calls, [
        'selectExportDestination',
        'discardExportDestination',
      ]);
      expect(await fixture.saved.exists(), isFalse);
      expect((await fixture.snapshot('owner-a')).sha256, beforeA);
      expect((await fixture.snapshot('owner-b')).sha256, beforeB);
    },
  );

  for (final cancel in [false, true]) {
    test(
      cancel
          ? 'picker cancellation stops before reauthentication and any deletion'
          : 'save failure stops before reauthentication and any deletion',
      () async {
        fixture.cancelPicker = cancel;
        fixture.failWrite = !cancel;
        final beforeA = (await fixture.snapshot('owner-a')).sha256;
        final beforeB = (await fixture.snapshot('owner-b')).sha256;
        final ports = _DeletionPorts(fixture);
        final deletion = await fixture.deletion(ports);

        await expectLater(
          deletion.deleteAccount(idempotencyKey: _key),
          throwsA(_failure(AccountDeletionFailureCode.fullExportFailed)),
        );
        expect(fixture.calls, contains('selectExportDestination'));
        expect(
          fixture.calls.where((call) => call == 'writeExportFile').length,
          cancel ? 0 : 1,
        );
        expect(fixture.order, isEmpty);
        expect(ports.reauthCalls, 0);
        expect(ports.cloudCalls, 0);
        expect(await fixture.saved.exists(), isFalse);
        expect((await fixture.snapshot('owner-a')).sha256, beforeA);
        expect((await fixture.snapshot('owner-b')).sha256, beforeB);
      },
    );
  }

  test(
    'saved export precedes deletion and B survives a real SQLite reopen',
    () async {
      final beforeB = (await fixture.snapshot('owner-b')).sha256;
      final ports = _DeletionPorts(fixture);
      final deletion = await fixture.deletion(ports);
      final receipt = await deletion.deleteAccount(idempotencyKey: _key);

      expect(fixture.order, ['saved', 'reauth', 'cloud', 'local']);
      expect(
        receipt.exportReceipt.artifactSha256,
        sha256.convert(await fixture.saved.readAsBytes()).toString(),
      );
      expect(receipt.localReceipt.deletedOwnerId, 'owner-a');
      expect(ports.reauthCalls, 1);
      expect(ports.cloudCalls, 1);
      expect((await fixture.snapshot('owner-a')).recordCount, 0);
      expect((await fixture.snapshot('owner-b')).sha256, beforeB);

      await fixture.reopen();
      expect((await fixture.snapshot('owner-a')).recordCount, 0);
      expect((await fixture.snapshot('owner-b')).sha256, beforeB);
      final owner = await fixture.owners.getOrCreateActiveOwner();
      expect(owner.id, receipt.localReceipt.newGuestOwnerId);
      expect(owner.firebaseUid, isNull);
      expect(await fixture.saved.exists(), isTrue);
    },
  );

  test(
    'ordinary prepare and export cannot claim full account JSON coverage',
    () async {
      final reader = _UnusedReader();
      final exports = ExportUseCases(
        owners: fixture.owners,
        reader: reader,
        store: const FileSelectorExportStore(isAndroid: true),
        nowUtc: () => _now,
        loadThaiFont: () => throw StateError('must not load a font'),
        researchConsent: ResearchConsentUseCases(
          owners: fixture.owners,
          repository: DriftResearchConsentRepository(fixture.database),
          nowUtc: () => _now,
        ),
      );
      const selection = ExportSelection(
        includeVocabulary: true,
        includeAttempts: true,
        includeReading: true,
        includeRewards: true,
      );
      for (final operation in [
        () => exports.prepare(
          format: ExportFormat.fullAccountJson,
          selection: selection,
          cancellation: ExportCancellation(),
        ),
        () => exports.export(
          format: ExportFormat.fullAccountJson,
          selection: selection,
          cancellation: ExportCancellation(),
        ),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<ExportException>().having(
              (error) => error.code,
              'code',
              ExportFailureCode.unavailable,
            ),
          ),
        );
      }
      expect(reader.calls, 0);
      expect(fixture.calls, isEmpty);
    },
  );
}

Matcher _failure(AccountDeletionFailureCode code) =>
    isA<AccountDeletionException>().having((error) => error.code, 'code', code);

Future<Object> _outcome(Future<Object> pending) =>
    pending.then<Object>((value) => value, onError: (Object error) => error);

extension<T> on Completer<T> {
  void completeIfPending([FutureOr<T>? value]) {
    if (!isCompleted) complete(value);
  }
}

final class _Fixture {
  _Fixture(this.directory)
    : database = AppDatabase(
        NativeDatabase(File('${directory.path}/account.sqlite')),
      );

  final Directory directory;
  AppDatabase database;
  late DriftLocalOwnerRepository owners = _owners();
  final calls = <String>[];
  final order = <String>[];
  final pickerStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Completer<Map<String, String>?>? selection;
  Completer<void>? writeGate;
  bool cancelPicker = false;
  bool failWrite = false;

  File get saved => File('${directory.path}/full-account.json');
  Map<String, String> get destination => {
    'destination': 'content://synthetic/full-account.json',
    'selectionToken': 'synthetic-selection-1',
  };
  DriftFullAccountExporter get exporter => DriftFullAccountExporter(
    owners: owners,
    snapshots: DriftAccountSnapshotBuilder(database, nowUtc: () => _now),
    store: const FileSelectorExportStore(isAndroid: true),
    nowUtc: () => _now,
  );

  static Future<_Fixture> open() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('lexiquest-full-export-'),
    );
    await fixture.database.customStatement('PRAGMA foreign_keys = ON');
    await _seed(fixture.database);
    return fixture;
  }

  DriftLocalOwnerRepository _owners() => DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic-unexpected-guest',
    nowUtc: () => _now,
  );

  Future<LocalAccountSnapshot> snapshot(String ownerId) =>
      DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => _now,
      ).build(ownerId: ownerId);

  void installPicker() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          if (call.method == 'selectExportDestination') {
            pickerStarted.completeIfPending();
            final args = call.arguments as Map<Object?, Object?>;
            expect(args['mimeType'], 'application/json');
            expect(args['suggestedName'], endsWith('.json'));
            expect(args.containsKey('bytes'), isFalse);
            if (cancelPicker) return null;
            return selection == null ? destination : await selection!.future;
          }
          if (call.method == 'writeExportFile') {
            writeStarted.completeIfPending();
            if (failWrite) throw PlatformException(code: 'WRITE_FAILED');
            if (writeGate != null) await writeGate!.future;
            final args = call.arguments as Map<Object?, Object?>;
            expect(args['selectionToken'], destination['selectionToken']);
            await saved.writeAsBytes(args['bytes'] as Uint8List, flush: true);
            order.add('saved');
            return null;
          }
          if (call.method == 'discardExportDestination') return null;
          fail('Unexpected export platform method ${call.method}');
        });
  }

  Future<void> activateB() => database.transaction(() async {
    await database.customStatement('UPDATE local_owners SET is_active = 0');
    await database.customStatement(
      "UPDATE local_owners SET is_active = 1 WHERE id = 'owner-b'",
    );
  });

  Future<void> reopen() async {
    await database.close();
    database = AppDatabase(
      NativeDatabase(File('${directory.path}/account.sqlite')),
    );
    await database.customStatement('PRAGMA foreign_keys = ON');
    owners = _owners();
  }

  Future<AccountDeletionUseCases> deletion(_DeletionPorts ports) async {
    SharedPreferences.setMockInitialValues({});
    return AccountDeletionUseCases(
      enabled: true,
      owners: owners,
      currentSession: () => const AccountSession(
        uid: 'uid-a',
        email: 'synthetic-a@example.test',
        isAnonymous: false,
        emailVerified: true,
      ),
      exporter: exporter,
      reauthenticator: ports,
      cloud: ports,
      local: DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          expect(ownerId, 'owner-a');
          expect(firebaseUid, 'uid-a');
          order.add('local');
        },
      ),
      journal: SharedPreferencesAccountDeletionJournal(
        await SharedPreferences.getInstance(),
      ),
      nowUtc: () => _now,
    );
  }
}

final class _DeletionPorts
    implements
        AccountDeletionReauthenticator,
        PrivilegedAccountDeletionGateway {
  _DeletionPorts(this.fixture);
  final _Fixture fixture;
  var reauthCalls = 0;
  var cloudCalls = 0;

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) async {
    reauthCalls++;
    expect(await fixture.saved.exists(), isTrue);
    fixture.order.add('reauth');
    return RecentAuthenticationReceipt(
      firebaseUid: firebaseUid,
      authenticatedAtUtc: _now,
    );
  }

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    cloudCalls++;
    expect(
      exportReceipt.artifactSha256,
      sha256.convert(await fixture.saved.readAsBytes()).toString(),
    );
    expect(exportReceipt.coveredScopes, requiredFullAccountExportScopes);
    expect(authenticationReceipt.firebaseUid, firebaseUid);
    fixture.order.add('cloud');
    return CloudDeletionReceipt(
      receiptId: 'synthetic-cloud-receipt',
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      idempotencyKey: idempotencyKey,
      completedAtUtc: _now,
    );
  }
}

final class _UnusedReader extends Fake implements ExportReader {
  var calls = 0;
  @override
  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    bool rewards = false,
  }) async {
    calls++;
    throw StateError('ordinary export must not read a full snapshot');
  }
}

Future<void> _seed(AppDatabase database) async {
  for (final id in ['a', 'b']) {
    await database.customStatement(
      'INSERT INTO local_owners (id, firebase_uid, account_state, is_active, created_at_utc_ms) '
      'VALUES (?, ?, ?, ?, ?)',
      ['owner-$id', 'uid-$id', 'firebaseBound', id == 'a' ? 1 : 0, 1],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      ['category-$id', 'owner-$id', 'ชุดส่วนตัว $id', 'private $id'],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, '
      'meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, 'noun', 1, 1)",
      [
        'word-$id',
        'owner-$id',
        'category-$id',
        'private-$id',
        'private-$id',
        'คำศัพท์ $id',
        'คำศัพท์ $id',
      ],
    );
    await database.customStatement(
      'INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) '
      "VALUES (?, ?, 'quiz', 'completed', 1, 'synthetic', 'full-export-test')",
      ['session-$id', 'owner-$id'],
    );
    await database.customStatement(
      'INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, attempt_number, occurred_at_utc_ms) '
      "VALUES (?, ?, ?, ?, 'meaning', 1, 1, 1)",
      ['attempt-$id', 'owner-$id', 'session-$id', 'word-$id'],
    );
    await database.customStatement(
      'INSERT INTO reward_transactions (id, owner_id, idempotency_key, transaction_type, amount, catalog_version, occurred_at_utc_ms) '
      "VALUES (?, ?, ?, 'earn', 7, 1, 1)",
      ['reward-$id', 'owner-$id', 'synthetic-reward-$id'],
    );
  }
}
