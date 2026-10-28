"""Verify checkpoint integrity; explicitly does not certify semantic coverage."""
import ast
import collections
import hashlib
import json
import subprocess
from pathlib import Path

ROOT=Path.cwd()
OUT=Path(__file__).resolve().parent
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
inventory=read(OUT/'G8.1-inventory.json')
ledger=read(OUT/'G8.2-review-ledger.json')
assert len(ledger['files'])==inventory['trackedCount']
assert len({r['path'] for r in ledger['files']})==len(ledger['files'])
expected={r['path']:r for r in inventory['files']}
amendment=read(OUT/'context-continuation-amendment.json')
authorized={r['path']:r for r in amendment['files']}
assert set(authorized)=={
    'docs/development/full-system-active-index.md',
    'docs/development/full-system-package-workflow.md',
    'docs/development/2026-09-13-rule-supersession-register.md',
}
assert amendment['applicationSourceChanged'] is False
for row in ledger['files']:
    assert row['sha256']==expected[row['path']]['sha256']
    change=authorized.get(row['path'])
    if change:
        assert change['frozenSha256']==row['sha256'],row['path']
    actual_expected=change['checkpointSha256'] if change else row['sha256']
    assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==actual_expected,row['path']
    if row['category'] in {'handwritten-source','configuration','generated'}:
        assert row['zone'] in {f'REV-{i:02}' for i in range(1,13)},row['path']
    if row['status'] in {'reviewed-no-actionable-finding','reviewed-with-findings'}:
        assert row['reviewerPassDate'] and row.get('reviewNotes'),row['path']
for script in OUT.glob('*.py'):
    ast.parse(script.read_text(encoding='utf-8'),filename=str(script))
untracked=subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z']).decode().split('\0')
ignored=subprocess.check_output(['git','ls-files','--others','--ignored','--exclude-standard','-z']).decode().split('\0')
assert not [p for p in untracked if p and not p.startswith('docs/development/full-system/evidence/bundles/B18/')],untracked
status=collections.Counter(r['status'] for r in ledger['files'] if r['zone'])
report=dict(sourceSha=inventory['sourceSha'],trackedRawBytesVerified=len(ledger['files']),
    frozenRawBytesUnchanged=len(ledger['files'])-len(authorized),
    authorizedPolicyAmendments=list(authorized.values()),
    sourceAndConfigStatus=dict(status),ignoredFiles=[p for p in ignored if p],
    newReviewTooling=[p for p in untracked if p],
    semanticReviewComplete=False,G82Accepted=False,G83Started=False,B19Dispatched=False,
    runtimeTestsRun=False,validation='Integrity only; source-read observations and candidate findings are not full semantic acceptance')
(OUT/'checkpoint-integrity.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps(report))
