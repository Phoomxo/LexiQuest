"""Reconcile documentation only; never infer runtime acceptance from source presence."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
LEDGER = ROOT / 'docs/development/2026-09-13-full-system-work-ledger.json'
SOURCE = 'e3b21146a7ba0b4f6366d0f70830b9cc2c6c6919'
def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')
def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

ledger = json.loads(LEDGER.read_text(encoding='utf-8-sig'))
catalog_path = 'docs/generated/alltcas-idea-integration-feature-map.json'
catalog = json.loads(read(catalog_path))
features = {r['id']: r for r in catalog['records']}
registry_path = 'lib/features/learning/application/lesson_mode_registry.dart'
registry = read(registry_path)
production_path = 'lib/runtime/production_feature_contract.dart'
production = read(production_path)
delivery = {}
for match in re.finditer(r'Feature\.(\w+): ProductionFeatureDelivery\((.*?)\n  \)', production, re.S):
    body = match[2]
    delivery[match[1]] = {k: re.search(k + r":\s*'([^']*)'", body)[1] for k in ['productionEntryId', 'dependencyId']}
defaults_path = 'lib/runtime/registries/feature_registry.dart'
defaults = dict(re.findall(r'Feature\.(\w+): FeatureState\.(\w+)', read(defaults_path).split('const BuildFeatureRegistry.fieldDefaults()')[1].split('const BuildFeatureRegistry.allEnabled()')[0]))

# Explicit consumer boundaries: route-free capability identity remains unchanged.
boundaries = {
'f04': ('lib/features/learning_packs/domain/content_quality_policy.dart', 'lib/features/learning_packs/application/learning_pack_detail_use_cases.dart', 'Pack detail and offline imports consume version/checksum/provenance and reviewed publication policy; no independent menu.'),
'f05': ('lib/features/learning/presentation/unified_lesson_shell.dart', 'lib/features/learning/application/current_activity_evidence.dart', 'Lesson screens consume shared shell/controller feedback and canonical evidence adapter; shell is not a new writer.'),
'f10': (registry_path, 'lib/runtime/app_bootstrap.dart', 'Matching is composed through quiz authority and learning/matching; production matching is implemented-off unless learning preview is enabled.'),
'f12': (registry_path, 'lib/features/learning_packs/application/learning_pack_detail_use_cases.dart', 'Scratchpad registration is implemented-off; pack detail omits it. Ephemeral self-check has no OCR or scored evidence.'),
'f15': ('lib/features/recommendation/application/recall_ladder_use_cases.dart', 'lib/features/recommendation/domain/active_recall_ladder.dart', 'Recommendation readers consume canonical mastery/availability into the recall ladder; no separate route or mastery writer.'),
'f16': ('lib/features/learning/domain/session_configuration.dart', 'lib/features/learning/presentation/session_configuration_sheet.dart', 'Session configuration sheet/policy supplies activity launch configuration; no independent product entry.'),
'f17': ('lib/features/learning/domain/answer_feedback.dart', 'lib/features/learning/presentation/answer_feedback_panel.dart', 'Lesson answer feedback panel consumes evaluated feedback; UI cannot independently award correctness or rewards.'),
'f20': ('lib/features/review/application/learner_intent_use_cases.dart', 'lib/features/review/data/drift_learner_intent_repository.dart', 'Review/bookmark use cases persist learner intent through owner-scoped repository; no standalone entry in catalog.'),
'f21': ('lib/features/review/application/content_report_use_cases.dart', 'lib/features/review/presentation/content_report_sheet.dart', 'Content report sheet submits reports through review use cases; reports are not automatic published content corrections.'),
'f23': ('lib/features/time_tracking/application/focus_timer_controller.dart', 'lib/features/time_tracking/presentation/focus_timer_widget.dart', 'Embedded focus widget consumes controller under FocusTimerRollout; implemented-off by default, preview internal only.'),
'f24': ('lib/features/time_tracking/application/active_learning_time_controller.dart', 'lib/runtime/app_bootstrap.dart', 'Bootstrap composes active learning time for trustworthy educational activity consumers; durable time authority remains canonical.'),
'f25': ('lib/features/progress/application/learning_calendar_use_cases.dart', 'lib/screens/learning_calendar_screen.dart', 'Calendar screen reads canonical learning-time/progress projections; no second analytics writer.'),
'f34': ('lib/features/achievements/application/achievement_share_card_use_cases.dart', 'lib/features/achievements/presentation/achievement_share_card.dart', 'Achievement card renders projection snapshot for sharing; not a new achievement authority or route.'),
'f35': ('lib/features/preferences/application/learner_preferences_use_cases.dart', 'lib/features/preferences/data/drift_learner_preferences_repository.dart', 'Onboarding/settings consumers store learner preferences through owner-scoped use cases; no separate catalog menu.'),
'f38': ('lib/features/accessibility/domain/accessibility_policy.dart', 'lib/features/accessibility/presentation/accessibility_scope.dart', 'Shared accessibility scope supplies semantics/scaling/motion policy to lesson shell and UI consumers.'),
'f39': ('lib/features/preferences/application/display_preferences_controller.dart', 'lib/features/learning/presentation/unified_lesson_shell.dart', 'Display preferences and lesson UI consume theme/motion choices; independent runtime accessibility acceptance remains required.'),
'f41': (defaults_path, 'lib/runtime/production_feature_gate.dart', 'Build/runtime registries and production gate govern existing feature consumers; hidden/disabled/emergency-off must fail closed, no standalone route.'),
}
mode_features = {'associativeReading':'reading','meaningQuiz':'quiz','typedRecall':'quiz','definitionQuiz':'quiz','cloze':'quiz','matching':'quiz','flashcard':'srs','handwritingScratchpad':'quiz','dictation':'quiz','speaking':'speechPractice','shadowing':'speechPractice','cefrReading':'reading','sentenceScramble':'quiz','wordScramble':'quiz'}
common = [catalog_path, production_path, defaults_path, registry_path,
 'lib/features/learning/domain/lesson_mode.dart', 'lib/runtime/app_bootstrap.dart',
 'lib/runtime/learning_preview_feature_registry.dart', 'lib/runtime/central_cost_policy.dart',
 'lib/product/feature_contract/alltcas_idea_integration_catalog.dart',
 'lib/product/feature_contract/compatibility_profiles.dart',
 'lib/features/learning_packs/domain/content_quality_policy.dart',
 'lib/features/learning_packs/application/learning_pack_detail_use_cases.dart',
 'lib/features/vocabulary/data/cefr_editorial_manifest.dart',
 'lib/features/learning/application/current_activity_evidence.dart',
 'lib/features/learning/domain/evidence_eligibility_policy.dart',
 'lib/data/local/app_database.dart', 'docs/development/full-system/G0.3-authority.md',
 'docs/superpowers/specs/2026-09-13-minigame-coverage-contract.md',
 'docs/development/2026-09-13-master-plan-coverage-audit.md',
 'pubspec.yaml', 'pubspec.lock', 'lib/features/time_tracking/application/focus_timer_rollout.dart']
rows = {r['id']: r for r in ledger['coverage']}
for row in ledger['coverage']:
    row['sourcePin'] = SOURCE
    related = row.get('relatedModeRecords', []) + row.get('relatedCapabilityRecords', [])
    row['requirements'] = [row['id']] + related
    row['traceability'] = {'schemaVersion': 1, 'inspection': 'source-inspected-runtime-not-run',
      'sourceManifest': 'docs/development/full-system/evidence/G0.5/source-manifest.json',
      'configProfile': 'accepted-source-defaults', 'contentProfile': 'canonical-content',
      'authorityDecision': 'docs/development/full-system/G0.3-authority.md',
      'evidencePath': 'docs/development/full-system/evidence/G0.5/verification.json',
      'sourcePaths': []}
    trace = row['traceability']
    if row['kind'] == 'capability':
        f = features[row['featureId']]
        trace['sourcePaths'] = [catalog_path, production_path]
        trace['runtimeFeatures'] = f['runtimeFeatures']
        trace['buildDefaultStates'] = {x: defaults[x] for x in f['runtimeFeatures']}
        trace['productionEntries'] = f['productionEntryIds']
        trace['authorityProfileId'] = f['authorityProfileId']
        trace['evidenceProfileId'] = f['evidenceProfileId']
        if not f['productionEntryIds']:
            provider, consumer, explanation = boundaries[f['id']]
            row['foundationBoundary'] = explanation
            trace['consumerBoundary'] = {'provider': provider, 'consumer': consumer, 'contract': explanation}
            trace['sourcePaths'] += [provider, consumer]
        if int(f['id'][1:]) in list(range(23,28)) + list(range(29,44)):
            trace['contentProfile'] = 'owner-derived-or-foundation'
        if f['id'] == 'f12': trace['contentProfile'] = 'ephemeral-unscored'
        if f['id'] == 'f28': trace['contentProfile'] = 'assessment-question-set'
    elif row['kind'] == 'lesson-mode':
        feature = mode_features[row['modeId']]
        trace.update(runtimeFeatures=[feature], productionEntries=[delivery[feature]['productionEntryId']],
          buildDefaultStates={feature: defaults[feature]}, route=row['declaredRoute'],
          deliveryDefault='implementedOff' if row['modeId'] in ['matching','handwritingScratchpad'] else 'enabled-subject-to-feature-and-content-gates',
          sourcePaths=[registry_path, 'lib/runtime/app_bootstrap.dart'],
          authorityProfileId=features[row['featureId']]['authorityProfileId'],
          evidenceProfileId=features[row['featureId']]['evidenceProfileId'])
        if row['modeId'] == 'matching': trace['previewOverride'] = 'LEXIQUEST_LEARNING_PREVIEW=true enables internal pair matching'
        if row['modeId'] == 'handwritingScratchpad': trace['contentProfile'] = 'ephemeral-unscored'
        if row['modeId'] in ['dictation','speaking','shadowing']: trace['contentProfile'] = 'media-dependent'
    elif row['kind'] == 'journey':
        adventure = row['id'] == 'MODE-adventure-journey'
        feature = 'adventureMotivation' if adventure else 'ghostDuel'
        trace.update(runtimeFeatures=[feature], buildDefaultStates={feature: defaults[feature]},
          productionEntries=[delivery[feature]['productionEntryId']],
          sourcePaths=['lib/features/adventure/presentation/adventure_hub_screen.dart', 'lib/features/adventure/presentation/adventure_mixed_review_screen.dart'] if adventure else ['lib/screens/ghost_shadow_duel_screen.dart'],
          authorityProfileId=features['f13']['authorityProfileId'], evidenceProfileId=features['f13']['evidenceProfileId'],
          contentProfile='journey-session-identity')
        row['declaredEntry'] = delivery[feature]['productionEntryId']
    else:
        trace.update(relatedRecords=related, sourcePaths=['docs/superpowers/specs/2026-09-13-minigame-coverage-contract.md'],
          authorityProfileId='inherit-related-records', evidenceProfileId='inherit-related-records',
          contentProfile='inherit-related-records')
        if row['id'] == 'MG-10':
            trace['contentProfile'] = 'assessment-question-set'
            trace['boundary'] = 'Reading exposure is not authored Q&A acceptance; requires versioned questions, answers and explanations in P2.8/P3.2/P3.6.'
    trace['testTargetInspection'] = [{'path': p, 'exists': (ROOT/p).is_file(), 'runtimeStatus':'not-run-by-G0.5'} for p in row['testTargets']]
    common += trace['sourcePaths'] + [r['path'] for r in trace['testTargetInspection'] if r['exists']]

starter = json.loads(read('assets/content/cefr_starter/catalog.json'))
profiles = {
 'canonical-content': {'readiness':'source-inspected-per-pack-runtime-readiness-not-run', 'version':starter['edition'],
 'starterQuality':starter['qualityStatus'], 'starterCount':starter['count'],
 'editorialVersion':'content-addressed assets in source-manifest; schemaVersion 1',
 'contract':'Canonical pack/word revision and checksum; reviewed publication/provenance required. Starter inventory and editorial files do not certify every mode prompt. Pack detail gates definition/cloze/matching with pinned vocabulary; other registrations still require owner acceptance.',
 'paths':['assets/content/cefr_starter/catalog.json','lib/features/vocabulary/data/cefr_editorial_manifest.dart','lib/features/learning_packs/domain/content_quality_policy.dart','lib/features/learning_packs/application/learning_pack_detail_use_cases.dart']},
 'owner-derived-or-foundation': {'readiness':'runtime-not-run','version':'AppDatabase schema26 / accepted source '+SOURCE,'contract':'No independent content pack. Consumes owner-scoped preferences, canonical evidence/time/progress or shared UI/activation policy; session/content identities are inherited where relevant.'},
 'ephemeral-unscored': {'readiness':'implemented-off','version':SOURCE,'contract':'Local ephemeral scratchpad; no OCR, durable response or correctness/reward inference.'},
 'media-dependent': {'readiness':'external-pending-for-physical-audio; local fallback not run','version':SOURCE,'contract':'Canonical prompt and provider/model/voice identity required at session time; availability, permission and device checks remain P6.4/P6.5.'},
 'journey-session-identity': {'readiness':'runtime-not-run','version':SOURCE,'contract':'Adventure mixed review pins canonical session/prompt catalog; Ghost requires compatible recorded ghost identity/time. No fabricated live ghost/content revision.'},
 'assessment-question-set': {'readiness':'needs-verification; research assessment hidden in field defaults','version':SOURCE,'contract':'Authored question/answer/explanation set revision required; exposure-only reading does not satisfy MG-10. No research activation or enrollment authorized.'},
 'inherit-related-records': {'readiness':'runtime-not-run','version':SOURCE,'contract':'Resolve every related record; apply MG-specific acceptance in addition to shared mode/config/content. MG-03 selected and MG-04 typed remain distinct.'}}
for path in sorted((ROOT/'assets/content').rglob('*')):
    if path.is_file(): common.append(path.relative_to(ROOT).as_posix())
pins = []
for path in sorted(set(common)):
    data = (ROOT/path).read_bytes()
    blob = subprocess.check_output(['git','rev-parse', SOURCE+':'+path],cwd=ROOT,text=True).strip()
    accepted = subprocess.check_output(['git','cat-file','blob',blob],cwd=ROOT)
    assert data.replace(b'\r\n', b'\n') == accepted.replace(b'\r\n', b'\n'), path
    pins.append({'path':path,'sha256':hashlib.sha256(data).hexdigest(),'gitBlob':blob,
      'acceptedBytesSha256':hashlib.sha256(accepted).hexdigest(),
      'checkoutTransform':'identical' if data == accepted else 'CRLF/LF-only', 'bytes':len(data)})
manifest = {'schemaVersion':1,'sourceSha':SOURCE,'catalogRevision':catalog['revision'],
 'catalogSemanticHash':catalog['semanticHash'],'configProfiles':{'accepted-source-defaults':{
 'buildRegistry':'BuildFeatureRegistry.fieldDefaults','states':defaults,'learningPreviewDefault':False,
 'cloudSyncDefault':True,'effectiveDeploymentConfig':'not-observed; source defaults only; P0.8/P7.5 required',
 'runtimeOverrides':'owner/runtime overrides and availability may further restrict; no active device state read'}},
 'contentProfiles':profiles,'pins':pins,'runtimeVerified':False}
write(OUT/'source-manifest.json',manifest)
ledger['coverageTraceability'] = {'package':'P0.5','status':'assigned-source-inspected','sourceSha':SOURCE,
 'manifest':'docs/development/full-system/evidence/G0.5/source-manifest.json','runtimeVerified':False,
 'compatibility':'Historical 44-feature generated catalog remains unchanged; 74 overlapping coverage identities preserved.'}
pkg = next(p for p in ledger['packages'] if p['id']=='P0.5')
pkg['status'] = 'accepted'
pkg['acceptanceEvidence'] = 'docs/development/full-system/evidence/G0.5/verification.json'
write(LEDGER,ledger)
print(json.dumps({'records':len(rows),'pins':len(pins),'missingTargets':sorted({x['path'] for r in rows.values() for x in r['traceability']['testTargetInspection'] if not x['exists']})}))
