import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

const _expectedBaselineCommit = 'd6be10d2ac6206fb018730449483c33cc4ed04b2';

void main() {
  final repositoryRoot = Directory.current;
  final manifestFile = File(
    '${repositoryRoot.path}/docs/generated/'
    'alltcas-8-44-final-test-plan.json',
  );

  Map<String, Object?> readManifest() {
    return (jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>)
        .cast<String, Object?>();
  }

  List<Map<String, Object?>> manifestMaps(
    Map<String, Object?> manifest,
    String key,
  ) {
    return (manifest[key]! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((value) => value.cast<String, Object?>())
        .toList(growable: false);
  }

  test(
    'final test plan review: explicit commit and fingerprint close every executable input',
    () {
      final manifest = readManifest();
      final sources = manifestMaps(manifest, 'sources');
      final sourcePaths = sources
          .map((source) => source['path']! as String)
          .toSet();

      expect(manifest['sourceCommit'], matches(RegExp(r'^[0-9a-f]{40}$')));

      final requiredExactInputs = <String>{
        'package.json',
        'pubspec.lock',
        'pubspec.yaml',
        'firebase.json',
        'firestore.rules',
        'tool/final_test_plan/generate_final_test_plan.dart',
        'tool/cli/run-android-smoke.ps1',
        'tool/cli/tests/run-android-smoke.tests.ps1',
        'test/architecture/final_8_44_test_plan_contract_test.dart',
        'test/architecture/final_8_44_test_plan_review_contract_test.dart',
        'test/database/migration_v1_to_v22_matrix_test.dart',
      };
      expect(sourcePaths, containsAll(requiredExactInputs));

      for (final alternatives in <List<String>>[
        <String>['android/app/build.gradle.kts', 'android/app/build.gradle'],
        <String>['android/settings.gradle.kts', 'android/settings.gradle'],
        <String>['android/build.gradle.kts', 'android/build.gradle'],
      ]) {
        final existing = alternatives
            .where((path) => File('${repositoryRoot.path}/$path').existsSync())
            .toList(growable: false);
        expect(existing, hasLength(1));
        expect(sourcePaths, contains(existing.single));
      }

      final gates = manifestMaps(manifest, 'gates');
      final executableSourceRefs = gates
          .expand(
            (gate) => (gate['sourceRefs']! as List<Object?>).cast<String>(),
          )
          .where(_isExecutableGateInput)
          .toSet();
      expect(
        sourcePaths,
        containsAll(executableSourceRefs),
        reason: 'Every executable gate input must contribute to the digest.',
      );
      for (final source in sources) {
        final path = source['path']! as String;
        final type = FileSystemEntity.typeSync('${repositoryRoot.path}/$path');
        expect(
          type,
          isNot(FileSystemEntityType.notFound),
          reason: 'Missing source input: $path',
        );
        expect(
          source['sha256'],
          _hashSourcePath(repositoryRoot, path, type),
          reason: '--check must fail when gate input $path changes.',
        );
      }

      final canonicalFingerprintInput = jsonEncode(<String, Object?>{
        'sources': sources,
      });
      expect(
        manifest['sourceFingerprint'],
        sha256.convert(utf8.encode(canonicalFingerprintInput)).toString(),
      );
    },
  );

  test(
    'final test plan review: architecture and analyze are exact non-overlapping gates',
    () {
      final manifest = readManifest();
      final gates = manifestMaps(manifest, 'gates');
      final commands = gates.map((gate) => gate['command']! as String).toList();

      expect(commands, contains('flutter test --no-pub test/architecture'));
      expect(commands, contains('flutter analyze'));

      final executableTargets =
          <({String gateId, String path, String? plainName})>[];
      for (final gate in gates) {
        final gateId = gate['id']! as String;
        final command = gate['command']! as String;
        for (final target in _flutterTestCoverage(command)) {
          executableTargets.add((
            gateId: gateId,
            path: target.path,
            plainName: target.plainName,
          ));
        }
      }
      for (var left = 0; left < executableTargets.length; left += 1) {
        for (
          var right = left + 1;
          right < executableTargets.length;
          right += 1
        ) {
          final a = executableTargets[left];
          final b = executableTargets[right];
          expect(
            _coverageOverlaps(a, b),
            isFalse,
            reason:
                'Executable coverage overlaps between ${a.gateId} (${a.path}) '
                'and ${b.gateId} (${b.path}).',
          );
        }
      }

      final rollbackGates = gates
          .where((gate) => (gate['category']! as String) == 'rollbackDrill')
          .toList(growable: false);
      expect(rollbackGates, isNotEmpty);
      for (final gate in rollbackGates) {
        final command = gate['command']! as String;
        expect(command, contains('--plain-name'));
        expect(
          command,
          contains(
            'file-backed permanent clear and TTL controls converge across restart',
          ),
        );
      }
    },
  );

  test(
    'final test plan review: flutter-tester integrations launch one file per process',
    () {
      final manifest = readManifest();
      final integrationGates = manifestMaps(manifest, 'gates')
          .where((gate) => gate['category'] == 'integration')
          .toList(growable: false);
      const expected = <String, ({String command, String source})>{
        'integration-feature-controls': (
          command:
              'flutter test -d flutter-tester --no-pub --reporter compact '
              'integration_test/field_trial_feature_controls_test.dart',
          source: 'integration_test/field_trial_feature_controls_test.dart',
        ),
        'integration-media-smoke': (
          command:
              'flutter test -d flutter-tester --no-pub --reporter compact '
              'integration_test/field_trial_media_smoke_test.dart',
          source: 'integration_test/field_trial_media_smoke_test.dart',
        ),
      };

      expect(
        integrationGates.map((gate) => gate['id']).toSet(),
        expected.keys.toSet(),
      );
      for (final gate in integrationGates) {
        final id = gate['id']! as String;
        final contract = expected[id]!;
        final command = gate['command']! as String;
        expect(command, contract.command, reason: id);
        expect((gate['sourceRefs']! as List<Object?>).cast<String>(), <String>[
          contract.source,
        ], reason: id);
        expect(
          RegExp(r'integration_test/[^\s]+\.dart')
              .allMatches(command)
              .map((match) => match.group(0))
              .toList(growable: false),
          <String>[contract.source],
          reason: '$id must start a fresh flutter-tester process',
        );
      }
    },
  );

  test(
    'final test plan review: every migration gate executes a frozen fixture',
    () {
      final manifest = readManifest();
      final migrationGates = manifestMaps(manifest, 'gates')
          .where(
            (gate) => (gate['category']! as String) == 'migrationTransition',
          )
          .toList(growable: false);

      expect(migrationGates, hasLength(AppDatabase.currentSchemaVersion - 1));
      for (final gate in migrationGates) {
        final command = gate['command']! as String;
        expect(command, startsWith('flutter test --no-pub '));
        expect(command, isNot(contains('Select-String')));
        expect(command, isNot(contains('rg ')));
        expect(command, isNot(contains('grep ')));
        final refs = (gate['sourceRefs']! as List<Object?>).cast<String>();
        expect(refs.any((path) => path.startsWith('test/database/')), isTrue);
        if (refs.contains(
          'test/database/migration_v1_to_v22_matrix_test.dart',
        )) {
          expect(command, contains('--plain-name'));
        }
      }
      expect(
        manifestMaps(
          manifest,
          'gates',
        ).where((gate) => gate['category'] == 'fullUpgrade'),
        hasLength(1),
      );
      expect(
        migrationGates.any(
          (gate) => (gate['command']! as String).contains(
            'migration_v1_to_v22_matrix_test.dart',
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'final test plan review: Android smoke authenticates selected device metadata',
    () {
      final manifest = readManifest();
      final androidSmoke = manifestMaps(
        manifest,
        'gates',
      ).singleWhere((gate) => gate['id'] == 'android-bounded-core-smoke');
      final command = androidSmoke['command']! as String;

      expect(
        command,
        'powershell -NoProfile -ExecutionPolicy Bypass '
        '-File tool/cli/run-android-smoke.ps1',
      );
      expect(
        (androidSmoke['sourceRefs']! as List<Object?>).cast<String>(),
        containsAll(<String>[
          'tool/cli/run-android-smoke.ps1',
          'tool/cli/tests/run-android-smoke.tests.ps1',
          'integration_test/field_trial_core_journey_test.dart',
        ]),
      );
    },
  );

  test(
    'final test plan review: Android smoke accepts real Flutter device metadata fail closed',
    () {
      final manifest = readManifest();
      final command =
          manifestMaps(manifest, 'gates').singleWhere(
                (gate) => gate['id'] == 'android-bounded-core-smoke',
              )['command']!
              as String;
      final cases =
          <({Map<String, Object?> device, bool accepted, String reason})>[
            (
              device: const <String, Object?>{
                'id': 'V2041',
                'targetPlatform': 'android-arm64',
              },
              accepted: true,
              reason: 'Flutter 3.44 Android device omits platformType',
            ),
            (
              device: const <String, Object?>{
                'id': 'emulator-5554',
                'targetPlatform': 'android-x64',
                'platformType': 'android',
              },
              accepted: true,
              reason: 'explicit consistent Android metadata',
            ),
            (
              device: const <String, Object?>{
                'id': 'windows',
                'targetPlatform': 'windows-x64',
              },
              accepted: false,
              reason: 'Windows target is not Android',
            ),
            (
              device: const <String, Object?>{
                'id': 'chrome',
                'targetPlatform': 'web-javascript',
                'platformType': 'web',
              },
              accepted: false,
              reason: 'Web target is not Android',
            ),
            (
              device: const <String, Object?>{
                'id': 'contradictory',
                'targetPlatform': 'android-arm64',
                'platformType': 'windows',
              },
              accepted: false,
              reason: 'present platformType must not contradict targetPlatform',
            ),
          ];

      for (final testCase in cases) {
        expect(
          _generatedAndroidCommandAccepts(command, testCase.device),
          testCase.accepted,
          reason: testCase.reason,
        );
      }
    },
  );

  test(
    'final test plan review: runtime ledger names the implementation baseline honestly',
    () {
      final ledger = File(
        '${repositoryRoot.path}/docs/field/'
        '2026-08-09-runtime-feature-ledger.md',
      ).readAsStringSync();

      expect(ledger, contains(_expectedBaselineCommit));
      for (final paragraph
          in ledger
              .replaceAll('\r\n', '\n')
              .replaceAll('\r', '\n')
              .split(RegExp(r'\n\s*\n'))) {
        if (paragraph.contains('c55f7bb')) {
          expect(
            paragraph.toLowerCase(),
            isNot(contains('metadata-only')),
            reason:
                'The ledger must not classify post-c55f7bb implementation as '
                'metadata-only.',
          );
        }
      }
    },
  );
  test(
    'final test plan review: later implementation is not described as metadata only',
    () {
      final ledger = File(
        '${repositoryRoot.path}/docs/field/'
        '2026-08-09-runtime-feature-ledger.md',
      ).readAsStringSync();

      expect(ledger, contains(_expectedBaselineCommit));
      expect(
        _claimsLaterChangesAreMetadataOnly(ledger),
        isFalse,
        reason:
            'A later implementation baseline cannot coexist with a claim '
            'that later changes are limited to metadata or documents.',
      );
    },
  );
}

bool _generatedAndroidCommandAccepts(
  String command,
  Map<String, Object?> device,
) {
  const expectedCommand =
      'powershell -NoProfile -ExecutionPolicy Bypass '
      '-File tool/cli/run-android-smoke.ps1';
  if (command != expectedCommand) return false;
  final targetPlatform = (device['targetPlatform'] as String? ?? '')
      .toLowerCase();
  final platformType = (device['platformType'] as String? ?? '').toLowerCase();
  return targetPlatform.startsWith('android') &&
      (platformType == 'android' || platformType.isEmpty);
}

bool _claimsLaterChangesAreMetadataOnly(String ledger) {
  final normalized = ledger
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
  return RegExp(
    r'(?:later|subsequent|following|post-[^\s]+)\s+'
    r'(?:changes|commits|work)\b[^.\n]{0,120}'
    r'(?:limited\s+to|only|metadata-only)[^.\n]{0,80}'
    r'(?:metadata|documents?|documentation)',
  ).hasMatch(normalized);
}

bool _isExecutableGateInput(String path) {
  return path == 'lib' ||
      path == 'test' ||
      path == 'tool' ||
      path.startsWith('lib/') ||
      path.startsWith('test/') ||
      path.startsWith('integration_test/') ||
      path.startsWith('tool/') ||
      path.startsWith('android/') ||
      path == 'package.json' ||
      path == 'pubspec.lock' ||
      path == 'pubspec.yaml' ||
      path == 'firebase.json' ||
      path == 'firestore.rules';
}

Iterable<({String path, String? plainName})> _flutterTestCoverage(
  String command,
) sync* {
  final commandMatch = RegExp(
    r'flutter test(?:\s+-d\s+\S+)?\s+([^;&]+)',
  ).firstMatch(command);
  if (commandMatch == null) return;
  final invocation = commandMatch.group(0)!;
  final plainNameMatch = RegExp(
    r'''--plain-name\s+(?:"([^"]+)"|'([^']+)'|(\S+))''',
  ).firstMatch(invocation);
  final plainName = plainNameMatch == null
      ? null
      : (plainNameMatch.group(1) ??
            plainNameMatch.group(2) ??
            plainNameMatch.group(3));
  final tokens = invocation.split(RegExp(r'\s+'));
  for (final token in tokens) {
    if (token.startsWith('-')) {
      continue;
    }
    final normalized = token.replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (normalized == 'compact' || normalized.contains('=')) {
      continue;
    }
    if (normalized.startsWith('test/') ||
        normalized.startsWith('integration_test/')) {
      yield (
        path: normalized.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), ''),
        plainName: plainName,
      );
    }
  }
}

String _hashSourcePath(
  Directory root,
  String relativePath,
  FileSystemEntityType type,
) {
  final absolutePath = '${root.path}/$relativePath';
  if (type == FileSystemEntityType.file) {
    return sha256.convert(File(absolutePath).readAsBytesSync()).toString();
  }
  final directory = Directory(absolutePath);
  final files =
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  final entries = <String>[];
  for (final file in files) {
    final childPath = file.path
        .substring(directory.path.length + 1)
        .replaceAll('\\', '/');
    entries.add('$childPath\u0000${sha256.convert(file.readAsBytesSync())}');
  }
  return sha256.convert(utf8.encode(entries.join('\n'))).toString();
}

bool _coverageOverlaps(
  ({String gateId, String path, String? plainName}) left,
  ({String gateId, String path, String? plainName}) right,
) {
  final pathsOverlap =
      left.path == right.path ||
      left.path.startsWith('${right.path}/') ||
      right.path.startsWith('${left.path}/');
  if (!pathsOverlap) {
    return false;
  }
  if (left.plainName != null &&
      right.plainName != null &&
      left.plainName != right.plainName) {
    return false;
  }
  return true;
}
