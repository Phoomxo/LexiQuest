import '../../research/domain/research_participation_permit.dart';
import '../../today_hub/application/today_hub_use_cases.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_world_catalog.dart';
import 'adventure_diagnostics.dart';
import 'adventure_rollout_gate.dart';

abstract interface class AdventurePresentationPreferenceReader {
  Future<TodayExperiencePresentation?> readForOwner(String ownerId);
}

typedef AdventureEntryAttemptIdFactory = String Function();

final class AdventureEntryUseCases implements AdventureProductEntryResolver {
  const AdventureEntryUseCases({
    required this.rollout,
    required this.catalog,
    required this.todayHubIdentity,
    required this.learningIdentity,
    this.preferences,
    this.diagnostics,
  });

  final AdventureRolloutGate rollout;
  final AdventureWorldCatalog catalog;
  final Object todayHubIdentity;
  final Object learningIdentity;
  final AdventurePresentationPreferenceReader? preferences;
  final AdventureDiagnostics? diagnostics;

  AdventureProductEntryDecision? preflight(AdventureEntryRequest request) {
    _validateRequest(request);
    final availability = rollout.availability;
    if (rollout.isHostAuthorized) return null;
    return _record(_blockedDecision(request, availability));
  }

  @override
  Future<AdventureProductEntryDecision> resolve(
    AdventureEntryRequest request,
  ) async {
    final blocked = preflight(request);
    if (blocked != null) return blocked;

    final availability = rollout.availability;
    final permit = request.activePresentationPermit;
    final permitIsActive = _isActivePermit(permit, request);
    final hadInvalidPermit = permit != null && !permitIsActive;

    TodayExperiencePresentation presentation;
    AdventureFallbackReason fallback = AdventureFallbackReason.none;
    if (permitIsActive) {
      presentation = permit!.assignedPresentation;
      if (presentation == TodayExperiencePresentation.adventure &&
          request.sessionChoice == TodayExperiencePresentation.standard) {
        presentation = TodayExperiencePresentation.standard;
        fallback = AdventureFallbackReason.learnerChoseStandard;
      }
    } else if (request.sessionChoice case final choice?) {
      presentation = choice;
      if (choice == TodayExperiencePresentation.standard) {
        fallback = AdventureFallbackReason.learnerChoseStandard;
      } else if (hadInvalidPermit) {
        fallback = AdventureFallbackReason.assignmentUnavailable;
      }
    } else {
      presentation =
          await preferences?.readForOwner(request.ownerId) ??
          TodayExperiencePresentation.standard;
      if (hadInvalidPermit) {
        fallback = AdventureFallbackReason.assignmentUnavailable;
      } else if (presentation == TodayExperiencePresentation.standard) {
        fallback = AdventureFallbackReason.none;
      }
    }

    if (availability == AdventureAvailability.invalidCatalog) {
      presentation = TodayExperiencePresentation.standard;
      fallback = AdventureFallbackReason.catalogUnavailable;
    } else if (availability == AdventureAvailability.contentUnavailable) {
      presentation = TodayExperiencePresentation.standard;
      fallback = AdventureFallbackReason.contentUnavailable;
    }

    return _record(
      AdventureProductEntryDecision(
        entryAttemptId: request.entryAttemptId,
        availability: availability,
        destination: presentation == TodayExperiencePresentation.adventure
            ? AdventureEntryDestination.adventure
            : AdventureEntryDestination.standardToday,
        fallbackReason: fallback,
        catalogId: catalog.catalogId,
        catalogVersion: catalog.catalogVersion,
        catalogSchemaVersion: catalog.schemaVersion,
        permitId: permitIsActive ? permit!.permitId : null,
        assignmentId: permitIsActive ? permit!.assignmentId : null,
        treatment: permitIsActive
            ? permit!.assignedPresentation.wireName
            : presentation.wireName,
      ),
    );
  }

  AdventureProductEntryDecision _record(AdventureProductEntryDecision value) {
    diagnostics
      ?..recordEntry(value.destination)
      ..recordEntryFallback(value.fallbackReason);
    return value;
  }

  AdventureProductEntryDecision _blockedDecision(
    AdventureEntryRequest request,
    AdventureAvailability availability,
  ) => AdventureProductEntryDecision(
    entryAttemptId: request.entryAttemptId,
    availability: availability,
    destination: AdventureEntryDestination.learn,
    fallbackReason: switch (availability) {
      AdventureAvailability.emergencyOff =>
        AdventureFallbackReason.emergencyOff,
      AdventureAvailability.missingDependency =>
        AdventureFallbackReason.dependencyUnavailable,
      _ => AdventureFallbackReason.featureUnavailable,
    },
    catalogId: catalog.catalogId,
    catalogVersion: catalog.catalogVersion,
    catalogSchemaVersion: catalog.schemaVersion,
  );
}

final class AdventureEntryHostResult {
  const AdventureEntryHostResult({required this.decision, this.today});

  final AdventureProductEntryDecision decision;
  final TodayHubSnapshot? today;
}

final class AdventureEntryHost {
  AdventureEntryHost({
    required this.entry,
    required this.activePermits,
    required this.todayHub,
    required this.createEntryAttemptId,
  });

  final AdventureEntryUseCases entry;
  final ActivePresentationPermitReader activePermits;
  final TodayHubSnapshotLoader todayHub;
  final AdventureEntryAttemptIdFactory createEntryAttemptId;

  String? _ownerId;
  String? _entryAttemptId;
  Future<ActivePresentationPermit?>? _activePermitFuture;
  Future<TodayHubSnapshot>? _todayFuture;
  int _generation = 0;

  Future<AdventureEntryHostResult?> open({
    required String ownerId,
    required DateTime occurredAtUtc,
    TodayExperiencePresentation? sessionChoice,
  }) async {
    _activate(ownerId);
    final generation = _generation;
    final attemptId = _entryAttemptId ??= createEntryAttemptId();
    var request = AdventureEntryRequest(
      ownerId: ownerId,
      entryAttemptId: attemptId,
      occurredAtUtc: occurredAtUtc,
      sessionChoice: sessionChoice,
    );
    final blocked = entry.preflight(request);
    if (blocked != null) {
      return AdventureEntryHostResult(decision: blocked);
    }

    final activePermit = await (_activePermitFuture ??=
        Future<ActivePresentationPermit?>.sync(
          () => activePermits.readActivePermit(
            ownerId: ownerId,
            evaluatedAtUtc: occurredAtUtc,
          ),
        ));
    if (!_isCurrent(ownerId, generation)) return null;
    request = AdventureEntryRequest(
      ownerId: ownerId,
      entryAttemptId: attemptId,
      occurredAtUtc: occurredAtUtc,
      sessionChoice: sessionChoice,
      activePresentationPermit: activePermit,
    );
    final decision = await entry.resolve(request);
    if (!_isCurrent(ownerId, generation)) return null;
    if (decision.destination == AdventureEntryDestination.learn) {
      return AdventureEntryHostResult(decision: decision);
    }

    final snapshot = await (_todayFuture ??= Future<TodayHubSnapshot>.sync(
      todayHub.load,
    ));
    if (!_isCurrent(ownerId, generation) || snapshot.ownerId != ownerId) {
      return null;
    }
    return AdventureEntryHostResult(decision: decision, today: snapshot);
  }

  void _activate(String ownerId) {
    if (_ownerId == ownerId) return;
    _ownerId = ownerId;
    _entryAttemptId = null;
    _activePermitFuture = null;
    _todayFuture = null;
    _generation += 1;
  }

  bool _isCurrent(String ownerId, int generation) =>
      _ownerId == ownerId && _generation == generation;
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void _validateRequest(AdventureEntryRequest request) {
  if (!_canonical(request.ownerId) ||
      !_uuidV4.hasMatch(request.entryAttemptId) ||
      !_validUtc(request.occurredAtUtc)) {
    throw ArgumentError('Adventure entry request is not canonical.');
  }
}

bool _isActivePermit(
  ActivePresentationPermit? permit,
  AdventureEntryRequest request,
) =>
    permit != null &&
    permit.ownerId == request.ownerId &&
    _canonical(permit.permitId) &&
    _canonical(permit.protocolId) &&
    _canonical(permit.protocolVersion) &&
    _canonical(permit.assignmentId) &&
    _validUtc(permit.expiresAtUtc) &&
    request.occurredAtUtc.isBefore(permit.expiresAtUtc);

bool _canonical(String value) =>
    value.isNotEmpty && value == value.trim() && value.runes.length <= 256;

bool _validUtc(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.microsecondsSinceEpoch % Duration.microsecondsPerMillisecond == 0;
