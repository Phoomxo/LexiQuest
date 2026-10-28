"""Final packaging review; reuse passed package gates with unchanged inputs."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[6]
OUT=Path(__file__).parent
BASE='6ab2e371fc4f7563da1ad8dc04a158d854b5dc20'
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
gates={p:read(OUT/f'{p}-verification.json') for p in ['G0.6','G0.7','G0.8']}
assert all(g['status']=='passed' and g['runtimeVerified'] is False for g in gates.values())
for name,value in gates['G0.6']['fingerprints'].items(): assert sha(OUT/name)==value
assert sha(OUT/'G0.7-formula-registry.json')==gates['G0.7']['registrySha256']
assert sha(OUT/'G0.8-edition-contract.json')==gates['G0.8']['editionContractSha256']
for g in ['G0.7','G0.8']:
    for name,value in gates[g]['sourcePins'].items(): assert sha(ROOT/name)==value
    verifier='verify_formulas.py' if g=='G0.7' else 'verify_edition.py'
    assert sha(OUT/verifier)==gates[g]['verifierSha256']
changes=subprocess.check_output(['git','diff','--name-only',BASE],cwd=ROOT).decode().splitlines()
untracked=subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=ROOT).decode().splitlines()
allowed=['docs/development/full-system/evidence/bundles/B01/','docs/development/full-system/bundles/B01.md','docs/development/full-system-active-index.md']
for p in changes+untracked: assert any(p.startswith(a) for a in allowed),p
assert not subprocess.check_output(['git','diff','--name-only','--diff-filter=D',BASE],cwd=ROOT).strip()
defects=read(OUT/'defects.json')['defects']
openDefects=[d['id'] for d in defects if d['status']!='closed']
assert openDefects==['B01-FORM-01','B01-FORM-02']
for d in defects:
    if d['id'] in openDefects: assert d['owners'] and d['blocks'] and d['status']=='open-owned-downstream'
report=ROOT/'docs/development/full-system/bundles/B01.md'
links=[]
for dest in re.findall(r'\]\(([^)]+)\)',report.read_text(encoding='utf-8')):
    if '://' not in dest and not dest.startswith('#'):
        assert (report.parent/dest.split('#')[0]).resolve().exists(),dest
        links.append(dest)
result={'schemaVersion':1,'bundleId':'B01','status':'passed','kind':'final-package-review',
        'baseSha':BASE,'reusedGates':{p:sha(OUT/f'{p}-verification.json') for p in gates},
        'reportSha256':sha(report),'reportLinks':len(links),'defectsSha256':sha(OUT/'defects.json'),
        'openOwnedDefects':openDefects,'applicationChanges':0,'deletedFiles':0,
        'reviewedChanges':sorted(set(changes+untracked)),
        'reviewMode':'Single-writer self-review; no subagent permitted by project guardrails',
        'requirementReview':{'G0.6':'373 documents classified,76 retained failure PNGs have reference/hash/restore dispositions; one active Master',
                             'G0.7':'12 source/version/denominator registries and60 explicit fixtures; known differences separated from proposals and assigned',
                             'G0.8':'4 edition decisions,74 activation records, target/content/profile source binding, D01–D12 and verifier gaps adopted',
                             'G0':'Development-readiness accepted; no runtime coverage/remote/deployment/research/cost authority expansion'},
        'riskReview':'Only documents/structured inspection helpers changed. G0.7 explicitly permits recording implementation differences for owning packages; open FORM defects cannot be treated as their downstream runtime acceptance.',
        'runtimeVerified':False}
(OUT/'bundle-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'passed','reusedGates':3,'reportLinks':len(links),'openOwnedDefects':openDefects,'applicationChanges':0}))
