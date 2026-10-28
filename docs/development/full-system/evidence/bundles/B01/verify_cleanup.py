import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).parent
BASE = '6ab2e371fc4f7563da1ad8dc04a158d854b5dc20'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def git(*a): return subprocess.check_output(['git', *a], cwd=ROOT).decode().splitlines()
docs = read(OUT / 'G0.6-document-registry.json')
cleanup = read(OUT / 'G0.6-cleanup-dry-run.json')
assert len(cleanup['records']) == 76
assert not cleanup['plannedDeletes'] and not cleanup['plannedMoves']
tracked = set(git('ls-tree', '-r', '--name-only', BASE))
assert {r['path'] for r in docs['records']} == {p for p in tracked if p.startswith('docs/') or p == 'AGENTS.md'}
for r in docs['records'] + cleanup['records']:
    assert sha(ROOT / r['path']) == r['sha256'], r['path']
    assert git('rev-parse', BASE + ':' + r['path'])[0] == r['gitBlob']
    assert r['restore']['commit'] == BASE and r['restore']['path'] == r['path']
for r in cleanup['records']:
    assert r['disposition'] == 'retain-in-place' and not r['deletionEligible']
    assert all((ROOT / p).exists() for key in ['inboundLiteralReferences', 'testStemConsumers', 'goldenCounterparts'] for p in r[key])
    blob = subprocess.check_output(['git', 'cat-file', 'blob', r['gitBlob']], cwd=ROOT)
    assert hashlib.sha256(blob).hexdigest() == r['restore']['expectedSha256']
changes = git('diff', '--name-only', BASE)
assert all(p.startswith('docs/') for p in changes), changes
assert not git('diff', '--name-only', '--diff-filter=D', BASE)
# Previous migration proved the unchanged queue and its 611 links. Check bytes before reuse.
old = ROOT / 'docs/development/full-system/evidence/bundles-4'
pins = read(old / 'source-manifest.json')['files']
changed = 'docs/development/full-system-active-index.md'
reused = []
eol = []
for pin in pins:
    if pin['path'] != changed:
        raw = (ROOT / pin['path']).read_bytes()
        baseline = subprocess.check_output(['git', 'show', BASE + ':' + pin['path']], cwd=ROOT)
        assert raw.replace(b'\r\n', b'\n') == baseline.replace(b'\r\n', b'\n'), pin['path']
        representations = [raw, baseline, baseline.replace(b'\r\n', b'\n'), baseline.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')]
        assert pin['sha256'] in {hashlib.sha256(b).hexdigest() for b in representations}, pin['path']
        if sha(ROOT / pin['path']) != pin['sha256']:
            eol.append({'path': pin['path'], 'workingSha256': sha(ROOT / pin['path']), 'recordedSha256': pin['sha256'], 'reason': 'EOL-only; accepted Git blob content unchanged'})
        reused.append(pin['path'])
links = 0
for p in [ROOT / changed, ROOT / 'docs/development/full-system/bundles/B01.md']:
    for dest in re.findall(r'\]\(([^)]+)\)', p.read_text(encoding='utf-8')):
        if '://' in dest or dest.startswith('#'):
            continue
        target = dest.split('#')[0]
        assert (p.parent / target).resolve().exists(), (p, dest)
        links += 1
result = {'schemaVersion': 1, 'packageId': 'G0.6', 'bundleId': 'B01', 'status': 'passed',
          'kind': 'cleanup-review', 'sourceSha': BASE, 'runtimeVerified': False,
          'documents': len(docs['records']), 'failureCandidates': len(cleanup['records']),
          'restoreBlobsVerified': 76, 'changedDocumentLinks': links,
          'eolOnlyReuse': eol,
          'deletions': 0, 'moves': 0, 'applicationDelta': 0,
          'requirements': {'PLAN-04': 'Current index supersedes stale context/speech identity observations without rewriting historical evidence.',
                           'PLAN-10': 'All76 candidates have refs/hash/archive/restore and justified retain disposition.',
                           'G0': 'Cleanup disposition ready; formula/edition gates pending.'},
          'reused': {'workflow': str(old.relative_to(ROOT) / 'verification.json'), 'unchangedPins': len(reused),
                     'G0.4': 'No change to bounded-verifier source/dependency/config; accepted CLI results retained.',
                     'G0.5': 'No change to application/content/coverage source pins; no new runtime PASS.'},
          'fingerprints': {p.name: sha(p) for p in [OUT / 'G0.6-document-registry.json', OUT / 'G0.6-cleanup-dry-run.json', Path(__file__)]},
          'review': 'No protected files deleted; all76 Git archive blobs recover exact working bytes; active Master and serial64 requirement/20 bundle queue retain validated migration inputs.'}
(OUT / 'G0.6-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
