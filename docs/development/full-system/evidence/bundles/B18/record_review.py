"""Persist only explicitly supplied semantic observations, pinned to bytes."""
import datetime
import hashlib
import json
from pathlib import Path

OUT=Path(__file__).resolve().parent
path=OUT/'G8.2-review-ledger.json'
ledger=json.loads(path.read_text(encoding='utf-8'))
notes={
 'lib/main.dart':'Traced bootstrap typed storage failure, mounted/dependency identity checks on resume, detached background sync and owned dependency disposal. Other bootstrap failures still propagate; follow initialization finding.',
 'lib/runtime/app_dependencies.dart':'Checked optional capability dependencies, exact shared learning/review/adventure identity comparisons and idempotent dispose future. Broader feature gates still require caller review.',
 'lib/runtime/app_start_route_resolver.dart':'Authenticated route is home; persisted guest only admits home; store exceptions resolve login.',
 'lib/runtime/resource_disposer_stack.dart':'Reverse cleanup exhausts disposers and preserves first error; initialization cleanup suppresses cleanup errors to retain original failure. own() assumes no registration after disposal.',
 'lib/runtime/local_storage_readiness_app.dart':'Typed storage failure mapping preserves files and explains incompatibility; bounded scrollable safe-area fallback.',
 'lib/runtime/production_feature_gate.dart':'Reviewed listener replacement/removal, live hidden/emergency checks, delivery metadata and composed dependency checks before lazy subtree.',
 'lib/runtime/learning_preview_feature_registry.dart':'Only hidden dailyContinuity promoted; runtime override remains outer authority; no cloud/other delivery promotion.',
 'lib/runtime/app_runtime_status.dart':'Availability represents composition, not provider health. Supabase no-op status explicitly documented; isFullyReady still requires Firebase/backends/AI/voice.',
 'lib/navigation/app_route_factory.dart':'Initial routes limited to login/register/parsed email action; verification requires typed argument; unknown route resolves login.',
 'lib/navigation/app_routes.dart':'Route name map and generic push/replace/reset wrappers inspected; media RouteObserver is shared global.',
 'lib/runtime/registries/feature_registry.dart':'Production state map exhaustive, missing keys hidden, runtime emergency override wins. Mutable registry is explicit test helper; maps accepted by reference, caller ownership assumed.',
 'lib/runtime/runtime_feature_override_store.dart':'Reviewed UTC/expiry constraints, serialized mutation tail, generation suppression and expiry reload. Disposal does not drain queued store mutations: cross-check lifecycle before acceptance.',
 'lib/runtime/app_build_info.dart':'Only public build/version strings; no secret exposure in diagnostic representation.',
 'lib/runtime/central_cost_policy.dart':'Unknown required central cost remains unknown; default cloud flag shared. No free-tier or actual billing claim. Constructor assertions alone are not arbitrary external-input validation.',
 'lib/runtime/circuit_breaker.dart':'Single half-open probe admission reviewed. Old in-flight closed-state completion can reset newly open state; investigate concurrent provider callers and regression.',
 'lib/runtime/download_counter.dart':'Parameterized source/prefix-scoped transaction, deterministic idempotency, collision validation, protected current marker and bounded version/event pruning. Window explicitly not lifetime billing.',
 'lib/runtime/runtime_flag_namespaces.dart':'Exact namespace constants and colon-to-semicolon SQLite binary prefix upper bound inspected.',
 'lib/runtime/supabase_client_config.dart':'Publishable-key regex rejects absent or non-public patterns without echoing rejected value.',
 'lib/runtime/field_feature.dart':'Legacy enum retained; no execution or flag promotion.',
 'lib/runtime/field_feature_registry.dart':'Legacy immutable field defaults and missing-key hidden behavior checked; canonical UI authority is V2.',
 'lib/runtime/learning_dependencies.dart':'Empty compatibility source file; no executable behavior.',
 'lib/runtime/learning_feature_flags.dart':'Empty compatibility source file; no executable behavior.',
 'lib/runtime/production_feature_contract.dart':'Checked delivery identifiers/dependency declarations; shadowRewardV2 false; metadata alone does not admit unsupported runtime.',
 'lib/runtime/registries/feature.dart':'Complete enum and hidden/disabled/emergency states; no behavior.',
 'lib/runtime/registries/consent_registry.dart':'Versioned purpose/owner snapshots; no-op returns unknown, not granted.',
 'lib/runtime/registries/drift_consent_registry.dart':'Owner/version parameterized exact query, malformed decisions unknown, withdrawal denies; purpose limited to research upload.',
 'lib/runtime/registries/entitlement_registry.dart':'Default denies every entitlement; interface does not claim live billing integration.',
 'lib/runtime/registries/experiment_registry.dart':'Exact owner/experiment/version validation; absent repository StateError yields null, malformed returned assignment throws; no assignment writes.',
 'lib/features/identity/application/upgrade_guest_owner.dart':'Canonicalizes owner/UID inputs and delegates upgrade/logout/rollback through configured coordinator; actual ownership authority stays in repository.',
 'lib/features/identity/data/drift_local_owner_repository.dart':'Serialized creation transaction and lease-fenced direct bind reject rebinding. Heartbeat errors/active-owner uniqueness need repository/schema oracle cross-check.',
 'lib/features/identity/domain/identity_mapping.dart':'Identity DTO and no-consent default reviewed; isAuthenticated only means UID present, not auth authorization. No production auth permission inferred.',
 'lib/features/identity/domain/local_owner.dart':'Local owner DTO with nullable remote identity and UTC timestamps supplied by repository.',
 'lib/features/identity/domain/local_owner_repository.dart':'Owner lookup/bind interface checked against concrete repository.',
 'lib/features/identity/domain/owner_upgrade.dart':'Transition lease callback and upgrade result/inventory alias reviewed; no schema mutation here.',
 'lib/features/session/data/shared_preferences_app_entry_state_store.dart':'Only versioned guest entry flag; read failures signedOut, failed writes/removals throw, containsKey prevents unnecessary removal.',
 'lib/features/session/domain/app_entry_state.dart':'Entry choice independent of owner/business data; explicit guest/signedOut enum.',
 'lib/screens/login_screen.dart':'Reviewed controllers, async navigation, account error mapping and guest entry. Guest busy set after consent await; thrown guest/consent errors not fully contained. Requires negative widget regression.',
}
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
for row in ledger['files']:
    if row['path'] not in notes: continue
    assert hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()==row['sha256'],row['path']
    row.update(status='source-read-awaiting-cross-check',sourceReadDate=now,reviewNotes=notes[row['path']])
partial={
 'lib/runtime/app_bootstrap.dart':{'readRanges':[[1,2093]],'notes':'Full composition/control flow read in bounded chunks; cleanup registration finding requires reproduction. Imports and provider initialization inspected; no runtime claim.'},
 'lib/navigation/navigation_glossary.dart':{'readRanges':[[1,654]],'notes':'Read full Thai stable-ID map including reread of truncated settings/profile region. Explicit missing-ID failure; labels do not change stored identities. Assertion fixtures still need REV-12 complete review.'},
 'lib/features/identity/domain/owner_lifecycle_manifest.dart':{'readRanges':[[1,897]],'notes':'Read complete namespace/table descriptors and deletion ordering. Direct-owner set includes legacy_learning_records while originals remain outside current database. Compare with physical schema and export/delete consumers in REV-02/09/12.'},
 'lib/features/identity/data/drift_owner_upgrade_repository.dart':{'readRanges':[[1,4569]],'notes':'Read full gate/upgrade/logout rollback, Pair/reading preflight, category/word/SRS/streak/day/quest/consent/assessment/event/preference merges and outbox rehome. Pair historical IDs protected; untransferable research rows fail closed; legacy custody moves through owner manifest without rewriting legacy payload. Canonical transition cleanup preserves primary result. Cross-check source-authorized receipt transformations and physical uniqueness in REV-02/12.'},
}
for row in ledger['files']:
    if row['path'] in partial:
        row.update(status='in-progress',sourceReadDate=now,**partial[row['path']])
ledger['reviewProgress']={'zone':'REV-01','zoneAccepted':False,'completedZones':[], 'notes':'Source-read is not review acceptance; full file coverage, callers/oracles and finding dispositions remain required.'}
finding_by_path={
 'lib/runtime/app_bootstrap.dart':['B18-REV01-01'],
 'lib/screens/login_screen.dart':['B18-REV01-02'],
 'lib/runtime/circuit_breaker.dart':['B18-REV01-03'],
}
for row in ledger['files']:
    if row['path'] in finding_by_path: row['findingIDs']=finding_by_path[row['path']]
ledger['reviewProgress']['crossChecks']=[
 {'path':'lib/services/guest_session_service.dart','ranges':[[1,278]],'note':'Canonical start contains unexpected provider/entry-store errors and returns typed failure; UI finding narrows to consent await/reentrancy and injectable contract, not proven canonical provider throw.'},
 {'path':'lib/features/ai_tutor/data/ai_tutor_gateway_factory.dart','ranges':'full source','note':'Provider breakers shared per provider across key/list/generate gateways; half-open semantics relevant, UI coordinator serialization still to check.'},
 {'path':'test/runtime/circuit_breaker_test.dart','ranges':'full source','note':'Tests cover threshold, one half-open probe, predicates and invalid config; no old closed-state in-flight completion case. Not rerun.'},
 {'path':'test/screens/login_guest_mode_test.dart','ranges':'full source','note':'Existing repeated-tap test pumps before second tap and lacks deferred consent load; no throwing consent case. Not rerun.'},
 {'path':'test/runtime/app_bootstrap_test.dart','ranges':[[1351,1385],[7681,7730]],'note':'Offline manager fixture only successful reconcile/dispose case; no failed reconcile cleanup. Full test source remains REV-12 pending.'},
 {'path':'test/runtime/resource_disposer_stack_test.dart','ranges':'full source','note':'Reverse order/continue-after-error oracle reviewed; initialization registration is outside this unit. Not rerun.'},
 {'path':'test/navigation/navigation_glossary_test.dart','ranges':'partial output','note':'Exact metadata oracle and negative missing key reviewed; fixture middle truncated, not full source acceptance.'}
]
path.write_text(json.dumps(ledger,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print('Recorded explicit source observations for',len(notes),'files; no zone accepted')
