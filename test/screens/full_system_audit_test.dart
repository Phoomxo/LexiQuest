import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';
import 'package:vocab_learning_app/screens/cefr_diagnostic_test_screen.dart';
import 'package:vocab_learning_app/screens/boss_battle_screen.dart';
import 'package:vocab_learning_app/screens/learning_world_map_screen.dart';
import 'package:vocab_learning_app/screens/phonetic_explorer_screen.dart';
import 'package:vocab_learning_app/services/cognitive_attention_analyzer_service.dart';
import 'package:vocab_learning_app/services/dynamic_story_contextualizer_service.dart';
import 'package:vocab_learning_app/services/rapid_naming_speed_service.dart';
import 'package:vocab_learning_app/services/brahmawong_research_analytics_service.dart';
import 'package:vocab_learning_app/services/anki_dictionary_exporter_service.dart';
import 'package:vocab_learning_app/services/auth_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuditFakeVoiceProvider implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

void main() {
  group('LexiQuest Master Full System Audit (All Sections & Research Engines)', () {
    // -------------------------------------------------------------
    // Section 1: Authentication & Error Translation Audit
    // -------------------------------------------------------------
    testWidgets('Section 1 Audit: LoginScreen renders Thai UI & Guest Mode button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('เข้าสู่ระบบ'), findsWidgets);
      expect(find.textContaining('Guest Mode'), findsOneWidget);
    });

    testWidgets('Section 1 Audit: RegisterScreen & OTPScreen render verification UI', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('สมัครสมาชิก'), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(2)); // Email & Password
    });

    test('Section 1 Audit: AuthService translates Firebase errors to Thai', () {
      final exc = FirebaseAuthException(code: 'email-already-in-use');
      final msg = AuthService.getErrorMessage(exc);
      expect(msg, contains('อีเมลนี้ถูกใช้งานในระบบแล้ว'));
    });

    // -------------------------------------------------------------
    // Section 2: Mode Navigation & Main Navigation Audit
    // -------------------------------------------------------------
    testWidgets('Section 2 Audit: ChooseModeScreen renders mode grid and Avatar Gear button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ChooseModeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('เลือกรูปแบบการเรียนรู้'), findsOneWidget);
      expect(find.textContaining('Avatar Gear'), findsOneWidget);
    });

    testWidgets('Section 2 Audit: MainNavigationScreen switches across all 4 primary tabs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pumpAndSettle();

      // Tab 0: Learn
      expect(find.text('เรียนรู้'), findsOneWidget);

      // Tab 1: Analytics
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.byType(MasteryDashboardScreen), findsOneWidget);

      // Tab 2: Weakness Clinic
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);

      // Tab 3: Achievements
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Section 3: Curriculum & Diagnostic Assessment Audit
    // -------------------------------------------------------------
    testWidgets('Section 3 Audit: CefrSelectionScreen renders tabs & level chips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CefrSelectionScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('คลังคำศัพท์ CEFR'), findsOneWidget);
    });

    testWidgets('Section 3 Audit: CefrDiagnosticTestScreen executes assessment flow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CefrDiagnosticTestScreen()));
      await tester.pumpAndSettle();

      expect(find.text('แบบทดสอบวัดระดับ CEFR (1/5)'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Section 4: Cognitive & Research Analytics Engines Audit
    // -------------------------------------------------------------
    test('Section 4 Audit: CognitiveAttentionAnalyzer computes CLI and hesitation', () {
      final reportNormal = CognitiveAttentionAnalyzerService.analyzeDwellTime(
        word: 'perseverance',
        dwellTimeMs: 250,
      );
      expect(reportNormal.isHesitated, false);
      expect(reportNormal.cognitiveLoadIndex, equals(0.25));

      final reportHesitated = CognitiveAttentionAnalyzerService.analyzeDwellTime(
        word: 'perseverance',
        dwellTimeMs: 800,
      );
      expect(reportHesitated.isHesitated, true);
      expect(reportHesitated.recommendation, contains('พบความลังเล'));
    });

    test('Section 4 Audit: DynamicStoryContextualizer generates target stories', () {
      final story = DynamicStoryContextualizerService.generateStory('resilience');
      expect(story.targetWord, equals('resilience'));
      expect(story.storyText, contains('resilience'));
    });

    test('Section 4 Audit: RapidNamingSpeedService computes RAN score and rating', () {
      final result = RapidNamingSpeedService.evaluateSpeed(
        targetWord: 'challenge',
        responseTimeMs: 350,
      );
      expect(result.automaticityScore, equals(100));
      expect(result.fluencyRating, contains('Ultra-Fast'));
    });

    test('Section 4 Audit: BrahmawongResearchAnalytics computes E1/E2 efficiency', () {
      final ratio = BrahmawongResearchAnalyticsService.evaluateEfficiency(
        processQuizScores: [85.0, 90.0, 80.0],
        maxProcessScore: 100.0,
        postTestScores: [88.0],
        maxPostTestScore: 100.0,
        preTestScores: [50.0],
      );
      expect(ratio.e1ProcessEfficiency, greaterThanOrEqualTo(80.0));
      expect(ratio.e2ProductEfficiency, equals(88.0));
      expect(ratio.satisfies8080Standard, true);
    });

    // -------------------------------------------------------------
    // Section 5: RPG Gamification & Boss Battle Audit
    // -------------------------------------------------------------
    testWidgets('Section 5 Audit: AvatarEquipmentScreen displays 4 slots & stat buffs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AvatarEquipmentScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vocabulary Warrior'), findsOneWidget);
      expect(find.textContaining('Damage: +'), findsOneWidget);
    });

    testWidgets('Section 5 Audit: BossBattleScreen renders HP bar & boss mechanics', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BossBattleScreen(
            bossName: 'Vocab Titan',
            initialBossHp: 100,
            questions: [
              {'word': 'ephemeral', 'translation': 'ชั่วคราว'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vocab Titan'), findsOneWidget);
      expect(find.text('HP: 100 / 100'), findsOneWidget);
    });

    testWidgets('Section 5 Audit: LearningWorldMapScreen renders world map stages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LearningWorldMapScreen()));
      await tester.pumpAndSettle();

      expect(find.text('แผนที่ท่องโลกคำศัพท์ (World Map Campaign)'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Section 6: Phonetics, Weakness Clinic & Exporter Audit
    // -------------------------------------------------------------
    testWidgets('Section 6 Audit: PhoneticExplorerScreen renders IPA chart & guides', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: PhoneticExplorerScreen(voiceProvider: AuditFakeVoiceProvider())),
      );
      await tester.pumpAndSettle();

      expect(find.text('สำรวจสัทอักษร IPA (Phonetic Explorer)'), findsOneWidget);
    });

    test('Section 6 Audit: AnkiDictionaryExporter exports TSV format package', () {
      final tsv = AnkiDictionaryExporterService.exportToAnkiTxt([
        const VocabularyCardExport(
          word: 'ephemeral',
          ipa: '/əˈfem.ər.əl/',
          translation: 'ชั่วคราว',
          exampleSentence: 'Life is ephemeral.',
        ),
      ]);
      expect(tsv, contains('ephemeral\t/əˈfem.ər.əl/\tชั่วคราว\tLife is ephemeral.'));
    });
  });
}
