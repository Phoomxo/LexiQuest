import difflib
import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path('C:/Users/Phet/.codex/worktrees/02fa/LexiQuest')
out = root / 'build/verification/contextual-practice-20260908'
baseline = {item['path']: item['sha256'] for item in json.loads((out / 'baseline.json').read_text(encoding='utf-8-sig'))}
paths = subprocess.check_output(['git', 'ls-files', '-c', '-o', '--exclude-standard', '--', 'lib', 'test', 'integration_test'], cwd=root, text=True, encoding='utf-8').splitlines()
changes = []
diff = []
for name in sorted(set(paths)):
    path = root / name
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest == baseline.get(name):
        continue
    changes.append({'path': name, 'beforeSha256': baseline.get(name), 'afterSha256': digest})
    previous = out / 'baseline' / name
    before = previous.read_text(encoding='utf-8').splitlines(keepends=True) if previous.exists() else []
    after = path.read_text(encoding='utf-8').splitlines(keepends=True)
    diff.extend(difflib.unified_diff(before, after, fromfile='prior-approved-ui/' + name, tofile='current/' + name))
(out / 'incremental-source-identity.json').write_text(json.dumps(changes, indent=2), encoding='utf-8')
(out / 'incremental-source.diff').write_text(''.join(diff), encoding='utf-8')
print(json.dumps({'changedFiles': len(changes), 'paths': [item['path'] for item in changes]}, ensure_ascii=False))
