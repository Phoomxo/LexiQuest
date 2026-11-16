import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_litert/flutter_litert.dart' as tflite;

import '../application/model_download_manager.dart';
import '../domain/model_lifecycle.dart';
import '../domain/model_manifest.dart';

final class LiteRtModelFileVerifier implements ModelFileVerifier {
  const LiteRtModelFileVerifier();

  @override
  Future<void> verify(String path, ModelManifest manifest) async {
    LiteRtImageClassifier? classifier;
    try {
      classifier = await LiteRtImageClassifier.open(
        path: path,
        manifest: manifest,
        delegate: ModelDelegate.cpu,
        threads: 1,
      );
    } on ModelLifecycleException {
      rethrow;
    } catch (_) {
      throw const ModelLifecycleException(ModelFailureCode.interpreterRejected);
    } finally {
      classifier?.close();
    }
  }
}

final class LiteRtImageClassifier implements ImageClassifierRuntime {
  LiteRtImageClassifier._({
    required this._interpreter,
    required this._options,
    required this.delegate,
    required List<String> labels,
    this._nativeDelegate,
  }) : _labels = List<String>.unmodifiable(labels);

  final tflite.Interpreter _interpreter;
  final tflite.InterpreterOptions _options;
  final tflite.Delegate? _nativeDelegate;
  final List<String> _labels;
  @override
  final ModelDelegate delegate;
  bool _closed = false;

  static Future<LiteRtImageClassifier> open({
    required String path,
    required ModelManifest manifest,
    required ModelDelegate delegate,
    int threads = 2,
  }) async {
    if (threads < 1 || threads > 8) {
      throw ArgumentError.value(threads, 'threads', 'must be between 1 and 8');
    }
    if (!manifest.supportedDelegates.contains(delegate)) {
      throw const ModelLifecycleException(ModelFailureCode.unavailable);
    }
    final options = tflite.InterpreterOptions()..threads = threads;
    tflite.Delegate? nativeDelegate;
    try {
      if (delegate == ModelDelegate.xnnpack) {
        nativeDelegate = tflite.XNNPackDelegate(
          options: tflite.XNNPackDelegateOptions(numThreads: threads),
        );
        options.addDelegate(nativeDelegate);
      }
      final interpreter = tflite.Interpreter.fromFile(
        File(path),
        options: options,
      );
      try {
        _validateContract(interpreter, manifest);
        final labels = _readEmbeddedLabels(path, manifest.labelAssetName);
        if (labels.length != manifest.outputShape.last) {
          throw const ModelLifecycleException(
            ModelFailureCode.incompatibleTensor,
          );
        }
        return LiteRtImageClassifier._(
          interpreter: interpreter,
          options: options,
          delegate: delegate,
          labels: labels,
          nativeDelegate: nativeDelegate,
        );
      } catch (_) {
        interpreter.close();
        rethrow;
      }
    } catch (_) {
      nativeDelegate?.delete();
      options.delete();
      rethrow;
    }
  }

  static void _validateContract(
    tflite.Interpreter interpreter,
    ModelManifest manifest,
  ) {
    final inputs = interpreter.getInputTensors();
    final outputs = interpreter.getOutputTensors();
    if (inputs.length != 1 ||
        outputs.length != 1 ||
        !_sameShape(inputs.single.shape, manifest.inputShape) ||
        !_sameShape(outputs.single.shape, manifest.outputShape) ||
        !_sameType(inputs.single.type, manifest.inputType) ||
        !_sameType(outputs.single.type, manifest.outputType)) {
      throw const ModelLifecycleException(ModelFailureCode.incompatibleTensor);
    }
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  static bool _sameType(tflite.TensorType actual, ModelTensorType expected) {
    return switch (expected) {
      ModelTensorType.uint8 => actual == tflite.TensorType.uint8,
      ModelTensorType.float32 => actual == tflite.TensorType.float32,
    };
  }

  static List<String> _readEmbeddedLabels(String path, String assetName) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final file in archive) {
        if (file.isFile && file.name.split('/').last == assetName) {
          final bytes = file.readBytes();
          if (bytes == null) break;
          return const LineSplitter()
              .convert(utf8.decode(bytes))
              .map((label) => label.trim())
              .where((label) => label.isNotEmpty)
              .toList(growable: false);
        }
      }
    } finally {
      input.closeSync();
    }
    throw const ModelLifecycleException(ModelFailureCode.incompatibleTensor);
  }

  @override
  Future<List<ModelClassification>> classify(
    Uint8List rgbBytes, {
    int topK = 5,
  }) async {
    _checkOpen();
    final input = _interpreter.getInputTensor(0);
    if (rgbBytes.length != input.numBytes()) {
      throw ArgumentError.value(
        rgbBytes.length,
        'rgbBytes',
        'must match the input tensor byte count',
      );
    }
    if (topK < 1 || topK > _labels.length) {
      throw ArgumentError.value(topK, 'topK', 'is out of bounds');
    }
    final output = Uint8List(_interpreter.getOutputTensor(0).numBytes());
    _interpreter.run(rgbBytes, output);
    final params = _interpreter.getOutputTensor(0).params;
    final scores = List<ModelClassification>.generate(output.length, (index) {
      final confidence = (output[index] - params.zeroPoint) * params.scale;
      return ModelClassification(
        index: index,
        label: _labels[index],
        confidence: confidence.clamp(0.0, 1.0),
      );
    });
    scores.sort((a, b) => b.confidence.compareTo(a.confidence));
    return scores.take(topK).toList(growable: false);
  }

  @override
  Future<void> run(Uint8List input) async {
    await classify(input, topK: 1);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
    _nativeDelegate?.delete();
    _options.delete();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Model runtime is closed.');
    }
  }
}
