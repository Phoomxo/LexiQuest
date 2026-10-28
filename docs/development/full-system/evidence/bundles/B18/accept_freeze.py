"""Validate predecessor acceptance and retained pins without rerunning gates."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path.cwd()
OUT = Path(__file__).resolve().parent
CONTROL = Path('C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/full-system-orchestration')
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
state = read(CONTROL/'run-state.json')
handoff = read(CONTROL/'handoffs/bundles/B17.json')
inventory = read(OUT/'G8.1-inventory.json')
assert inventory['counts'].get('unclassified', 0) == 0
assert subprocess.check_output(['git','rev-parse','HEAD']).decode().strip() == handoff['acceptedSourceSha']
assert state['currentWriter']['bundleId']=='B18'
packages=[]
for p in state['packageStates']:
    if p['ordinal'] >= 59: continue
    assert p['status']=='accepted', p
    packages.append({k:p.get(k) for k in ['displayId','status','acceptedSourceSha','handoffPath']})
artifacts=[]
for bundle in ['B15','B16','B17']:
    index=ROOT/f'docs/development/full-system/evidence/bundles/{bundle}/{bundle}-artifact-index.json'
    rows=read(index)['artifacts']
    for row in rows:
        assert sha(ROOT/row['path'])==row['sha256'],row['path']
    artifacts.append(dict(bundle=bundle,artifacts=len(rows),indexSha256=sha(index)))
pins=[]
for label,p,key in [('dataset',handoff['dataset'],'path'),('candidate',handoff['candidate'],'localArtifactPath')]:
    expected=p.get('sha256') or p['expectedSha256']
    assert sha(Path(p[key])) == expected, label
    pins.append(dict(kind=label,path=p[key],sha256=expected))
for name in ['pubspec.yaml','pubspec.lock','firestore.rules','storage.rules','lib/features/device_model/domain/model_manifest.dart','docs/generated/alltcas-8-44-final-test-plan.json']:
    pins.append(dict(kind='source-config',path=name,sha256=sha(ROOT/name)))
result=dict(sourceSha=handoff['acceptedSourceSha'],planRevision=state['planRevision'],
    priorPackages=packages,artifacts=artifacts,pins=pins,trackedFiles=inventory['trackedCount'],
    reviewCounts=inventory['counts'],applicationWriterFrozen=True,
    evidenceReuse='No production source changed from B17. Prior results retain their exact original scopes and limits; no new runtime PASS.',
    inheritedHandoffSha256=sha(CONTROL/'handoffs/bundles/B17.json'),
    inheritedConstraints=handoff)
(OUT/'G8.1-acceptance.json').write_bytes((json.dumps(result,indent=2,ensure_ascii=False)+'\n').encode())
print(json.dumps(dict(packages=len(packages),artifacts=artifacts,pins=len(pins),files=inventory['trackedCount'])))
