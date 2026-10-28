import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path('C:/Users/Phet/.codex/worktrees/02fa/LexiQuest')
out = root / 'build/verification/contextual-practice-20260908'
def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

records = read(out / 'final-gates.json')
assert len(records) == 9
assert all(r['nativeExitCode'] == 0 and r['gateExitCode'] == 0 and r['sourceStable'] for r in records)
assert len({r['sourceFingerprint'] for r in records}) == 1
last = read(pathlib.Path(records[-1]['evidence']) / 'source-after.json')
changes = [f['path'] for f in last['files'] if sha(root / f['path']) != f['sha256']]
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
assert head == last['baseHead']
incremental = read(out / 'incremental-source-identity.json')
assert len(incremental) == 12
assert all(sha(root / f['path']) == f['afterSha256'] for f in incremental)
apk = read(out / 'final-apk-identity.json')
assert sha(pathlib.Path(apk['path'])) == apk['sha256']
assert sha(root / 'build/app/outputs/flutter-apk/app-debug.apk') == apk['sha256']
assert pathlib.Path(apk['path']).stat().st_size == apk['bytes']
summary = read(out / 'full-final.summary.json')
assert summary['doneSuccess'] and summary['passed'] == 4964 and summary['failed'] == 0 and not summary['parseFailures']
result = {'sourceFileCount':len(last['files']), 'sourceFingerprint':last['fingerprint'], 'changedPaths':changes, 'incrementalFiles':len(incremental), 'passed':summary['passed'], 'apkSha256':apk['sha256'], 'allNineGatesPassed':True}
(out / 'final-source-after-docs.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
assert not changes, 'A verified input changed after final checks'
