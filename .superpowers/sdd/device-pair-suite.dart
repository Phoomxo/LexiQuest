import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../../integration_test/field_trial_feature_controls_test.dart' as controls;
import '../../integration_test/field_trial_media_smoke_test.dart' as media;
import '../../test/features/learning/pair_matching/pair_active_timer_test.dart' as suite0;
import '../../test/features/learning/pair_matching/pair_board_accessibility_test.dart' as suite1;
import '../../test/features/learning/pair_matching/pair_board_view_test.dart' as suite2;
import '../../test/features/learning/pair_matching/pair_configured_disposition_test.dart' as suite3;
import '../../test/features/learning/pair_matching/pair_matching_atomic_start_test.dart' as suite4;
import '../../test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart' as suite5;
import '../../test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart' as suite6;
import '../../test/features/learning/pair_matching/pair_matching_configuration_test.dart' as suite7;
import '../../test/features/learning/pair_matching/pair_matching_density_preference_test.dart' as suite8;
import '../../test/features/learning/pair_matching/pair_matching_engine_test.dart' as suite9;
import '../../test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart' as suite10;
import '../../test/features/learning/pair_matching/pair_matching_experience_host_test.dart' as suite11;
import '../../test/features/learning/pair_matching/pair_matching_idempotency_test.dart' as suite12;
import '../../test/features/learning/pair_matching/pair_matching_owner_command_test.dart' as suite13;
import '../../test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart' as suite14;
import '../../test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart' as suite15;
import '../../test/features/learning/pair_matching/pair_matching_plan_test.dart' as suite16;
import '../../test/features/learning/pair_matching/pair_matching_result_view_test.dart' as suite17;
import '../../test/features/learning/pair_matching/pair_matching_session_purpose_test.dart' as suite18;
import '../../test/features/learning/pair_matching/pair_matching_source_composer_test.dart' as suite19;
import '../../test/features/learning/pair_matching/pair_matching_source_property_test.dart' as suite20;
import '../../test/features/learning/pair_matching/pair_measurement_boundary_test.dart' as suite21;
import '../../test/features/learning/pair_matching/pair_practice_replay_test.dart' as suite22;
import '../../test/features/learning/pair_matching/pair_repair_policy_test.dart' as suite23;
import '../../test/features/learning/pair_matching/pair_review_deferral_test.dart' as suite24;
import '../../test/features/learning/pair_matching/pair_star_policy_test.dart' as suite25;
import '../../test/features/learning/pair_matching/pair_support_classification_test.dart' as suite26;
import '../../test/features/learning/pair_matching/pair_timeout_race_test.dart' as suite27;
import '../../test/features/learning/pair_matching/pair_timeout_recovery_test.dart' as suite28;
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('feature-controls', controls.main);
  group('media-fallback', media.main);
  group('pair_active_timer_test.dart', suite0.main);
  group('pair_board_accessibility_test.dart', suite1.main);
  group('pair_board_view_test.dart', suite2.main);
  group('pair_configured_disposition_test.dart', suite3.main);
  group('pair_matching_atomic_start_test.dart', suite4.main);
  group('pair_matching_checkpoint_codec_test.dart', suite5.main);
  group('pair_matching_compatibility_rollout_test.dart', suite6.main);
  group('pair_matching_configuration_test.dart', suite7.main);
  group('pair_matching_density_preference_test.dart', suite8.main);
  group('pair_matching_engine_test.dart', suite9.main);
  group('pair_matching_evidence_contract_test.dart', suite10.main);
  group('pair_matching_experience_host_test.dart', suite11.main);
  group('pair_matching_idempotency_test.dart', suite12.main);
  group('pair_matching_owner_command_test.dart', suite13.main);
  group('pair_matching_owner_upgrade_auth_test.dart', suite14.main);
  group('pair_matching_owner_upgrade_test.dart', suite15.main);
  group('pair_matching_plan_test.dart', suite16.main);
  group('pair_matching_result_view_test.dart', suite17.main);
  group('pair_matching_session_purpose_test.dart', suite18.main);
  group('pair_matching_source_composer_test.dart', suite19.main);
  group('pair_matching_source_property_test.dart', suite20.main);
  group('pair_measurement_boundary_test.dart', suite21.main);
  group('pair_practice_replay_test.dart', suite22.main);
  group('pair_repair_policy_test.dart', suite23.main);
  group('pair_review_deferral_test.dart', suite24.main);
  group('pair_star_policy_test.dart', suite25.main);
  group('pair_support_classification_test.dart', suite26.main);
  group('pair_timeout_race_test.dart', suite27.main);
  group('pair_timeout_recovery_test.dart', suite28.main);
  testWidgets('DEVICE_SUITE_FINAL_SENTINEL', (tester) async {
    binding.reportData = {
      'suite': 'pair-and-shell',
      'testResults': binding.results.map((key, value) => MapEntry(key, value.toString())),
      'sourceFiles': ["test/features/learning/pair_matching/pair_active_timer_test.dart","test/features/learning/pair_matching/pair_board_accessibility_test.dart","test/features/learning/pair_matching/pair_board_view_test.dart","test/features/learning/pair_matching/pair_configured_disposition_test.dart","test/features/learning/pair_matching/pair_matching_atomic_start_test.dart","test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart","test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart","test/features/learning/pair_matching/pair_matching_configuration_test.dart","test/features/learning/pair_matching/pair_matching_density_preference_test.dart","test/features/learning/pair_matching/pair_matching_engine_test.dart","test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart","test/features/learning/pair_matching/pair_matching_experience_host_test.dart","test/features/learning/pair_matching/pair_matching_idempotency_test.dart","test/features/learning/pair_matching/pair_matching_owner_command_test.dart","test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart","test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart","test/features/learning/pair_matching/pair_matching_plan_test.dart","test/features/learning/pair_matching/pair_matching_result_view_test.dart","test/features/learning/pair_matching/pair_matching_session_purpose_test.dart","test/features/learning/pair_matching/pair_matching_source_composer_test.dart","test/features/learning/pair_matching/pair_matching_source_property_test.dart","test/features/learning/pair_matching/pair_measurement_boundary_test.dart","test/features/learning/pair_matching/pair_practice_replay_test.dart","test/features/learning/pair_matching/pair_repair_policy_test.dart","test/features/learning/pair_matching/pair_review_deferral_test.dart","test/features/learning/pair_matching/pair_star_policy_test.dart","test/features/learning/pair_matching/pair_support_classification_test.dart","test/features/learning/pair_matching/pair_timeout_race_test.dart","test/features/learning/pair_matching/pair_timeout_recovery_test.dart"],
    };
    expect(binding.results.length, greaterThan(20));
  });
  unawaited(publishService());
}
Future<void> publishService() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null || uri.host != '127.0.0.1') throw StateError('Local VM service unavailable');
  await File('${Directory.systemTemp.path}/lexiquest-core-service-20260907.json')
      .writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}
