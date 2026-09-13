"""Bounded delivery/source review and G0 readiness gate, never runtime certification."""
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[6]
OUT=Path(__file__).parent
CONTROL=Path('C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/full-system-orchestration')
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def text(p): return (ROOT/p).read_text(encoding='utf-8-sig')
edition=read(OUT/'G0.8-edition-contract.json')
ledger=read(ROOT/'docs/development/2026-09-13-full-system-work-ledger.json')
assert len(edition['activationMatrix'])==74
assert [r['recordId'] for r in edition['activationMatrix']]==[r['id'] for r in ledger['coverage']]
assert Counter(r['kind'] for r in edition['activationMatrix'])==Counter({'capability':44,'lesson-mode':14,'journey':2,'interaction-group':14})
for r,old in zip(edition['activationMatrix'],ledger['coverage']):
    assert r['ownerPackages']==old['packages'] and r['baselineStatus']==old['status']
    assert r['runtimeStatus']=='NOT RUN in B01'
    assert r['contentProfile'] in edition['content']['profiles']
assert [d['id'] for d in edition['deliveryDecisions']]==['COV-f12','COV-f23','COV-f28','COV-f41']
assert all(d['decisionStatus']=='closed' for d in edition['deliveryDecisions'])
assert [d['id'] for d in edition['acceptedAuthorityObligations']]==[f'D{i:02}' for i in range(1,13)]
assert len(edition['verificationObligations'])==4
assert {o['area'] for o in edition['verificationObligations']}=={'Economy','Integration'}
assert all(o['status']=='Unavailable / NOT RUN' for o in edition['verificationObligations'])
assert edition['buildProfile']['dartDefines']=={'LEXIQUEST_LEARNING_PREVIEW':'true','LEXIQUEST_CLOUD_SYNC_ENABLED':'false'}
assert edition['buildProfile']['baselineCloudDefault'] is True
assert edition['buildProfile']['selectedCloudSync'] is False
assert edition['target']['deviceObservedInB01'] is False and edition['target']['installedBuild'] is None

sourceChecks={
 'lib/runtime/app_bootstrap.dart':[
   "'LEXIQUEST_LEARNING_PREVIEW'", 'cloudSyncEnabled: productionCloudSyncEnabledByDefault',
   'FocusTimerRollout.internal(emergencyOff: focusTimerRollout.emergencyOff)',
   'internalPairMatching: learningPreviewEnabled', 'LearningTimeCaptureRollout.internal(',
   'const ResearchMeasurementSyncRollout.off()', 'const AdventureResearchRuntimeConfig.off()'],
 'lib/runtime/app_dependencies.dart':['this.focusTimerRollout = const FocusTimerRollout.implementedOff()'],
 'lib/runtime/central_cost_policy.dart':["'LEXIQUEST_CLOUD_SYNC_ENABLED'", 'defaultValue: true'],
 'lib/runtime/learning_preview_feature_registry.dart':['feature == Feature.dailyContinuity && state == FeatureState.hidden', '? FeatureState.enabled'],
 'lib/runtime/registries/feature_registry.dart':['Feature.researchAssessment: FeatureState.hidden', 'if (override == FeatureState.emergencyOff) return FeatureState.emergencyOff'],
 'lib/features/learning/application/lesson_mode_registry.dart':['LessonModeDeliveryState handwritingDeliveryState =', "routeName: 'learning/handwriting-scratchpad'", 'deliveryState: handwritingDeliveryState'],
 'lib/features/time_tracking/application/focus_timer_rollout.dart':['stage == FocusTimerStage.internal && !emergencyOff'],
 'lib/runtime/production_feature_gate.dart':['ProductionFeatureUnavailableReason.missingRegistry', 'ProductionFeatureUnavailableReason.missingDependency', 'ProductionFeatureUnavailableReason.incompatibleRollout'],
 'lib/config/adventure_research_runtime_config.dart':['const AdventureResearchRuntimeConfig.off()', 'study = null'],
}
sourcePins={}
for path,anchors in sourceChecks.items():
    body=text(path)
    for anchor in anchors: assert anchor in body,(path,anchor)
    sourcePins[path]=sha(ROOT/path)
bootstrap=text('lib/runtime/app_bootstrap.dart')
composition=bootstrap.split('final lessonModes = buildLessonModeRegistry(',1)[1].split(');',1)[0]
assert 'handwritingDeliveryState' not in composition
assert 'matchingDeliveryState: learningPreviewEnabled' in composition
registry=text('lib/features/learning/application/lesson_mode_registry.dart')
assert re.search(r'handwritingDeliveryState\s*=\s*LessonModeDeliveryState\.implementedOff',registry)
# Validate selected profile against observed flag declarations; this is not a compiled config probe.
assert 'bool.fromEnvironment' in bootstrap and 'bool.fromEnvironment' in text('lib/runtime/central_cost_policy.dart')
plannedTargets=['test/runtime/runtime_feature_controls_test.dart','test/features/learning/lesson_mode_registry_test.dart']
for p in plannedTargets:
    assert (ROOT/p).is_file()
    sourcePins[p]=sha(ROOT/p)

# Reuse accepted G0.5 source/content evidence by exact Git object identity.
manifest=read(ROOT/'docs/development/full-system/evidence/G0.5/source-manifest.json')
tree=subprocess.check_output(['git','ls-tree','-r','HEAD'],cwd=ROOT).decode().splitlines()
blobs={line.split('\t',1)[1]:line.split()[2] for line in tree}
assert len(manifest['pins'])==169
for p in manifest['pins']:
    assert blobs[p['path']]==p['gitBlob'],p['path']
assert edition['content']['profiles']==manifest['contentProfiles']
assert edition['content']['catalogSemanticHash']==manifest['catalogSemanticHash']
changed=subprocess.check_output(['git','diff','--name-only','6ab2e371'],cwd=ROOT).decode().splitlines()
assert all(p.startswith('docs/') for p in changed),changed
assert not subprocess.check_output(['git','diff','--name-only','--diff-filter=D','6ab2e371'],cwd=ROOT).strip()

g06=read(OUT/'G0.6-verification.json'); g07=read(OUT/'G0.7-verification.json')
assert g06['status']==g07['status']=='passed'
for name,fingerprint in g06['fingerprints'].items(): assert sha(OUT/name)==fingerprint,name
assert sha(OUT/'G0.7-formula-registry.json')==g07['registrySha256']
assert sha(OUT/'verify_formulas.py')==g07['verifierSha256']
for path,fingerprint in g07['sourcePins'].items(): assert sha(ROOT/path)==fingerprint,path
assert g07['openDefects']==['B01-FORM-01','B01-FORM-02']
state=read(CONTROL/'run-state.json')
assert state['executionAuthorized'] and state['executionMode']=='bundles'
assert state['currentWriter']['threadId']=='01a09918-9875-7822-88c9-382a51aa99b9'
assert state['currentPackageId']=='G0.8' and state['activeBundleId']=='B01'
assert len(state['acceptedHistory'])==5
receipts={}
for package in ['G0.6','G0.7']:
    receipt=read(CONTROL/'packages'/f'{package}.json')
    assert receipt['status']=='accepted' and receipt['bundleId']=='B01'
    assert sha(ROOT/receipt['verificationPath'])==receipt['verificationSha256']
    subprocess.check_call(['git','merge-base','--is-ancestor',receipt['acceptedSourceSha'],'HEAD'],cwd=ROOT)
    receipts[package]=receipt['acceptedSourceSha']
links=0
report=ROOT/'docs/development/full-system/bundles/B01.md'
for dest in re.findall(r'\]\(([^)]+)\)',report.read_text(encoding='utf-8')):
    if '://' not in dest and not dest.startswith('#'):
        assert (report.parent/dest.split('#')[0]).resolve().exists(),dest
        links+=1
result={'schemaVersion':1,'packageId':'G0.8','bundleId':'B01','kind':'delivery-review','status':'passed',
 'sourceSha':edition['sourceSha'],'controlRevisionAtVerification':state['revision'],
 'editionId':edition['editionId'],'editionContractSha256':sha(OUT/'G0.8-edition-contract.json'),
 'verifierSha256':sha(Path(__file__)),'sourcePins':sourcePins,
 'counts':{'activationRecords':74,'deliveryDecisions':4,'authorityDispositions':12,'reusedG05Pins':169,'formulaFixtures':60,'failureCandidatesRetained':76,'reportLinks':links},
 'reusedPackageCommits':receipts,'gates':{
   'sourceOwnership':'PASS accepted G0.1/G0.2 lineage; one current bundle writer and isolated accepted branch',
   'authorityChoices':'PASS D01–D12 adopted with implementation/remote release blockers retained, not runtime closure',
   'coverageAssignment':'PASS same74 records, content profiles, owner packages and catalog identity',
   'cleanupDisposition':'PASS accepted G0.6 unchanged fingerprints; all76 evidence images retained with restore proof',
   'formulaRegistry':'PASS accepted G0.7 unchanged source/registry; gaps have explicit downstream owners',
   'editionDecision':'PASS local preview config specified and source-bound; f12/f23/f28/f41 decisions closed; actual device config NOT RUN',
   'verificationObligations':'PASS obligation registration only; Economy/Integration missing automation remains NOT RUN',
   'G0':'PASS development-readiness; not runtime/product/release acceptance'},
 'runtimeVerified':False,'applicationChanges':0,'dataDeletions':0,
 'notRun':['Flutter','backend','Android build/install','GPU','emulator','physical device','human','live provider','full release'],
 'openDefects':['B01-FORM-01','B01-FORM-02'],'externalGates':edition['externalGates'],
 'review':'Reviewed against G0.8/Master decisions. Preserves existing authority/history, closes decision ambiguity, explicitly disables cloud in selected profile, does not activate any service or claim44 runtime capabilities.'}
(OUT/'G0.8-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':result['status'],'G0':result['gates']['G0'],'counts':result['counts'],'runtimeVerified':False}))
