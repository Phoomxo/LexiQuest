import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

List<File> _dartFiles(String path) =>
    Directory(path)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false)
      ..sort((left, right) => left.path.compareTo(right.path));

Iterable<String> _imports(String source) sync* {
  final pattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
  for (final match in pattern.allMatches(source)) {
    yield match.group(1)!;
  }
}

String _maskDartCommentsAndStrings(String source) {
  final output = StringBuffer();
  var index = 0;

  void maskCharacter(String character) {
    output.write(character == '\n' || character == '\r' ? character : ' ');
  }

  void maskRange(int start, int end) {
    for (var cursor = start; cursor < end; cursor += 1) {
      maskCharacter(source[cursor]);
    }
  }

  while (index < source.length) {
    if (index + 1 < source.length &&
        source[index] == '/' &&
        source[index + 1] == '/') {
      while (index < source.length && source[index] != '\n') {
        maskCharacter(source[index]);
        index += 1;
      }
      continue;
    }
    if (index + 1 < source.length &&
        source[index] == '/' &&
        source[index + 1] == '*') {
      var depth = 1;
      maskRange(index, index + 2);
      index += 2;
      while (index < source.length && depth > 0) {
        if (index + 1 < source.length &&
            source[index] == '/' &&
            source[index + 1] == '*') {
          depth += 1;
          maskRange(index, index + 2);
          index += 2;
        } else if (index + 1 < source.length &&
            source[index] == '*' &&
            source[index + 1] == '/') {
          depth -= 1;
          maskRange(index, index + 2);
          index += 2;
        } else {
          maskCharacter(source[index]);
          index += 1;
        }
      }
      if (depth != 0) {
        throw StateError('Unbalanced Dart block comment.');
      }
      continue;
    }
    if (source[index] == "'" || source[index] == '"') {
      final quote = source[index];
      final isRaw =
          index > 0 &&
          (source[index - 1] == 'r' || source[index - 1] == 'R') &&
          (index < 2 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[index - 2]));
      final triple =
          index + 2 < source.length &&
          source[index + 1] == quote &&
          source[index + 2] == quote;
      final delimiterLength = triple ? 3 : 1;
      maskRange(index, index + delimiterLength);
      index += delimiterLength;
      var closed = false;
      while (index < source.length) {
        if (triple &&
            index + 2 < source.length &&
            source[index] == quote &&
            source[index + 1] == quote &&
            source[index + 2] == quote) {
          maskRange(index, index + 3);
          index += 3;
          closed = true;
          break;
        }
        if (!triple && source[index] == quote) {
          maskCharacter(source[index]);
          index += 1;
          closed = true;
          break;
        }
        if (!isRaw && source[index] == '\\' && index + 1 < source.length) {
          maskRange(index, index + 2);
          index += 2;
          continue;
        }
        maskCharacter(source[index]);
        index += 1;
      }
      if (!closed) {
        throw StateError('Unbalanced Dart string literal.');
      }
      continue;
    }
    output.write(source[index]);
    index += 1;
  }
  return output.toString();
}

int _requiredBalancedEnd(
  String source,
  int openingOffset,
  String opening,
  String closing,
) {
  var depth = 0;
  if (openingOffset < 0 ||
      openingOffset >= source.length ||
      source[openingOffset] != opening) {
    throw StateError('Expected opening delimiter $opening.');
  }
  for (var index = openingOffset; index < source.length; index += 1) {
    if (source[index] == opening) {
      depth += 1;
    }
    if (source[index] == closing) {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }
  throw StateError('Unbalanced delimiter $opening$closing.');
}

List<int> _offsets(String source, String marker) {
  final offsets = <int>[];
  var start = 0;
  while (true) {
    final offset = source.indexOf(marker, start);
    if (offset < 0) {
      return offsets;
    }
    offsets.add(offset);
    start = offset + marker.length;
  }
}

String _requiredMethodBody(String source, String marker) {
  final code = _maskDartCommentsAndStrings(source);
  final markers = _offsets(code, marker);
  if (markers.length != 1) {
    throw StateError(
      'Required method marker must be unique: $marker (${markers.length})',
    );
  }
  final markerStart = markers.single;
  final parametersStart = code.indexOf('(', markerStart);
  if (parametersStart < 0) {
    throw StateError('Required method has no parameter list: $marker');
  }
  final parametersEnd =
      _requiredBalancedEnd(code, parametersStart, '(', ')') + 1;

  final bodyStart = code.indexOf('{', parametersEnd);
  final declarationEnd = code.indexOf(';', parametersEnd);
  final expressionBody = code.indexOf('=>', parametersEnd);
  if (bodyStart < 0 ||
      (declarationEnd >= 0 && declarationEnd < bodyStart) ||
      (expressionBody >= 0 && expressionBody < bodyStart)) {
    throw StateError('Required method has no block body: $marker');
  }
  final bodyEnd = _requiredBalancedEnd(code, bodyStart, '{', '}');
  return source.substring(bodyStart, bodyEnd + 1);
}

String _requiredTransactionCallbackBody(
  String source, {
  required String methodMarker,
  required String transactionMarker,
}) {
  final methodBody = _requiredMethodBody(source, methodMarker);
  final code = _maskDartCommentsAndStrings(methodBody);
  final callbackPattern = RegExp(
    '${RegExp.escape(transactionMarker)}'
    r'\s*\(\s*\(\s*\)\s+async\s*\{',
  );
  final callbacks = callbackPattern.allMatches(code).toList(growable: false);
  if (callbacks.length != 1) {
    throw StateError(
      'Transaction callback must be unique in $methodMarker: '
      '$transactionMarker (${callbacks.length})',
    );
  }
  final bodyStart = callbacks.single.end - 1;
  final bodyEnd = _requiredBalancedEnd(code, bodyStart, '{', '}');
  return methodBody.substring(bodyStart, bodyEnd + 1);
}

({int persistenceCalls, int outboxCalls, bool ordered}) _createPathOrder(
  String transactionCallback, {
  required String persistenceCall,
  required String outboxCall,
}) {
  final code = _maskDartCommentsAndStrings(transactionCallback);
  final persistenceOffsets = _offsets(code, persistenceCall);
  final outboxOffsets = _offsets(code, outboxCall);
  return (
    persistenceCalls: persistenceOffsets.length,
    outboxCalls: outboxOffsets.length,
    ordered:
        persistenceOffsets.length == 1 &&
        outboxOffsets.length == 1 &&
        persistenceOffsets.single < outboxOffsets.single,
  );
}

void _expectOrdered(
  String source,
  List<String> markers, {
  required String reason,
}) {
  final code = _maskDartCommentsAndStrings(source);
  var previous = -1;
  for (final marker in markers) {
    final current = code.indexOf(marker);
    expect(current, greaterThan(previous), reason: '$reason: $marker');
    previous = current;
  }
}

bool _purchaseCommitPrecedesMutation(String source) {
  final code = _maskDartCommentsAndStrings(source);
  const resultAssignment = 'final result = await _avatarOperation(';
  const purchaseClosure = '() => repository.purchase(';
  const mutationNotification = 'onLocalMutation?.call()';
  final resultOffset = code.indexOf(resultAssignment);
  final purchaseOffset = code.indexOf(purchaseClosure, resultOffset + 1);
  final notificationOffset = code.indexOf(
    mutationNotification,
    purchaseOffset + 1,
  );
  return resultOffset >= 0 &&
      purchaseOffset > resultOffset &&
      notificationOffset > purchaseOffset;
}

final class _CreatePathContract {
  const _CreatePathContract({
    required this.path,
    required this.methodMarker,
    required this.transactionMarker,
    required this.persistenceCall,
    required this.outboxCall,
    this.replayOutboxCall,
  });

  final String path;
  final String methodMarker;
  final String transactionMarker;
  final String persistenceCall;
  final String outboxCall;
  final String? replayOutboxCall;
}

void main() {
  test('screens never own Drift or Firestore persistence', () {
    final screens = _dartFiles('lib/screens');
    expect(screens, isNotEmpty);

    final violations = <String>[];
    for (final file in screens) {
      for (final import in _imports(file.readAsStringSync())) {
        final directPersistenceImport =
            import == 'package:drift/drift.dart' ||
            import == 'package:drift/native.dart' ||
            import == 'package:cloud_firestore/cloud_firestore.dart' ||
            import.endsWith('/data/local/app_database.dart') ||
            import.contains('/data/drift_') ||
            import.endsWith('/data/firestore_sync_gateway.dart');
        if (directPersistenceImport) {
          violations.add('${file.path.replaceAll('\\', '/')}: $import');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Screens must mutate only through typed domain use cases.',
    );
  });

  test(
    'syncable domain rows and outbox entries share repository transactions',
    () {
      const contracts = <_CreatePathContract>[
        _CreatePathContract(
          path: 'lib/features/learning/data/drift_learning_repository.dart',
          methodMarker: 'Future<AnswerRecordResult> recordAnswer',
          transactionMarker: 'database.transaction',
          persistenceCall: '.into(database.answerAttempts)',
          outboxCall: '_appendImmutableOutbox(',
        ),
        _CreatePathContract(
          path:
              'lib/features/vocabulary/data/'
              'drift_vocabulary_repository.dart',
          methodMarker: 'Future<VocabularyCategory> createCategory',
          transactionMarker: 'database.transaction',
          persistenceCall: '.into(database.vocabularyCategories)',
          outboxCall: '_appendOutbox(',
        ),
        _CreatePathContract(
          path: 'lib/features/rewards/data/drift_reward_repository.dart',
          methodMarker: 'Future<PurchaseResult> purchase',
          transactionMarker: 'database.transaction',
          persistenceCall: '.into(database.rewardTransactions)',
          outboxCall: '_ensureOutbox(',
        ),
        _CreatePathContract(
          path:
              'lib/features/research/data/'
              'drift_experiment_assignment_repository.dart',
          methodMarker: 'Future<ExperimentAssignment> assignIfAbsent',
          transactionMarker: '_database.transaction',
          persistenceCall: '_insertAssignment(candidate)',
          outboxCall: '_ensureOutbox(inserted, createIfMissing: true)',
          replayOutboxCall: '_ensureOutbox(replay, createIfMissing: false)',
        ),
        _CreatePathContract(
          path: 'lib/features/assessment/data/drift_assessment_repository.dart',
          methodMarker: 'Future<AssessmentRun> start',
          transactionMarker: '_database.transaction',
          persistenceCall: '_database.customInsert(',
          outboxCall: '_ensureOutbox(persisted, revision: 1)',
          replayOutboxCall: '_ensureOutbox(existingById, revision: 1)',
        ),
      ];

      for (final contract in contracts) {
        final transactionCallback = _requiredTransactionCallbackBody(
          _read(contract.path),
          methodMarker: contract.methodMarker,
          transactionMarker: contract.transactionMarker,
        );
        final order = _createPathOrder(
          transactionCallback,
          persistenceCall: contract.persistenceCall,
          outboxCall: contract.outboxCall,
        );
        expect(
          order.persistenceCalls,
          1,
          reason: '${contract.path} must have one create-path persistence call',
        );
        expect(
          order.outboxCalls,
          1,
          reason: '${contract.path} must have one create-path outbox call',
        );
        expect(
          order.ordered,
          isTrue,
          reason:
              '${contract.path} must persist locally before enqueueing outbox',
        );
        final replayOutboxCall = contract.replayOutboxCall;
        if (replayOutboxCall != null) {
          expect(
            _offsets(
              _maskDartCommentsAndStrings(transactionCallback),
              replayOutboxCall,
            ),
            hasLength(1),
            reason:
                '${contract.path} must keep replay repair distinct from create',
          );
        }
      }
    },
  );

  test('create-path detector is callback scoped and rejects swapped calls', () {
    const orderedFixture = '''
Future<void> unrelatedHelper() async {
  await appendOutbox(inserted);
}

Future<void> createRecord() {
  return database.transaction(() async {
    if (replay != null) {
      await appendOutbox(replay);
      return;
    }
    await persist(candidate);
    await appendOutbox(inserted);
  });
}
''';
    const swappedFixture = '''
Future<void> unrelatedHelper() async {
  await appendOutbox(inserted);
}

Future<void> createRecord() {
  return database.transaction(() async {
    if (replay != null) {
      await appendOutbox(replay);
      return;
    }
    await appendOutbox(inserted);
    await persist(candidate);
  });
}
''';

    ({int persistenceCalls, int outboxCalls, bool ordered}) inspect(
      String source,
    ) {
      final callback = _requiredTransactionCallbackBody(
        source,
        methodMarker: 'Future<void> createRecord',
        transactionMarker: 'database.transaction',
      );
      return _createPathOrder(
        callback,
        persistenceCall: 'persist(candidate)',
        outboxCall: 'appendOutbox(inserted)',
      );
    }

    expect(inspect(orderedFixture), (
      persistenceCalls: 1,
      outboxCalls: 1,
      ordered: true,
    ));
    expect(inspect(swappedFixture), (
      persistenceCalls: 1,
      outboxCalls: 1,
      ordered: false,
    ));
  });

  test('remote claims begin only after committed application mutations', () {
    final learning = _requiredMethodBody(
      _read('lib/features/learning/application/learning_use_cases.dart'),
      'Future<AnswerRecordResult> _recordCanonicalEvidence',
    );
    _expectOrdered(
      learning,
      <String>['await repository.recordAnswer', 'onLocalMutation?.call()'],
      reason: 'Learning must notify sync only after its repository commit',
    );

    final vocabulary = _requiredMethodBody(
      _read('lib/features/vocabulary/application/vocabulary_use_cases.dart'),
      'Future<VocabularyCategory> createCategory',
    );
    _expectOrdered(
      vocabulary,
      <String>['await vocabulary.createCategory', 'onLocalMutation?.call()'],
      reason: 'Vocabulary must notify sync only after its repository commit',
    );

    final rewards = _requiredMethodBody(
      _read('lib/features/rewards/application/reward_use_cases.dart'),
      'Future<PurchaseResult> purchase',
    );
    expect(
      _purchaseCommitPrecedesMutation(rewards),
      isTrue,
      reason: 'Rewards must notify sync only after its repository commit',
    );

    final avatarOperation = _requiredMethodBody(
      _read('lib/features/rewards/application/reward_use_cases.dart'),
      'Future<T> _avatarOperation<T>',
    );
    expect(
      avatarOperation,
      contains('return await operation();'),
      reason: 'The avatar wrapper must await the repository operation.',
    );

    final bootstrap = _read('lib/runtime/app_bootstrap.dart');
    expect(
      bootstrap,
      contains('trigger.requestDetached(SyncTriggerReason.localMutation)'),
      reason: 'Cloud availability must not become part of the local commit.',
    );

    final detachedTrigger = _requiredMethodBody(
      _read('lib/features/sync/application/sync_trigger.dart'),
      'void requestDetached',
    );
    expect(detachedTrigger, contains('unawaited('));
    expect(detachedTrigger, contains('onError: (Object _, StackTrace _) {}'));

    final production = _dartFiles(
      'lib',
    ).map((file) => file.readAsStringSync()).join('\n');
    expect(
      RegExp(
        r'\b(?:class|mixin|enum|extension)\s+LocalFirstService\b',
      ).hasMatch(production),
      isFalse,
      reason: 'f40 reuses domain repositories and the existing outbox.',
    );
  });

  test('reward purchase inspector rejects an unawaited purchase wrapper', () {
    const committed = '''
Future<PurchaseResult> purchase() async {
  final currentAccount = await _avatarOperation(
    owner.id,
    () => repository.load(owner.id),
  );
  final result = await _avatarOperation(
    owner.id,
    () => repository.purchase(item),
  );
  onLocalMutation?.call();
  return result;
}
''';
    const unawaitedPurchase = '''
Future<PurchaseResult> purchase() async {
  final currentAccount = await _avatarOperation(
    owner.id,
    () => repository.load(owner.id),
  );
  final result = _avatarOperation(
    owner.id,
    () => repository.purchase(item),
  );
  onLocalMutation?.call();
  return await result;
}
''';

    expect(_purchaseCommitPrecedesMutation(committed), isTrue);
    expect(_purchaseCommitPrecedesMutation(unawaitedPurchase), isFalse);
  });

  test('retry and restart preserve one bounded durable operation identity', () {
    final engine = _requiredMethodBody(
      _read('lib/features/sync/application/sync_engine.dart'),
      'Future<SyncRunResult> run',
    );
    _expectOrdered(engine, <String>[
      'store.claimPending',
      'store.beginAttempt',
      'gateway.push(claim.mutation)',
      'store.markRetry',
    ], reason: 'Sync can retry only a claimed durable outbox mutation');
    expect(engine, contains('backoff.nextAttemptAt'));
    expect(engine, contains('claim.attemptCount < maxSyncSendReservations'));

    final store = _read('lib/features/sync/data/drift_sync_store.dart');
    expect(store, contains('static const int maxSendReservations ='));
    expect(store, contains("exhausted ? 'permanentFailure' : 'retryWaiting'"));

    final trigger = _read('lib/features/sync/application/sync_trigger.dart');
    expect(trigger, contains('this.maxGateWait = const Duration(seconds: 30)'));
    expect(trigger, contains('if (waited >= maxGateWait) return last'));

    final engineTests = _read('test/features/sync/sync_engine_test.dart');
    expect(
      engineTests,
      contains(
        'offline work retries then applies exactly once after reconnect',
      ),
    );
    expect(
      engineTests,
      contains(
        'five durable send reservations exhaust retryable work before a sixth '
        'call',
      ),
    );

    final recovery = _read(
      'test/scenarios/file_backed_sync_recovery_test.dart',
    );
    expect(
      recovery,
      contains(
        'lost acknowledgement replays vocabulary and learning work once '
        'after reopen',
      ),
    );
    expect(recovery, contains("const String _lostAckOperationId ="));
    expect(
      recovery,
      contains('expect(gateway.requestCounts[_lostAckNamespaceKey], 2)'),
    );
    expect(
      recovery,
      contains('expect(gateway.applyCounts[_lostAckNamespaceKey], 1)'),
    );
    expect(recovery, contains('expect(secondReopen.pushed, 0)'));

    final learningRestart = _read(
      'test/scenarios/production_learning_restart_test.dart',
    );
    expect(
      learningRestart,
      contains('answer completion does not await an offline projection batch'),
    );
    expect(learningRestart, contains('expect(result.inserted, isTrue)'));
  });
}
