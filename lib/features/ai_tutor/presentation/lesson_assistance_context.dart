import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../learning/domain/answer_feedback.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/lesson_session_state.dart';
import '../../learning/domain/session_configuration.dart';
import 'menu_action_binding.dart';

/// Optional read-only projection. It owns no lesson controls, scores or storage.
final class LessonAssistanceContext extends StatelessWidget {
  const LessonAssistanceContext({
    super.key,
    required this.ownerId,
    required this.state,
    required this.child,
    this.direction,
    this.feedback,
  });
  final String? ownerId;
  final LessonSessionState state;
  final SessionDirection? direction;
  final AnswerFeedback? feedback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registry = MenuActionScope.maybeOf(context);
    if (registry == null) return child;
    final committed = feedback;
    final data = <String, Object?>{
      'mode': state.mode.id,
      'languages': ['en', 'th'],
      'direction': direction?.name ?? 'not_configured',
      'status': state.status.name,
      'itemCount': state.itemCount,
      'committedResponses': state.committedResponseCount,
      'guidance': _guidance(state.mode),
      'assistance':
          'Explain the method or last committed feedback. Learner answers in the original exercise. This context cannot submit, score or save.',
      if (committed != null && state.committedResponseCount > 0)
        'lastCommittedFeedback': {
          'isCorrect': committed.isCorrect,
          'correctAnswer': committed.canonicalCorrectAnswer,
          'correctAnswerTruncated': false,
        },
    };
    return _LessonAssistanceScope(
      ownerId: ownerId,
      child: MenuActionBinding(
        id: 'lesson/assistance',
        label: 'บริบทสำหรับช่วยอธิบายบทเรียน',
        ownerId: ownerId,
        onInvoke: null,
        readValue: ownerId == null ? null : _encodeContext(data),
        child: child,
      ),
    );
  }
}

final class _LessonAssistanceScope extends InheritedWidget {
  const _LessonAssistanceScope({required this.ownerId, required super.child});
  final String? ownerId;
  @override
  bool updateShouldNotify(_LessonAssistanceScope oldWidget) =>
      oldWidget.ownerId != ownerId;
}

/// Reads the actual visible committed result from native-mode feedback panels.
/// No callback, score write or answer submission is exposed to the assistant.
final class CommittedFeedbackAssistance extends StatelessWidget {
  const CommittedFeedbackAssistance({
    super.key,
    required this.feedback,
    required this.child,
  });
  final AnswerFeedback feedback;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LessonAssistanceScope>();
    if (scope == null) return child;
    return MenuActionBinding(
      id: 'lesson/committed-feedback',
      label: 'ผลตอบที่บันทึกและแสดงอยู่',
      ownerId: scope.ownerId,
      onInvoke: null,
      readValue: scope.ownerId == null
          ? null
          : _encodeContext({
              'source': 'visible_committed_feedback',
              'lastCommittedFeedback': {
                'isCorrect': feedback.isCorrect,
                'correctAnswer': feedback.canonicalCorrectAnswer,
                'correctAnswerTruncated': false,
              },
            }),
      child: child,
    );
  }
}

String _encodeContext(Map<String, Object?> data) {
  // Stay below the registry's limit without cutting JSON or a Unicode rune.
  var encoded = jsonEncode(data);
  final last = data['lastCommittedFeedback'] as Map<String, Object?>?;
  while (encoded.length > 980 && last != null) {
    final runes = (last['correctAnswer'] as String).runes.toList();
    last['correctAnswer'] = String.fromCharCodes(runes.take(runes.length ~/ 2));
    last['correctAnswerTruncated'] = true;
    encoded = jsonEncode(data);
  }
  return encoded;
}

String _guidance(LessonMode mode) => switch (mode) {
  LessonMode.associativeReading =>
    'ช่วยอธิบายขั้นตอนอ่านและการเชื่อมคำกับบริบทของเรื่อง',
  LessonMode.meaningQuiz =>
    'ช่วยอธิบายวิธีพิจารณาความหมายและตัวเลือกตามทิศทางของโจทย์',
  LessonMode.typedRecall => 'ช่วยแนะนำวิธีนึกคำและตรวจการสะกดหลังผู้เรียนตอบ',
  LessonMode.definitionQuiz => 'ช่วยอธิบายวิธีอ่านคำจำกัดความและแยกชนิดของคำ',
  LessonMode.cloze => 'ช่วยอธิบายการใช้บริบทและโครงสร้างประโยคเพื่อเติมคำ',
  LessonMode.matching =>
    'ช่วยแนะนำวิธีเชื่อมคำกับความหมาย โดยผู้เรียนจับคู่เอง',
  LessonMode.flashcard => 'ช่วยแนะนำการนึกคำก่อนเปิดเฉลยและการทบทวนตามรอบ',
  LessonMode.handwritingScratchpad =>
    'ช่วยอธิบายการฝึกเขียนและตรวจตัวเอง ไม่อ้างว่าประเมินลายมือจากข้อความนี้',
  LessonMode.dictation =>
    'ช่วยแนะนำการฟังแบ่งเสียงและตรวจการสะกดหลังตอบ ไม่อ้างว่าได้ยินเสียงจากบริบทข้อความ',
  LessonMode.speaking =>
    'ช่วยอธิบายการออกเสียงด้วยข้อความ ไม่อ้างผลประเมินเสียงที่ยังไม่ได้รับ',
  LessonMode.shadowing =>
    'ช่วยอธิบายวิธีฟังและพูดตามจังหวะ ไม่อ้างว่าได้ฟังเสียงผู้เรียน',
  LessonMode.cefrReading => 'ช่วยแนะนำกลยุทธ์อ่านและตีความคำในบทความตามระดับ',
  LessonMode.sentenceScramble =>
    'ช่วยอธิบายตำแหน่งประธาน กริยา และส่วนขยายในการเรียงประโยค',
  LessonMode.wordScramble =>
    'ช่วยแนะนำการสังเกตรูปคำและกลุ่มตัวอักษรเพื่อเรียงคำ',
};
