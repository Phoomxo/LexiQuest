import 'package:flutter/material.dart';

import '../features/device_model/application/model_benchmark.dart';
import '../features/device_model/domain/model_lifecycle.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class ObjectScannerScreen extends StatefulWidget {
  const ObjectScannerScreen({super.key, this.scanner, this.voice});

  final ObjectScannerController? scanner;
  final VoiceUseCases? voice;

  @override
  State<ObjectScannerScreen> createState() => _ObjectScannerScreenState();
}

class _ObjectScannerScreenState extends State<ObjectScannerScreen>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<ObjectScannerScreen> {
  ObjectScannerController? _scanner;
  ObjectScannerLease? _scannerLease;
  ObjectScannerLease? _initializedLease;
  VoiceUseCases? _voice;
  bool _cameraForeground = true;
  bool _initializing = true;
  bool _capturing = false;
  bool _downloading = false;
  bool _benchmarking = false;
  bool _modelUnavailable = false;
  bool _accepted = false;
  String? _error;
  ObjectScanResult? _result;
  List<ModelBenchmarkResult> _benchmarks = const [];
  ModelCancellation? _captureCancellation;
  ModelCancellation? _downloadCancellation;
  int _captureEpoch = 0;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void onVoiceRouteCovered() => _releaseScannerLease();

  @override
  void onVoiceRouteResumed() => _bindDependencies(refreshVoice: false);

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _cameraForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindDependencies();
  }

  @override
  void didUpdateWidget(ObjectScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDependencies();
  }

  void _bindDependencies({bool refreshVoice = true}) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final scanner = widget.scanner ?? dependencies?.objectScanner;
    final voice = widget.voice ?? dependencies?.voice;
    if (!identical(scanner, _scanner)) {
      _releaseScannerLease();
      _initializedLease = null;
    }
    _scanner = scanner;
    _voice = voice;
    if (refreshVoice) refreshRouteVoiceSession();
    if (!routeIsCurrent || scanner == null || voice == null) {
      _releaseScannerLease();
      return;
    }
    if (_cameraForeground && _scannerLease == null) {
      _scannerLease = scanner.acquireLease();
    }
    final lease = _scannerLease;
    if (lease != null &&
        lease.isCurrent &&
        _cameraForeground &&
        !identical(lease, _initializedLease)) {
      _initializedLease = lease;
      _initializing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_scannerLease, lease)) {
          _initialize(lease);
        }
      });
    }
  }

  void _releaseScannerLease() {
    _invalidateCapture();
    final lease = _scannerLease;
    _scannerLease = null;
    _initializedLease = null;
    if (lease != null) lease.release().ignore();
  }

  void _invalidateCapture() {
    _captureEpoch += 1;
    _captureCancellation?.cancel();
    _captureCancellation = null;
    _capturing = false;
  }

  bool _captureIsCurrent({
    required int epoch,
    required ObjectScannerController scanner,
    required ObjectScannerLease lease,
    required ModelCancellation cancellation,
  }) {
    return mounted &&
        epoch == _captureEpoch &&
        identical(_scanner, scanner) &&
        identical(_scannerLease, lease) &&
        lease.isCurrent &&
        identical(_captureCancellation, cancellation) &&
        !cancellation.isCancelled &&
        _cameraForeground;
  }

  Future<void> _initialize([ObjectScannerLease? requestedLease]) async {
    final scanner = _scanner;
    final lease = requestedLease ?? _scannerLease;
    if (scanner == null || lease == null) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'ฟีเจอร์กล้องยังไม่พร้อมใช้งานบนอุปกรณ์นี้';
        });
      }
      return;
    }
    try {
      final initialized = await lease.initialize();
      if (!initialized) return;
      if (!mounted ||
          !identical(_scanner, scanner) ||
          !identical(_scannerLease, lease) ||
          !lease.isCurrent ||
          _voice == null ||
          !_cameraForeground) {
        return;
      }
      setState(() {
        _initializing = false;
        _error = null;
      });
    } on CameraPracticeException catch (error) {
      if (!mounted ||
          !identical(_scanner, scanner) ||
          !identical(_scannerLease, lease) ||
          !lease.isCurrent ||
          _voice == null ||
          !_cameraForeground) {
        return;
      }
      setState(() {
        _initializing = false;
        _modelUnavailable = error.code == CameraFailureCode.modelUnavailable;
        _error = _cameraFailureText(error.code);
      });
    }
  }

  Future<void> _capture() async {
    final scanner = _scanner;
    final lease = _scannerLease;
    if (scanner == null || lease == null || !lease.isReady || _capturing) {
      return;
    }
    final captureEpoch = ++_captureEpoch;
    final cancellation = ModelCancellation();
    _captureCancellation = cancellation;
    setState(() {
      _capturing = true;
      _accepted = false;
      _error = null;
      _result = null;
    });
    try {
      final result = await scanner.captureAndClassify(
        cancellation: cancellation,
      );
      if (_captureIsCurrent(
        epoch: captureEpoch,
        scanner: scanner,
        lease: lease,
        cancellation: cancellation,
      )) {
        setState(() => _result = result);
      }
    } on CameraPracticeException catch (error) {
      if (_captureIsCurrent(
        epoch: captureEpoch,
        scanner: scanner,
        lease: lease,
        cancellation: cancellation,
      )) {
        setState(() => _error = _cameraFailureText(error.code));
      }
    } finally {
      if (_captureIsCurrent(
        epoch: captureEpoch,
        scanner: scanner,
        lease: lease,
        cancellation: cancellation,
      )) {
        setState(() => _capturing = false);
        _captureCancellation = null;
      }
    }
  }

  Future<void> _downloadModel() async {
    final scanner = _scanner;
    if (scanner == null || _downloading) return;
    final cancellation = ModelCancellation();
    _downloadCancellation = cancellation;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await scanner.downloadModel(cancellation: cancellation);
      if (!mounted) return;
      setState(() {
        _modelUnavailable = false;
        _initializing = true;
      });
      await _initialize();
    } on ModelLifecycleException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          ModelFailureCode.cancelled => 'ยกเลิกการดาวน์โหลดแล้ว',
          ModelFailureCode.checksumMismatch || ModelFailureCode.sizeMismatch =>
            'โมเดลไม่ผ่านการตรวจสอบและจะไม่ถูกเปิดใช้งาน',
          _ => 'ดาวน์โหลดโมเดลไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่',
        };
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
      }
    }
  }

  Future<void> _benchmarkModel() async {
    final scanner = _scanner;
    if (scanner == null || _benchmarking) return;
    setState(() {
      _benchmarking = true;
      _benchmarks = const [];
      _error = null;
    });
    try {
      final results = await scanner.benchmarkModel();
      if (mounted) setState(() => _benchmarks = results);
    } on ModelLifecycleException {
      if (mounted) {
        setState(
          () => _error = 'ไม่สามารถทดสอบประสิทธิภาพโมเดลบนเครื่องนี้ได้',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'การทดสอบประสิทธิภาพโมเดลไม่สำเร็จ');
      }
    } finally {
      if (mounted) setState(() => _benchmarking = false);
    }
  }

  Future<void> _accept() async {
    final scanner = _scanner;
    final result = _result;
    if (scanner == null || result == null || result.vocabulary == null) return;
    try {
      await scanner.accept(result);
      if (mounted) setState(() => _accepted = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'บันทึกคำศัพท์ไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  Future<void> _speak(String text) async {
    final session = routeVoiceSession;
    if (session == null) return;
    try {
      await session.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'device-default',
          speed: 0.9,
          mode: VoiceMode.practice,
          contentId: 'scanner:$text',
          contentType: 'object-scanner',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'ระบบอ่านออกเสียงไม่พร้อมใช้งาน');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final scanner = _scanner;
    if (scanner == null) return;
    if (state == AppLifecycleState.resumed) {
      _cameraForeground = true;
      final previousLease = _scannerLease;
      _bindDependencies();
      final lease = _scannerLease;
      if (lease == null || !identical(previousLease, lease)) return;
      lease
          .resume()
          .then((_) {
            if (mounted &&
                identical(_scannerLease, lease) &&
                lease.isCurrent &&
                _cameraForeground) {
              setState(() {
                _initializing = false;
                _error = null;
              });
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _error = 'เปิดกล้องอีกครั้งไม่สำเร็จ');
          });
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _cameraForeground = false;
      _invalidateCapture();
      _downloadCancellation?.cancel();
      _scannerLease?.pause().ignore();
    }
  }

  @override
  void dispose() {
    _downloadCancellation?.cancel();
    _releaseScannerLease();
    // Runtime-owned scanners are disposed by AppDependencies. Injected test
    // scanners are owned by the caller.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _scanner;
    if (scanner == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.objectScanner,
      );
    }
    if (_voice == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.voice,
      );
    }
    final result = _result;
    final scannerReady = _scannerLease?.isReady == true;
    return Scaffold(
      appBar: AppBar(title: const Text('สแกนวัตถุเป็นคำศัพท์')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: _initializing
                      ? const Center(child: CircularProgressIndicator())
                      : scannerReady
                      ? scanner.buildPreview()
                      : const Center(
                          child: Icon(Icons.no_photography_outlined, size: 64),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('object-scanner-capture-button'),
              onPressed: scannerReady && !_capturing ? _capture : null,
              icon: _capturing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(
                _capturing ? 'กำลังวิเคราะห์...' : 'ถ่ายภาพและวิเคราะห์',
              ),
            ),
            if (scannerReady) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey<String>('object-scanner-benchmark-model'),
                onPressed: _benchmarking || _capturing ? null : _benchmarkModel,
                icon: _benchmarking
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_outlined),
                label: Text(
                  _benchmarking
                      ? 'กำลังทดสอบ CPU/XNNPACK...'
                      : 'ทดสอบประสิทธิภาพ CPU/XNNPACK',
                ),
              ),
            ],
            if (_benchmarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                key: const ValueKey<String>('object-scanner-benchmark-result'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ผลทดสอบโมเดลบนเครื่องนี้'),
                      for (final result in _benchmarks)
                        Text(_benchmarkSummary(result)),
                    ],
                  ),
                ),
              ),
            ],
            if (_modelUnavailable) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey<String>('object-scanner-download-model'),
                onPressed: _downloading
                    ? () => _downloadCancellation?.cancel()
                    : _downloadModel,
                icon: Icon(_downloading ? Icons.stop : Icons.download),
                label: Text(
                  _downloading
                      ? 'ยกเลิกดาวน์โหลด'
                      : 'ดาวน์โหลดโมเดลที่ตรวจสอบแล้ว',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey<String>('object-scanner-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _ResultCard(
                result: result,
                accepted: _accepted,
                onSpeak: () => _speak(
                  result.vocabulary?.englishWord ??
                      (result.matchedClassification ?? result.primary).label,
                ),
                onAccept: result.vocabulary == null ? null : _accept,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cameraFailureText(CameraFailureCode code) => switch (code) {
    CameraFailureCode.permissionDenied =>
      'ไม่ได้รับสิทธิ์ใช้กล้อง จึงยังสแกนวัตถุไม่ได้',
    CameraFailureCode.permissionPermanentlyDenied =>
      'สิทธิ์กล้องถูกปิดถาวร กรุณาเปิดจากการตั้งค่าระบบ',
    CameraFailureCode.modelUnavailable =>
      'ยังไม่มีโมเดลที่ตรวจสอบแล้ว กรุณาดาวน์โหลดโมเดลเมื่อออนไลน์',
    CameraFailureCode.cancelled => 'ยกเลิกการสแกนแล้ว',
    CameraFailureCode.invalidImage => 'รูปภาพนี้ไม่สามารถนำมาวิเคราะห์ได้',
    CameraFailureCode.captureFailed => 'ถ่ายภาพหรือวิเคราะห์ไม่สำเร็จ',
    CameraFailureCode.unavailable ||
    CameraFailureCode.initializationFailed => 'กล้องไม่พร้อมใช้งานบนอุปกรณ์นี้',
  };

  String _benchmarkSummary(ModelBenchmarkResult result) {
    final medianMs = (result.medianMicros / 1000).toStringAsFixed(1);
    final p90Ms = (result.p90Micros / 1000).toStringAsFixed(1);
    final peakMb = (result.peakWorkingSetBytes / (1024 * 1024)).toStringAsFixed(
      1,
    );
    return '${result.delegate.name.toUpperCase()} n=${result.sampleSize} '
        'median=$medianMs ms p90=$p90Ms ms peakRSS=$peakMb MB';
  }
}

final class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.accepted,
    required this.onSpeak,
    required this.onAccept,
  });

  final ObjectScanResult result;
  final bool accepted;
  final VoidCallback onSpeak;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final vocabulary = result.vocabulary;
    final displayedClassification =
        result.matchedClassification ?? result.primary;
    final confidence = (displayedClassification.confidence * 100)
        .toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vocabulary?.englishWord ?? displayedClassification.label,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (vocabulary != null)
              Text(
                vocabulary.thaiTranslation,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            Text('ความมั่นใจจากโมเดล: $confidence%'),
            Text(
              'โมเดล ${result.modelId} รุ่น ${result.modelVersion}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (vocabulary == null) ...[
              const SizedBox(height: 8),
              const Text(
                'พบวัตถุจริง แต่ยังไม่มีคำแปลที่ตรวจสอบแล้วในคลังคำศัพท์',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('ฟังเสียง'),
                ),
                const SizedBox(width: 8),
                if (onAccept != null)
                  FilledButton.icon(
                    onPressed: accepted ? null : onAccept,
                    icon: Icon(accepted ? Icons.check : Icons.add),
                    label: Text(accepted ? 'บันทึกแล้ว' : 'เพิ่มเข้าคลัง'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
