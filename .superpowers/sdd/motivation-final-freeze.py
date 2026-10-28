"""F0: reviewable incremental inventory and read-only formatting/diff checks."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[2]
if Path.cwd().resolve() != root:
    raise SystemExit('Wrong worktree')
evidence = root / 'build/verification/motivation-ui-20260908'
baseline = evidence / 'baseline'
stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
out = evidence / 'logs' / ('f0-' + stamp)
out.mkdir()
changes = []
for folder in ('lib', 'test', 'integration_test', 'test_driver', 'tool', 'tools'):
    for current in sorted((root / folder).rglob('*.dart')):
        rel = current.relative_to(root).as_posix()
        original = baseline / rel
        if original.is_file() and original.read_bytes() == current.read_bytes():
            continue
        changes.append({'path': rel, 'sha256': hashlib.sha256(current.read_bytes()).hexdigest()})
(evidence / 'reports/Motivation-incremental-files.json').write_text(json.dumps(changes, indent=2), encoding='utf-8')

def snapshot(name):
    path = out / name
    subprocess.run([sys.executable, '.superpowers/sdd/motivation-source-manifest.py', str(path)], check=True, stdout=subprocess.DEVNULL)
    return json.loads(path.read_text(encoding='utf-8'))

before = snapshot('whole-source-before.json')
commands = [
    ('diff-check', ['git', 'diff', '--check']),
    ('format-check', ['C:/Users/Phet/AppData/Local/Programs/flutter/bin/dart.bat', 'format', '--output=none', '--set-exit-if-changed', *[c['path'] for c in changes]]),
]
records = []
for label, args in commands:
    result = subprocess.run(args, cwd=root, capture_output=True)
    (out / (label + '.stdout.log')).write_bytes(result.stdout)
    (out / (label + '.stderr.log')).write_bytes(result.stderr)
    records.append({'label': label, 'command': args, 'exit': result.returncode})
after = snapshot('whole-source-after.json')
stable = before['fingerprint'] == after['fingerprint'] and before['head'] == after['head']
record = {'passed': stable and all(r['exit'] == 0 for r in records), 'wholeSourceStable': stable,
          'wholeSourceFingerprint': before['fingerprint'], 'fileCount': before['fileCount'],
          'incrementalDartFiles': len(changes), 'records': records}
(out / 'result.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in record.items() if k != 'records'}))
print(str(out))
raise SystemExit(0 if record['passed'] else 1)
