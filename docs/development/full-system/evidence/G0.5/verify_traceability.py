"""Bounded JSON/path/link/Git/hash acceptance, not a Flutter/runtime test."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

started = time.monotonic()
ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
SOURCE = 'e3b21146a7ba0b4f6366d0f70830b9cc2c6c6919'
LEDGER = 'docs/development/2026-09-13-full-system-work-ledger.json'
def read(path): return (ROOT/path).read_text(encoding='utf-8-sig')
def git(*args): return subprocess.check_output(['git', *args], cwd=ROOT)
def sha(data): return hashlib.sha256(data).hexdigest()
ledger = json.loads(read(LEDGER))
baseline = json.loads(git('show', SOURCE+':'+LEDGER))
manifest = json.loads((OUT/'source-manifest.json').read_text(encoding='utf-8'))
catalog = json.loads(read('docs/generated/alltcas-idea-integration-feature-map.json'))
rows = {r['id']:r for r in ledger['coverage']}
old = {r['id']:r for r in baseline['coverage']}
assert len(rows) == len(ledger['coverage']) == 74
assert set(rows) == set(old)
counts = {k:sum(r['kind']==k for r in rows.values()) for k in ['capability','lesson-mode','journey','interaction-group']}
assert list(counts.values()) == [44,14,2,14], counts
assert len({r['domain'] for r in rows.values() if r['kind']=='capability'}) == 8
assert set(r['featureId'] for r in rows.values() if r['kind']=='capability') == {r['id'] for r in catalog['records']}
enum = read('lib/features/learning/domain/lesson_mode.dart').split('enum LessonMode {')[1].split('}')[0]
assert set(re.findall(r'\b(\w+)\s*,',enum)) == {r['modeId'] for r in rows.values() if r['kind']=='lesson-mode'}
assert {f'MG-{i:02}' for i in range(1,15)} == {r['id'] for r in rows.values() if r['kind']=='interaction-group'}
packages = {p['id'] for p in ledger['packages']}
pins = {p['path']:p for p in manifest['pins']}
assert len(pins)==len(manifest['pins'])
for path, pin in pins.items():
    data = (ROOT/path).read_bytes()
    assert sha(data)==pin['sha256'], path
    blob = git('rev-parse',SOURCE+':'+path).decode().strip()
    assert blob==pin['gitBlob'], path
    accepted = git('cat-file','blob',blob)
    assert sha(accepted)==pin['acceptedBytesSha256'], path
    assert data.replace(b'\r\n',b'\n')==accepted.replace(b'\r\n',b'\n'), path
foundation_count = 0
test_targets = set()
for ident, row in rows.items():
    assert row['sourcePin']==SOURCE
    assert row['packages'] and set(row['packages'])<=packages
    assert row['status']==old[ident]['status'], ident
    assert row['evidence']==old[ident]['evidence'], ident
    assert row['requirements'] and row['requirements'][0]==ident
    assert (ROOT/row['acceptanceReference']).is_file()
    trace = row['traceability']
    assert trace['inspection']=='source-inspected-runtime-not-run'
    assert trace['authorityProfileId'] and trace['evidenceProfileId']
    assert trace['configProfile'] in manifest['configProfiles']
    profile = manifest['contentProfiles'][trace['contentProfile']]
    assert all(profile.get(k) for k in ['readiness','version','contract'])
    assert set(trace['sourcePaths'])<=pins.keys()
    assert (ROOT/trace['authorityDecision']).is_file()
    assert (ROOT/trace['sourceManifest']).is_file()
    if row['kind']=='capability':
        feature=next(r for r in catalog['records'] if r['id']==row['featureId'])
        assert trace['productionEntries']==feature['productionEntryIds']==row['declaredEntries']
        assert trace['authorityProfileId']==feature['authorityProfileId']
        if not row['declaredEntries']:
            foundation_count += 1
            boundary=trace['consumerBoundary']
            assert boundary['provider'] in pins and boundary['consumer'] in pins
            assert row['foundationBoundary']==boundary['contract'] and len(boundary['contract'])>50
    if row['kind']=='lesson-mode':
        assert "routeName: '"+row['declaredRoute']+"'" in read('lib/features/learning/application/lesson_mode_registry.dart')
        assert trace['route']==row['declaredRoute']
    if row['kind']=='interaction-group':
        assert trace['relatedRecords'] and set(trace['relatedRecords'])<=rows.keys()
        assert ident in read(row['acceptanceReference'])
    if row['kind']!='interaction-group':
        for entry in trace['productionEntries']:
            assert "productionEntryId: '"+entry+"'" in read('lib/runtime/production_feature_contract.dart')
    for target in trace['testTargetInspection']:
        assert target['exists'] and (ROOT/target['path']).is_file()
        assert target['path'] in pins
        assert target['runtimeStatus']=='not-run-by-G0.5'
        test_targets.add(target['path'])
assert rows['MODE-matching']['traceability']['deliveryDefault']=='implementedOff'
assert rows['MODE-handwritingScratchpad']['traceability']['deliveryDefault']=='implementedOff'
assert rows['MG-10']['readingExposureIsNotQuestionAnswerAcceptance'] is True
assert manifest['configProfiles']['accepted-source-defaults']['cloudSyncDefault'] is True
assert manifest['runtimeVerified'] is False
assert not git('diff',SOURCE,'--','lib','test','assets','tool','pubspec.yaml','pubspec.lock').strip()
# Preserve historical and unrelated ledger semantics, including G0.3/G0.4 obligations.
for key in baseline:
    if key not in ['coverage','packages']:
        assert ledger[key]==baseline[key], key
for package in ledger['packages']:
    original=next(p for p in baseline['packages'] if p['id']==package['id'])
    if package['id']!='P0.5': assert package==original, package['id']
for ident,row in rows.items():
    for key in old[ident]:
        if key not in ['sourcePin','foundationBoundary','declaredEntry']:
            assert row[key]==old[ident][key], (ident,key)
# Local links in the package checkpoint and report resolve; no web fetch needed.
link_count=0
for name in ['docs/development/full-system/checkpoints/G0.5.md','docs/development/full-system/G0.5-coverage-traceability.md']:
    path=ROOT/name
    for link in re.findall(r'\]\(([^)]+)\)',path.read_text(encoding='utf-8')):
        if '://' not in link:
            target = (path.parent/link.split('#')[0]).resolve()
            assert target.is_file() or target == OUT/'verification.json', link
            link_count+=1
result={'schemaVersion':1,'packageId':'P0.5','sourceSha':SOURCE,
 'command':'python docs/development/full-system/evidence/G0.5/verify_traceability.py',
 'exitCode':0,'durationSeconds':round(time.monotonic()-started,3),
 'kind':'traceability-source-inspection','runtimeVerified':False,'status':'accepted',
 'counts':counts,'domains':8,'unassigned':0,'foundationBoundaries':foundation_count,
 'sourcePins':len(pins),'existingTestTargets':len(test_targets),'localLinks':link_count,
 'statusPreservation':{'needs-verification':71,'delivery-decision-pending':3,'promotedToVerifiedExisting':0},
 'sourceManifestSha256':sha((OUT/'source-manifest.json').read_bytes()),
 'ledgerSha256':sha((ROOT/LEDGER).read_bytes()),
 'verifierSha256':sha(Path(__file__).read_bytes()),
 'review':'74 identities, package references, mode/route/default config, content profiles, source/Git hashes, unchanged statuses and application inputs checked',
 'priorEvidence':{'path':'docs/development/full-system/evidence/G0.2/verification.json',
 'disposition':'prior accepted only; no new runtime PASS or gate invocation claimed'},
 'notRun':['Flutter','backend','Android','GPU','full release','physical/live/human'],
 'defects':['G05-OPS-01: broad initial output reduced to projections; wrong receipts path corrected to dispatches',
 'G05-OPS-02: discovery queried absent lib/core; subsequent searches use observed lib paths',
 'G05-DOC-01: parser required one space after dependencyId; changed to whitespace matching after inspecting multiline Adventure declaration',
 'G05-DOC-02: filtered hash-object changed CRLF CSV identity; stopped repeated command and verified raw blob, then used accepted blob bytes with explicit EOL-only classification']}
(OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
