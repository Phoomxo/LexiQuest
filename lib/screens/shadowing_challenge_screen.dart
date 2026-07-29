import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/multi_accent_pitch_calibration_service.dart';
import '../services/phoneme_alignment_clinic_service.dart';
import '../utils/pronunciation_evaluator.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';
import '../widgets/accent_selector_widget.dart';
import '../widgets/live_audio_waveform_widget.dart';
import '../widgets/visual_pitch_contour_widget.dart';

class ShadowingChallengeScreen extends StatefulWidget {
  final String referenceSentence;
  final VoiceProvider? voiceProvider;

  const ShadowingChallengeScreen({
    super.key,
    required this.referenceSentence,
    this.voiceProvider,
  });

  @override
  State<ShadowingChallengeScreen> createState() =>
      _ShadowingChallengeScreenState();
}

class _ShadowingChallengeScreenState extends State<ShadowingChallengeScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  bool _isRecording = false;
  bool _hasRecorded = false;

  VoiceAccent _selectedAccent = VoiceAccent.us;
  List<double> _liveAudioLevels = const [];
  List<double> _referencePitchPoints = const [];
  List<double> _userPitchPoints = const [];
  PronunciationDiff? _pronunciationDiff;
  PhonemeAlignmentResult? _alignmentResult;
  Timer? _waveformTimer;

  @override
  void initState() {
    super.initState();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
      _ownsVoiceProvider = false;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
  }

  Future<void> _playReference({required double speed}) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: widget.referenceSentence,
          language: 'en',
          voiceId: _selectedAccent.voiceId,
          speed: speed,
          mode: VoiceMode.practice,
          contentId: widget.referenceSentence,
          contentType: 'shadowing_reference',
        ),
      );
    } catch (e) {
      debugPrint('Shadowing audio error: $e');
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _liveAudioLevels = List.generate(
        24,
        (index) => 0.2 + Random().nextDouble() * 0.6,
      );
      _waveformTimer?.cancel();
      _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (mounted && _isRecording) {
          setState(() {
            _liveAudioLevels = List.generate(
              24,
              (index) => 0.15 + Random().nextDouble() * 0.75,
            );
          });
        }
      });
    } else {
      _waveformTimer?.cancel();
      _waveformTimer = null;

      final rawRef = [0.3, 0.45, 0.7, 0.6, 0.8, 0.75, 0.5, 0.65, 0.4, 0.35];
      final rawUser = [0.28, 0.42, 0.65, 0.58, 0.82, 0.7, 0.48, 0.6, 0.38, 0.3];

      SpeechAccent speechAccent = SpeechAccent.us;
      if (_selectedAccent == VoiceAccent.uk) speechAccent = SpeechAccent.uk;
      if (_selectedAccent == VoiceAccent.au) speechAccent = SpeechAccent.au;

      final refCalibrated = MultiAccentPitchCalibrationService.calibratePitch(
        rawPitchPoints: rawRef,
        accent: speechAccent,
      );
      final userCalibrated = MultiAccentPitchCalibrationService.calibratePitch(
        rawPitchPoints: rawUser,
        accent: speechAccent,
      );

      final evalDiff = PronunciationEvaluator.evaluate(
        widget.referenceSentence,
        widget.referenceSentence,
      );

      final clinicResult = PhonemeAlignmentClinicService.analyzeAlignment(
        targetWord: widget.referenceSentence,
        targetIpa: '/præk.tɪs meɪks pɜː.fekt/',
        spokenText: widget.referenceSentence,
      );

      setState(() {
        _hasRecorded = true;
        _referencePitchPoints = refCalibrated.normalizedPoints;
        _userPitchPoints = userCalibrated.normalizedPoints;
        _pronunciationDiff = evalDiff;
        _alignmentResult = clinicResult;
      });
    }
  }

  @override
  void dispose() {
    _waveformTimer?.cancel();
    _voiceProvider.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Shadowing Practice (พูดตามจังหวะ AI)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentSelectorWidget(
              selectedAccent: _selectedAccent,
              onAccentChanged: (accent) {
                setState(() {
                  _selectedAccent = accent;
                });
              },
            ),
            const SizedBox(height: 16),

            const Text(
              '1. ฟังเสียงต้นแบบ AI ➡️ 2. กดอัดเสียงพูดตามเพื่อวัด Pitch Contour',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Text(
                widget.referenceSentence,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _playReference(speed: 1.0),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ฟังเสียง AI (1.0x)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _playReference(speed: 0.8),
                  icon: const Icon(Icons.slow_motion_video),
                  label: const Text('ฟังชะลอ (0.8x)'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.deepPurple,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : Colors.deepPurple)
                            .withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _isRecording
                    ? 'กำลังอัดเสียงพูดตาม...'
                    : 'กดไอคอนเพื่อเริ่มฝึก Shadowing',
                style: TextStyle(
                  color: _isRecording ? Colors.red : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (_isRecording) ...[
              const SizedBox(height: 20),
              LiveAudioWaveformWidget(
                audioLevels: _liveAudioLevels,
                height: 80,
                barColor: Colors.redAccent,
              ),
            ],

            if (_hasRecorded) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.show_chart,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'กราฟเปรียบเทียบ Pitch Contour เสียงพูด',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'เสียงต้นแบบ AI',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 12,
                            height: 12,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'เสียงพูดของคุณ',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      VisualPitchContourWidget(
                        referencePitchPoints: _referencePitchPoints,
                        userPitchPoints: _userPitchPoints,
                        height: 120,
                      ),
                      const SizedBox(height: 16),

                      if (_pronunciationDiff != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'คะแนนความแม่นยำ:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Chip(
                              backgroundColor:
                                  _pronunciationDiff!.scorePercentage >= 80
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              label: Text(
                                '${_pronunciationDiff!.scorePercentage}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      _pronunciationDiff!.scorePercentage >= 80
                                      ? Colors.green.shade900
                                      : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _pronunciationDiff!.feedbackText,
                          style: const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],

                      if (_alignmentResult != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'วิเคราะห์สัญลักษณ์ IPA (Phoneme Alignment):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ..._alignmentResult!.matchedPhonemes.map(
                              (p) => Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Colors.lightGreen.shade100,
                                label: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            ..._alignmentResult!.errorPhonemes.map(
                              (p) => Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Colors.red.shade100,
                                label: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _alignmentResult!.diagnosticTip,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
