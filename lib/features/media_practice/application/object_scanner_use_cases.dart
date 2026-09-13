import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../device_model/application/device_model_use_cases.dart';
import '../../device_model/application/model_benchmark.dart';
import '../../device_model/domain/model_lifecycle.dart';
import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../../services/object_vocabulary_database.dart';
import '../domain/media_practice_contracts.dart';
import 'image_preprocessor.dart';

abstract interface class ObjectScannerController {
  bool get isReady;

  ObjectScannerLease acquireLease();

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

  Future<VocabularyWord> accept(ObjectScanResult result);

  Future<void> pause();

  Future<void> resume();

  Future<void> dispose();
}

abstract interface class ObjectScannerLease {
  bool get isCurrent;

  bool get isReady;

  Future<bool> initialize();

  Future<void> pause();

  Future<void> resume();

  Future<void> release();
}

/// Serializes lifecycle ownership for a runtime-scoped scanner controller.
///
/// A newly acquired lease synchronously supersedes the previous consumer. Its
/// initialization is queued behind both any in-flight operation and a takeover
/// pause, so a stale route can never pause a newer preview after completing
/// late.
final class ObjectScannerLeaseManager {
  factory ObjectScannerLeaseManager({
    required bool Function() isReady,
    required Future<void> Function() initialize,
    required Future<void> Function() pause,
    required Future<void> Function() resume,
    void Function()? onInvalidated,
  }) => ObjectScannerLeaseManager._(
    isReady,
    initialize,
    pause,
    resume,
    onInvalidated,
  );

  ObjectScannerLeaseManager._(
    this._isReady,
    this._initialize,
    this._pause,
    this._resume,
    this._onInvalidated,
  );

  final bool Function() _isReady;
  final Future<void> Function() _initialize;
  final Future<void> Function() _pause;
  final Future<void> Function() _resume;
  final void Function()? _onInvalidated;
  Future<void> _operationTail = Future<void>.value();
  int _nextLeaseId = 0;
  int? _activeLeaseId;
  bool _closed = false;

  ObjectScannerLease acquire() {
    if (_closed) {
      throw StateError('ObjectScannerLeaseManager is closed.');
    }
    final hadActiveLease = _activeLeaseId != null;
    final leaseId = ++_nextLeaseId;
    _activeLeaseId = leaseId;
    _onInvalidated?.call();
    if (hadActiveLease) {
      _enqueue<void>(() async {
        if (_activeLeaseId == leaseId) await _pause();
      }).ignore();
    }
    return _ManagedObjectScannerLease(this, leaseId);
  }

  bool _isCurrent(int leaseId) => !_closed && _activeLeaseId == leaseId;

  bool _leaseIsReady(int leaseId) => _isCurrent(leaseId) && _isReady();

  Future<bool> _initializeLease(int leaseId) {
    return _enqueue<bool>(() async {
      if (!_isCurrent(leaseId)) return false;
      await _initialize();
      return _isCurrent(leaseId);
    });
  }

  Future<void> _pauseLease(int leaseId) {
    if (_isCurrent(leaseId)) _onInvalidated?.call();
    return _enqueue<void>(() async {
      if (_isCurrent(leaseId)) await _pause();
    });
  }

  Future<void> _resumeLease(int leaseId) {
    return _enqueue<void>(() async {
      if (_isCurrent(leaseId)) await _resume();
    });
  }

  Future<void> _releaseLease(int leaseId) {
    if (!_isCurrent(leaseId)) return Future<void>.value();
    _activeLeaseId = null;
    _onInvalidated?.call();
    // This cleanup remains ahead of any subsequently acquired lease's
    // initialization in the shared operation queue.
    return _enqueue<void>(_pause);
  }

  /// Invalidates every lease and drains any serialized lifecycle work.
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _activeLeaseId = null;
      _onInvalidated?.call();
    }
    await _operationTail;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completion = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completion.complete(await operation());
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }
}

final class _ManagedObjectScannerLease implements ObjectScannerLease {
  _ManagedObjectScannerLease(this._manager, this._leaseId);

  final ObjectScannerLeaseManager _manager;
  final int _leaseId;
  bool _released = false;

  @override
  bool get isCurrent => !_released && _manager._isCurrent(_leaseId);

  @override
  bool get isReady => !_released && _manager._leaseIsReady(_leaseId);

  @override
  Future<bool> initialize() {
    if (_released) return Future<bool>.value(false);
    return _manager._initializeLease(_leaseId);
  }

  @override
  Future<void> pause() {
    if (_released) return Future<void>.value();
    return _manager._pauseLease(_leaseId);
  }

  @override
  Future<void> resume() {
    if (_released) return Future<void>.value();
    return _manager._resumeLease(_leaseId);
  }

  @override
  Future<void> release() {
    if (_released) return Future<void>.value();
    _released = true;
    return _manager._releaseLease(_leaseId);
  }
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
  int _scanGeneration = 0;
  ObjectScanResult? _issuedResult;
  String? _issuedOwnerId;
  Future<void>? _disposeFuture;
  late final ObjectScannerLeaseManager _leaseManager =
      ObjectScannerLeaseManager(
        isReady: () => isReady,
        initialize: initialize,
        pause: pause,
        resume: resume,
        onInvalidated: _invalidateResult,
      );

  @override
  ObjectScannerLease acquireLease() {
    _checkNotDisposed();
    _invalidateResult();
    return _leaseManager.acquire();
  }

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
    _invalidateResult();
    try {
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
          throw const CameraPracticeException(
            CameraFailureCode.permissionDenied,
          );
        case MediaPermissionState.unavailable:
          throw const CameraPracticeException(CameraFailureCode.unavailable);
      }
      if (_disposed) return;
      await camera.initialize();
      if (_disposed) {
        await camera.pause();
        return;
      }
      if (_runtime == null) {
        final opened = await deviceModels.openActive(
          delegate: ModelDelegate.cpu,
        );
        if (_disposed) {
          opened.close();
          await camera.pause();
          return;
        }
        _runtime = opened;
      }
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
    _invalidateResult();
    final generation = _scanGeneration;
    final runtime = _runtime;
    if (!camera.isInitialized || runtime == null) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    if (cancellation?.isCancelled ?? false) {
      throw const CameraPracticeException(CameraFailureCode.cancelled);
    }
    try {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      if (_disposed ||
          generation != _scanGeneration ||
          (cancellation?.isCancelled ?? false)) {
        throw const CameraPracticeException(CameraFailureCode.cancelled);
      }
      final captured = await camera.capture();
      if (_disposed ||
          generation != _scanGeneration ||
          (cancellation?.isCancelled ?? false)) {
        throw const CameraPracticeException(CameraFailureCode.cancelled);
      }
      final input = preprocessor.toRawRgb224(captured.bytes);
      final classCount = deviceModels.manifest.outputShape.last;
      final classifications = await runtime.classify(
        input,
        topK: classCount < 10 ? classCount : 10,
      );
      final currentOwner = await vocabulary.owners.getOrCreateActiveOwner();
      if (currentOwner.id != owner.id ||
          _disposed ||
          generation != _scanGeneration ||
          (cancellation?.isCancelled ?? false)) {
        throw const CameraPracticeException(CameraFailureCode.cancelled);
      }
      if (classifications.any(
        (item) =>
            !item.confidence.isFinite ||
            item.confidence < 0 ||
            item.confidence > 1 ||
            item.index < 0 ||
            item.index >= classCount,
      )) {
        throw const CameraPracticeException(CameraFailureCode.captureFailed);
      }
      final usable = classifications
          .where(
            (result) =>
                result.index >= 0 &&
                result.index != deviceModels.manifest.backgroundClassIndex &&
                result.confidence >= minimumConfidence,
          )
          .toList(growable: false);
      if (usable.isEmpty) {
        throw const CameraPracticeException(CameraFailureCode.notConfident);
      }
      final primary = usable.first;
      final mapped = labelVocabulary.lookupByMlLabel(primary.label);
      final result = ObjectScanResult(
        classifications: List.unmodifiable(usable),
        vocabulary: mapped,
        matchedClassification: mapped == null ? null : primary,
        modelId: deviceModels.manifest.id,
        modelVersion: deviceModels.manifest.version,
        capturedAtUtc: captured.capturedAtUtc,
      );
      _issuedResult = result;
      _issuedOwnerId = owner.id;
      return result;
    } on CameraPracticeException {
      rethrow;
    } catch (_) {
      throw const CameraPracticeException(CameraFailureCode.captureFailed);
    }
  }

  @override
  Future<VocabularyWord> accept(ObjectScanResult result) async {
    _checkNotDisposed();
    final mapped = result.vocabulary;
    if (!identical(_issuedResult, result) || mapped == null) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    final ownerId = _issuedOwnerId;
    final generation = _scanGeneration;
    if (ownerId == null) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    return vocabulary.createOrReuseWordInCategory(
      expectedOwnerId: ownerId,
      categoryName: mapped.category,
      spelling: mapped.englishWord,
      meaning: mapped.thaiTranslation,
      partOfSpeech: 'noun',
      cefrLevel: mapped.cefrLevel,
      source: 'object-scanner:${result.modelId}@${result.modelVersion}',
      mutationAllowed: () =>
          !_disposed &&
          generation == _scanGeneration &&
          identical(_issuedResult, result),
    );
  }

  @override
  Future<void> pause() {
    _invalidateResult();
    return camera.pause();
  }

  void _invalidateResult() {
    _scanGeneration += 1;
    _issuedResult = null;
    _issuedOwnerId = null;
  }

  @override
  Future<void> resume() async {
    _checkNotDisposed();
    await camera.resume();
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _invalidateResult();
    await _leaseManager.close();
    final runtime = _runtime;
    _runtime = null;
    runtime?.close();
    await camera.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('ObjectScannerUseCases is disposed.');
  }
}
