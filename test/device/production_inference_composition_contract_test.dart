import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/device/device_capability_models.dart';

void main() {
  test('the only public decision factory is CPU-only', () {
    final modelsSource = File(
      'lib/device/device_capability_models.dart',
    ).readAsStringSync();

    final decision = InferenceDecision.cpu(
      tier: DevicePerformanceTier.balanced,
      analysisFrequency: AnalysisFrequency.standard,
      reason: InferenceDecisionReason.gpuAdapterUnverified,
    );

    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(
      RegExp(r'\bfactory\s+InferenceDecision\s*\(').hasMatch(modelsSource),
      isFalse,
    );
    expect(modelsSource, contains('factory InferenceDecision.cpu('));
    expect(
      RegExp(
        r'\bfactory\s+InferenceDecision\.(?!cpu\b)',
      ).hasMatch(modelsSource),
      isFalse,
    );
    final cpuFactorySignature = RegExp(
      r'\bfactory\s+InferenceDecision\.cpu\s*\((.*?)\)\s*=>',
      dotAll: true,
    ).firstMatch(modelsSource);
    expect(cpuFactorySignature, isNotNull);
    expect(cpuFactorySignature!.group(1), isNot(contains('backend')));
    expect(cpuFactorySignature.group(1), isNot(contains('InferenceBackend')));
  });

  test('production composition contains no GPU decision factory', () {
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(
      dartSources.contains('InferenceDecision.gpu'),
      isFalse,
      reason:
          'GPU execution must remain closed until an adapter-owned loaded-model '
          'evidence type exists.',
    );
  });
}
