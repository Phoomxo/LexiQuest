"""G0.8 edition decision supplement; no runtime flag or historical ledger writes."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[6]
OUT=Path(__file__).parent
def read(p): return json.loads((ROOT/p).read_text(encoding='utf-8-sig'))
def save(name,value): (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
ledger=read('docs/development/2026-09-13-full-system-work-ledger.json')
source=read('docs/development/full-system/evidence/G0.5/source-manifest.json')
decision={
 'schemaVersion':1,'packageId':'G0.8','bundleId':'B01','editionId':'local-learning-preview-b01-v1',
 'sourceSha':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
 'decisionStatus':'selected-for-sequential-development','runtimeStatus':'NOT RUN; no binary built or installed in B01',
 'scope':'Local guest learning preview with canonical owner/history, no research activation, no optional remote service requirement. This is not a44-capability runtime completion claim.',
 'target':{'primary':'Android13/API33 ARM64 phone profile; vivo V2041 family recorded in historical device evidence',
           'secondary':'Android emulator API33+ for local synthetic journeys; narrow/large-text/reduced-motion checks in owner packages',
           'selectionBasis':'Existing Android baseline and prior device evidence, not a fresh device inventory',
           'deviceObservedInB01':False,'installedBuild':None,'sourceMinSdk':26,
           'deviceAcceptanceOwners':['G5.6','G8.6','G8.7'],'otherPlatforms':'No iOS/desktop/web delivery acceptance claim'},
 'buildProfile':{'dartDefines':{'LEXIQUEST_LEARNING_PREVIEW':'true','LEXIQUEST_CLOUD_SYNC_ENABLED':'false'},
                 'entry':'AppBootstrap.production -> accepted AppDatabase schema26 and single composition root',
                 'baselineCloudDefault':True,'selectedCloudSync':False,
                 'configVerification':'Source flag binding and composition reviewed; compiled artifact/actual deployed config not observed. G1.7 must prove offline/non-completing optional initialization; G7.5/G7.7 must bind final artifact flags.',
                 'profileApplication':'Specification only; this package did not change host environment, runtime overrides, defaults, signing, cloud configuration or deployment.'},
 'deliveryDecisions':[
   {'id':'COV-f12','decision':'Include local ephemeral scratchpad in intended preview edition after G2.6 route/cleanup/no-evidence acceptance; keep current implementedOff until then',
    'decisionStatus':'closed','sourceState':'implementedOff even with learning preview; bootstrap omits handwritingDeliveryState override',
    'route':'learning/handwriting-scratchpad','content':'ephemeral-unscored; no OCR/autograde/reward or durable learner response',
    'owners':['G2.6','G7.5'],'requiredAcceptance':['route reachable only in selected edition','exit/restart/controller replacement clears strokes only','owner switch clears ephemeral state','no evidence/XP/coins/SRS from self-check','canonical vocabulary/history untouched','stale route/emergencyOff fails closed'],
    'runtimeStatus':'NOT RUN; not activated'},
   {'id':'COV-f23','decision':'Retain existing preview internal focus timer and active-time capture; do not implement a second timer',
    'decisionStatus':'closed','sourceState':'AppDependencies default off; AppBootstrap learningPreviewEnabled promotes both internal while preserving emergencyOff',
    'route':'embedded focus widget through existing learning/Today consumers',
    'owners':['G1.6','G4.3','G7.5'],'requiredAcceptance':['route/controller dependency available','monotonic active effort','pause/background/idle/retry','timer emergencyOff respected','no timer-derived skill score'],
    'runtimeStatus':'source composition inspected; runtime NOT RUN'},
   {'id':'COV-f28','decision':'Research assessment remains hidden/fail-closed. Do not select personal assessment runtime in this edition; G3.6 validates synthetic existing contract and any later personal design needs separate versioned authority.',
    'decisionStatus':'closed','sourceState':'researchAssessment hidden in field defaults and unchanged by LearningPreviewFeatureRegistry',
    'route':'research/assessment','owners':['G3.6','G7.5'],
    'requiredAcceptance':['missing consent/assignment/instrument/config denied','synthetic comparison metadata isolation','no enrollment/study assignment/synchronization','disclose capability absent from personal runtime'],
    'runtimeStatus':'NOT RUN; research rollout not authorized'},
   {'id':'COV-f41','decision':'Use existing build→preview→runtime/emergency override→production dependency/delivery gates; no direct-route bypass',
    'decisionStatus':'closed','sourceState':'RuntimeFeatureRegistry emergencyOff wins; ProductionFeatureGate rejects missing registry/dependency/incompatible rollout',
    'route':None,'owners':['G1.7','G7.5'],
    'requiredAcceptance':['hidden/disabled/emergencyOff unavailable','missing dependency unavailable','owner change/stale routes cannot resurrect feature','runtime override expiry/restart','actual artifact flags match profile'],
    'runtimeStatus':'source inspected; runtime NOT RUN'}],
 'integrations':{
    'camera':'Retain shipped baseline, no candidate promotion. Real camera/model/resource/physical validation remains G5; no fake detection fallback.',
    'aiVoice':'Optional; no key/device/provider unavailable path required. No paid requests, live quality, acoustic pronunciation or free-tier claims from local fixture evidence.',
    'cloud':'Disabled for selected preview profile; current default true is not changed. No trusted remote economy acceptance until D04/G7.3 rules and G7.5 actual activation checks.',
    'research':'ResearchMeasurementSyncRollout.off, AdventureResearchRuntimeConfig.off; leave canonical legacy evidence config untouched. No study/issuer/consent/participant provisioning.',
    'storage':'No optional Supabase/storage dependency selected; D09 forward-policy work remains mandatory before any storage-enabled edition.',
    'cost':'No spending authority; CentralCostBaseline production unknown prices are not evidence of free operation.'},
 'content':{'catalogRevision':source['catalogRevision'],'catalogSemanticHash':source['catalogSemanticHash'],
            'profiles':source['contentProfiles'],'sourceManifest':'docs/development/full-system/evidence/G0.5/source-manifest.json',
            'availabilityRule':'Installed canonical revision/checksum plus mode-specific readiness controls launch. Starter3000 inventory does not establish every definition/cloze/matching/speech prompt usable; unavailable stays unavailable.',
            'offlineRule':'Use packaged/previously verified installed content; no remote download or new provider content needed for G0. Content publications/rollouts need owner acceptance.'},
 'acceptanceNotices':['44 catalog identities and74 coverage records are preserved; edition runtime coverage is incomplete.',
                      'f12 is a closed intended-delivery decision with activation pending tests; f28 personal assessment is not selected.',
                      'Formula gaps B01-FORM-01 and B01-FORM-02 remain owned implementation obligations, not fixed by registry acceptance.',
                      'No new Flutter/backend/emulator/device/human/live/GPU/full-release PASS is asserted.'],
 'rollback':'No runtime mutation to undo. Revert only B01 docs commits if changing this decision, retain receipts/evidence; never reset user data or predecessor worktrees.'}

activation=[]
for r in ledger['coverage']:
    tr=r.get('traceability',{})
    effective=dict(tr.get('buildDefaultStates',{}))
    if effective.get('dailyContinuity')=='hidden': effective['dailyContinuity']='enabled'
    modeDelivery=tr.get('deliveryDefault')
    if r.get('modeId')=='matching': modeDelivery='enabled-internal-pair'
    special=next((d for d in decision['deliveryDecisions'] if d['id']==r['id']),None)
    activation.append({'recordId':r['id'],'kind':r['kind'],'ownerPackages':r['packages'],
      'baselineStatus':r['status'],'runtimeStatus':'NOT RUN in B01',
      'routeOrBoundary':r.get('declaredRoute') or r.get('declaredEntries') or r.get('foundationBoundary') or tr.get('consumerBoundary') or 'inherit related coverage records',
      'sourceDefaultFeatureStates':tr.get('buildDefaultStates',{}),'previewFeatureStatesBeforeRuntimeGates':effective,
      'previewModeDelivery':modeDelivery,'contentProfile':tr.get('contentProfile'),
      'contentReadiness':decision['content']['profiles'].get(tr.get('contentProfile'),{}).get('readiness','inherit related records'),
      'decisionId':special['id'] if special else 'preserve-current-contract-and-owning-package-acceptance',
      'availability':'Feature state alone is insufficient; canonical content, delivery, owner/runtime overrides and dependencies must all admit.',
      'testTargets':r.get('testTargets',[]),'externalDependency':r.get('externalDependency')})
decision['activationMatrix']=activation
authority=(ROOT/'docs/development/full-system/G0.3-authority.md').read_text(encoding='utf-8-sig')
adopt=[]
for match in re.finditer(r'^### (D\d{2}) — ([^\n]+)\n(.*?)(?=^### D|^## Acceptance|\Z)',authority,re.M|re.S):
    key,title,body=match.groups()
    adopt.append({'id':key,'title':title,'source':'docs/development/full-system/G0.3-authority.md',
                  'sectionSha256':hashlib.sha256(body.encode()).hexdigest(),
                  'ownerPackageMentions':sorted(set(re.findall(r'[PG]\d\.\d',body))),
                  'disposition':'Adopt accepted authority choice and all stated implementation/release obligations verbatim; source ownership closed, runtime work not promoted to PASS.'})
decision['acceptedAuthorityObligations']=adopt
assert [item['id'] for item in adopt] == [f'D{i:02}' for i in range(1,13)]
decision['verificationObligations']=read('docs/development/full-system/evidence/G0.4/registry-verification.json')['unavailable']
decision['externalGates']=[
 {'id':'REMOTE-ECONOMY','status':'NOT RUN/open-required-for-remote-edition','owners':['G7.3','G7.5'],'reason':'D04 trusted remote rules not closed; selected preview disables cloud'},
 {'id':'STORAGE-POLICY','status':'NOT RUN/not-selected-local-edition','owners':['G7.3','G7.5'],'reason':'D09 forward storage policy validation before enabling storage'},
 {'id':'DEVICE-CAMERA','status':'NOT RUN/external-pending','owners':['G5.6','G8.6','G8.7'],'reason':'Physical permission/lifecycle/model/resource/quality evidence required'},
 {'id':'LIVE-AI-VOICE','status':'NOT RUN/external-pending','owners':['G6.6','G8.6'],'reason':'Live provider/audio/human quality not established by local tests'},
 {'id':'BUILD-IDENTITY','status':'NOT RUN/required-later','owners':['G7.7','G8.6'],'reason':'Actual APK/AAB identity/signature/config/release provenance not inspected here'},
 {'id':'FULL-RELEASE','status':'NOT RUN/required-after-freeze','owners':['G8.4','G8.5','G8.9'],'reason':'B18 review/fixes before B19 System Test Plan/execution; no early full gate'}]
save('G0.8-edition-contract.json',decision)
print(json.dumps({'edition':decision['editionId'],'decisions':len(decision['deliveryDecisions']),'activationRecords':len(activation),'authorityDispositions':len(adopt),'unavailableVerificationObligations':len(decision['verificationObligations'])}))
