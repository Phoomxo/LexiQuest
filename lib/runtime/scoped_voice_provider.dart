import 'package:flutter/widgets.dart';

import '../voice/voice_provider.dart';
import '../features/voice/application/voice_use_cases.dart';
import 'app_dependencies.dart';

/// Resolves the [VoiceProvider] for [context], preferring [override] when given.
/// Falls back to the [VoiceUseCases] wired in [AppDependencies] when available.
VoiceProvider? resolveScopedVoiceProvider(
  BuildContext context,
  VoiceProvider? override,
) {
  if (override != null) return override;
  final deps = AppDependenciesScope.maybeOf(context);
  return deps?.voice?.provider;
}
