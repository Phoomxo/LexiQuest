import 'package:flutter/widgets.dart';

import '../../device_model/application/device_model_use_cases.dart';
import '../../device_model/application/model_benchmark.dart';
import '../../device_model/domain/model_lifecycle.dart';
import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_category.dart';
import '../../vocabulary/domain/vocabulary_failure.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../../services/object_vocabulary_database.dart';
import '../domain/media_practice_contracts.dart';
import 'image_preprocessor.dart';

abstract interface class ObjectScannerController {
  bool get isReady;

  Future<void> initialize();

  Widget buildPreview();

  Future<ModelDownloadRecord?> modelStatus();

  Future<ModelDownloadRecord> downloadModel({ModelCancellation? cancellation});

  Future<List<ModelBenchmarkResult>> benchmarkModel({
    String deviceTier = 'field-device',
    int warmupRuns = 3,
    int measuredRuns = 20,
  });

  Future<ObjectScanResult> captureAndClassify({
    ModelCancellation? cancellation,
  });

  Future<VocabularyWord> accept(
    ObjectScanResult result, {
    String? categoryId,
    String? expectedOwnerId,
  });

  Future<void> pause();

  Future<void> resume();

  Future<void> dispose();
}

final class ObjectScanResult {
  const ObjectScanResult({
    required this.classifications,
    required this.vocabulary,
    required this.matchedClassification,
    required this.modelId,
    required this.modelVersion,
    required this.capturedAtUtc,
  });

  final List<ModelClassification> classifications;
  final ScannedVocabulary? vocabulary;
  final ModelClassification? matchedClassification;
  final String modelId;
  final String modelVersion;
  final DateTime capturedAtUtc;

  ModelClassification get primary => classifications.first;
}

final class ObjectScannerUseCases implements ObjectScannerController {
  ObjectScannerUseCases({
    required this.camera,
    required this.deviceModels,
    required this.vocabulary,
    required this.preprocessor,
    this.labelVocabulary = const ObjectVocabularyDatabase(),
    this.minimumConfidence = 0.15,
  });

  final CameraGateway camera;
  final DeviceModelUseCases deviceModels;
  final VocabularyUseCases vocabulary;
  final ImagePreprocessor preprocessor;
  final ObjectVocabularyDatabase labelVocabulary;
  final double minimumConfidence;
  ImageClassifierRuntime? _runtime;
  bool _disposed = false;

  @override
  bool get isReady => camera.isInitialized && _runtime != null && !_disposed;

  @override
  Widget buildPreview() => camera.buildPreview();

  @override
  Future<ModelDownloadRecord?> modelStatus() => deviceModels.status();

  @override
  Future<ModelDownloadRecord> downloadModel({ModelCancellation? cancellation}) {
    return deviceModels.downloadAndActivate(cancellation: cancellation);
  }

  @override
  Future<List<ModelBenchmarkResult>> benchmarkModel({
    String deviceTier = 'field-device',
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) {
    return deviceModels.benchmarkActive(
      deviceTier: deviceTier,
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
    );
  }

  @override
  Future<void> initialize() async {
    _checkNotDisposed();
    final permission = await camera.requestPermission();
    switch (permission) {
      case MediaPermissionState.granted:
        break;
      case MediaPermissionState.permanentlyDenied:
        throw const CameraPracticeException(
          CameraFailureCode.permissionPermanentlyDenied,
        );
      case MediaPermissionState.denied:
      case MediaPermissionState.restricted:
        throw const CameraPracticeException(CameraFailureCode.permissionDenied);
      case MediaPermissionState.unavailable:
        throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    try {
      await camera.initialize();
      if (!camera.isInitialized) {
        throw const CameraPracticeException(
          CameraFailureCode.initializationFailed,
        );
      }
      _runtime ??= await deviceModels.openActive(delegate: ModelDelegate.cpu);
    } on ModelLifecycleException {
      await camera.pause();
      throw const CameraPracticeException(CameraFailureCode.modelUnavailable);
    } on CameraPracticeException {
      rethrow;
    } catch (_) {
      await camera.pause();
      throw const CameraPracticeException(
        CameraFailureCode.initializationFailed,
      );
    }
  }

  @override
  Future<ObjectScanResult> captureAndClassify({
    ModelCancellation? cancellation,
  }) async {
    _checkNotDisposed();
    final runtime = _runtime;
    if (!camera.isInitialized || runtime == null) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    if (cancellation?.isCancelled ?? false) {
      throw const CameraPracticeException(CameraFailureCode.cancelled);
    }
    try {
      final captured = await camera.capture();
      if (cancellation?.isCancelled ?? false) {
        throw const CameraPracticeException(CameraFailureCode.cancelled);
      }
      final input = preprocessor.toRawRgb224(captured.bytes);
      final classifications = await runtime.classify(input, topK: 10);
      if (cancellation?.isCancelled ?? false) {
        throw const CameraPracticeException(CameraFailureCode.cancelled);
      }
      final usable = classifications
          .where(
            (result) =>
                result.index > 0 && result.confidence >= minimumConfidence,
          )
          .toList(growable: false);
      if (usable.isEmpty) {
        throw const CameraPracticeException(CameraFailureCode.noConfidentMatch);
      }
      ScannedVocabulary? mapped;
      ModelClassification? matchedClassification;
      for (final classification in usable) {
        mapped = labelVocabulary.lookupByMlLabel(classification.label);
        if (mapped != null) {
          matchedClassification = classification;
          break;
        }
      }
      return ObjectScanResult(
        classifications: usable,
        vocabulary: mapped,
        matchedClassification: matchedClassification,
        modelId: deviceModels.manifest.id,
        modelVersion: deviceModels.manifest.version,
        capturedAtUtc: captured.capturedAtUtc,
      );
    } on CameraPracticeException {
      rethrow;
    } catch (_) {
      throw const CameraPracticeException(CameraFailureCode.captureFailed);
    }
  }

  @override
  Future<VocabularyWord> accept(
    ObjectScanResult result, {
    String? categoryId,
    String? expectedOwnerId,
  }) async {
    _checkNotDisposed();
    final mapped = result.vocabulary;
    if (mapped == null) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    final ownerId = await _requireOwner(expectedOwnerId);
    final category = await _findOrCreateCategory(
      mapped.category,
      categoryId: categoryId,
      expectedOwnerId: ownerId,
    );
    final words = await vocabulary.watchWords(category.id).first;
    await _requireOwner(ownerId);
    final normalizedSpelling = normalizeVocabularyText(mapped.englishWord);
    final normalizedMeaning = normalizeVocabularyText(mapped.thaiTranslation);
    for (final word in words) {
      if (word.normalizedSpelling == normalizedSpelling &&
          word.normalizedMeaning == normalizedMeaning) {
        return word;
      }
    }
    try {
      final word = await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: mapped.englishWord,
          meaning: mapped.thaiTranslation,
          partOfSpeech: 'noun',
          cefrLevel: mapped.cefrLevel,
          source: 'object-scanner:${result.modelId}@${result.modelVersion}',
        ),
      );
      await _requireOwner(ownerId);
      return word;
    } on DuplicateVocabularyFailure {
      final refreshed = await vocabulary.watchWords(category.id).first;
      await _requireOwner(ownerId);
      return refreshed.firstWhere(
        (word) =>
            word.normalizedSpelling == normalizedSpelling &&
            word.normalizedMeaning == normalizedMeaning,
      );
    }
  }

  Future<VocabularyCategory> _findOrCreateCategory(
    String name, {
    String? categoryId,
    required String expectedOwnerId,
  }) async {
    final normalized = normalizeVocabularyText(name);
    final categories = await vocabulary.watchCategories().first;
    await _requireOwner(expectedOwnerId);
    for (final category in categories) {
      if (categoryId == null
          ? category.normalizedName == normalized
          : category.id == categoryId) {
        return category;
      }
    }
    if (categoryId != null) throw const VocabularyNotFoundFailure();
    try {
      final category = await vocabulary.createCategory(name);
      await _requireOwner(expectedOwnerId);
      return category;
    } on DuplicateVocabularyFailure {
      final refreshed = await vocabulary.watchCategories().first;
      await _requireOwner(expectedOwnerId);
      return refreshed.firstWhere(
        (category) => category.normalizedName == normalized,
      );
    }
  }

  Future<String> _requireOwner(String? expectedOwnerId) async {
    final owner = await vocabulary.owners.getOrCreateActiveOwner();
    if (expectedOwnerId != null && owner.id != expectedOwnerId) {
      throw const VocabularyNotFoundFailure();
    }
    return owner.id;
  }

  @override
  Future<void> pause() => camera.pause();

  @override
  Future<void> resume() async {
    _checkNotDisposed();
    await camera.resume();
    if (!camera.isInitialized) {
      throw const CameraPracticeException(
        CameraFailureCode.initializationFailed,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _runtime?.close();
    _runtime = null;
    await camera.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('ObjectScannerUseCases is disposed.');
  }
}
