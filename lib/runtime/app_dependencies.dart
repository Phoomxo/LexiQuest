import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_runtime_status.dart';
import 'field_feature_registry.dart';

final class AppDependencies {
  AppDependencies({
    required this.runtimeStatus,
    required this.config,
    required this.guestSessionService,
    this.buildInfo = const AppBuildInfo.fromEnvironment(),
    this.fieldFeatures = const BuildFieldFeatureRegistry.fieldDefaults(),
    this.database,
    this.localOwners,
    this.upgradeGuestOwner,
    this.vocabulary,
    this.vocabularyImporter,
    this.disposeResources,
  });

  final AppRuntimeStatus runtimeStatus;
  final AppConfig? config;
  final GuestSessionService guestSessionService;
  final AppBuildInfo buildInfo;
  final FieldFeatureRegistry fieldFeatures;
  final AppDatabase? database;
  final LocalOwnerRepository? localOwners;
  final UpgradeGuestOwner? upgradeGuestOwner;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? vocabularyImporter;
  final Future<void> Function()? disposeResources;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= disposeResources?.call() ?? Future<void>.value();
  }

  @override
  String toString() => 'AppDependencies';
}

final class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppDependenciesScope>()
        ?.dependencies;
  }

  static AppDependencies of(BuildContext context) {
    final dependencies = maybeOf(context);
    assert(
      dependencies != null,
      'AppDependenciesScope was not found in the widget tree.',
    );
    return dependencies!;
  }

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) {
    return !identical(dependencies, oldWidget.dependencies);
  }
}
