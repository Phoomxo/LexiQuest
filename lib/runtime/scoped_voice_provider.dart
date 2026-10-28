import 'package:flutter/widgets.dart';

import '../voice/voice_provider.dart';
import 'app_dependencies.dart';

/// Resolves the [VoiceProvider] for [context], preferring [override] when given.
VoiceProvider resolveScopedVoiceProvider(
  BuildContext context,
  VoiceProvider? override,
) {
  return override ?? AppDependenciesScope.of(context).voice;
}
