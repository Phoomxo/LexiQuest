from pathlib import Path
import difflib
import hashlib
import json

root = Path.cwd()
evidence = root / 'build/verification/motivation-ui-20260908'
baseline = evidence / 'c1-baseline'
changes, chunks = [], []
for folder in ('lib', 'test'):
    for current in sorted((root / folder).rglob('*.dart')):
        relative = current.relative_to(root).as_posix()
        before = baseline / relative
        original = before.read_bytes() if before.is_file() else b''
        actual = current.read_bytes()
        if original == actual:
            continue
        changes.append({'path': relative, 'sha256': hashlib.sha256(actual).hexdigest()})
        chunks.extend(difflib.unified_diff(
            original.decode('utf-8-sig').splitlines(True),
            actual.decode('utf-8-sig').splitlines(True),
            fromfile='c1-baseline/' + relative, tofile=relative, n=6,
        ))
(evidence / 'reports/C1-integration.diff').write_text(''.join(chunks), encoding='utf-8')
(evidence / 'reports/C1-changed-files.json').write_text(json.dumps(changes, indent=2), encoding='utf-8')
print(json.dumps({'changedFiles': len(changes), 'paths': [e['path'] for e in changes]}))
