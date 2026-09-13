import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';

void main() {
  const policy = SessionConfigurationPolicy();
  const limits = SessionConfigurationProtocolLimits.standard();
  final registry = buildLessonModeRegistry(
    matchingDeliveryState: LessonModeDeliveryState.enabled,
    handwritingDeliveryState: LessonModeDeliveryState.enabled,
  );
  for (final mode in LessonMode.values) {
    test('B06 matrix ${mode.name} admits exact config and rejects stale authority', () {
      final registration = registry.resolve(mode)!;
      final draft = policy.defaultsFor(registration: registration, limits: limits);
      final configuration = policy.validate(
        draft: draft, registration: registration, limits: limits,
        ownerId: 'matrix-owner', availablePackIdentities: const [],
      );
      final restored = SessionConfiguration.fromStableSerialization(configuration.stableSerialization);
      expect(policy.revalidate(
        configuration: restored, registration: registration, limits: limits,
        ownerId: 'matrix-owner', availablePackIdentities: const [],
      ).stableSerialization, configuration.stableSerialization);
      expect(() => policy.revalidate(
        configuration: restored, registration: registration, limits: limits,
        ownerId: 'replacement-owner', availablePackIdentities: const [],
      ), throwsA(isA<SessionConfigurationResetRequired>()));
      final off = LessonModeRegistration(
        adapter: registration.adapter, feature: registration.feature,
        productionEntryId: registration.productionEntryId,
        routeName: registration.routeName,
        deliveryState: LessonModeDeliveryState.implementedOff,
      );
      expect(() => policy.validate(
        draft: draft, registration: off, limits: limits,
        ownerId: 'matrix-owner', availablePackIdentities: const [],
      ), throwsA(isA<SessionConfigurationResetRequired>()));
      expect(LessonModeRegistry(const []).resolve(mode), isNull);
      final capabilities = (registration.adapter as SessionConfigurableLessonModeAdapter).sessionConfigurationCapabilities;
      print('B06_MODE_MATRIX:${jsonEncode({
        'mode': mode.name, 'route': registration.routeName,
        'minItems': capabilities.minimumItemCount,
        'maxItems': capabilities.maximumItemCount,
        'defaultItems': configuration.itemCount,
        'directions': capabilities.directions.map((d) => d.name).toList(),
        'timed': capabilities.supportsTimed,
        'untimedActiveEffortBounded': capabilities.supportsUntimedAlternative,
        'packSelection': capabilities.supportsPackSelection,
        'handwritingConfigurationUsedByRoute': false,
      })}');
    });
  }
}
