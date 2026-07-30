import 'dart:async';

import 'package:flutter/material.dart';

import '../features/device_model/domain/model_lifecycle.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class ObjectScannerScreen extends StatefulWidget {
  const ObjectScannerScreen({super.key, this.scanner, this.voiceProvider});

  final ObjectScannerController? scanner;
  final VoiceProvider? voiceProvider;

  @override
  State<ObjectScannerScreen> createState() => _ObjectScannerScreenState();
}

class _ObjectScannerScreenState extends State<ObjectScannerScreen>
    with WidgetsBindingObserver {
  ObjectScannerController? _scanner;
  late final VoiceProvider _voice;
  bool _ownsVoice = false;
  bool _initializing = true;
  bool _capturing = false;
  bool _downloading = false;
  bool _modelUnavailable = false;
  bool _accepted = false;
  String? _error;
  ObjectScanResult? _result;
  ModelCancellation? _cancellation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = widget.voiceProvider ?? VoiceServiceFactory.create();
    _ownsVoice = widget.voiceProvider == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scanner != null) return;
    _scanner =
        widget.scanner ?? AppDependenciesScope.maybeOf(context)?.objectScanner;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final scanner = _scanner;
    if (scanner == null) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'ฟีเจอร์กล้องยังไม่พร้อมใช้งานบนอุปกรณ์นี้';
        });
      }
      return;
    }
    try {
      await scanner.initialize();
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = null;
        });
      }
    } on CameraPracticeException catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _modelUnavailable = error.code == CameraFailureCode.modelUnavailable;
          _error = _cameraFailureText(error.code);
        });
      }
    }
  }

  Future<void> _capture() async {
    final scanner = _scanner;
    if (scanner == null || _capturing) return;
    final cancellation = ModelCancellation();
    _cancellation = cancellation;
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
      if (mounted) setState(() => _result = result);
    } on CameraPracticeException catch (error) {
      if (mounted) setState(() => _error = _cameraFailureText(error.code));
    } finally {
      if (mounted) setState(() => _capturing = false);
      _cancellation = null;
    }
  }

  Future<void> _downloadModel() async {
    final scanner = _scanner;
    if (scanner == null || _downloading) return;
    final cancellation = ModelCancellation();
    _cancellation = cancellation;
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
      _cancellation = null;
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
    try {
      await _voice.speak(
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
    final scanner = _scanner;
    if (scanner == null) return;
    if (state == AppLifecycleState.resumed) {
      scanner
          .resume()
          .then((_) {
            if (mounted) setState(() => _error = null);
          })
          .catchError((_) {
            if (mounted) setState(() => _error = 'เปิดกล้องอีกครั้งไม่สำเร็จ');
          });
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _cancellation?.cancel();
      scanner.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellation?.cancel();
    final scanner = _scanner;
    if (scanner != null) unawaited(scanner.pause());
    _voice.stop();
    if (_ownsVoice && _voice is ManagedVoiceService) {
      _voice.dispose();
    }
    // Runtime-owned scanners are disposed by AppDependencies. Injected test
    // scanners are owned by the caller.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _scanner;
    final result = _result;
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
                      : scanner?.isReady ?? false
                      ? scanner!.buildPreview()
                      : const Center(
                          child: Icon(Icons.no_photography_outlined, size: 64),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('object-scanner-capture-button'),
              onPressed: scanner?.isReady == true && !_capturing
                  ? _capture
                  : null,
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
            if (_modelUnavailable) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey<String>('object-scanner-download-model'),
                onPressed: _downloading
                    ? () => _cancellation?.cancel()
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
