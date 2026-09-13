"""Audit actual Dart import closures and immutable bundle evidence bytes."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).parent

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def closure(targets):
    pending = list(targets)
    seen = set()
    while pending:
        name = pending.pop()
        path = (root / name).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            continue
        name = path.relative_to(root).as_posix()
        if name in seen:
            continue
        seen.add(name)
        source = path.read_text(encoding='utf-8-sig')
        for directive in re.findall(r'\b(?:import|export|part)\s+(?!of\b)[^;]+;', source):
            for ref in re.findall(r"['\"]([^'\"]+\.dart)['\"]", directive):
                if ref.startswith('package:vocab_learning_app/'):
                    pending.append('lib/' + ref.split('/', 1)[1])
                elif ':' not in ref:
                    pending.append(str(path.parent / ref))
    return seen | {'pubspec.yaml', 'pubspec.lock'}

checks = []
supplement = evidence / 'G7.5-architecture-verifier.json'
supplemental_pins = ({row['path']: row['sha256'].lower() for row in read_json(supplement)['inputClosure']}
                     if supplement.exists() else {})
for prefix in ['G7.3-research', 'G7.4-final', 'G7.5-default', 'G7.5-preview', 'G7.5-preview-journeys', 'G7.5-cefr-preview']:
    data = read_json(evidence / f'{prefix}-verifier.json')
    targets = [arg for command in data['selection'] for arg in command['Arguments']
               if arg.startswith('test/') and arg.endswith('.dart')]
    recorded = {row['path']: row['sha256'].lower() for row in data['inputClosure']}
    changed = []
    missing = []
    supplemental = []
    exact = 0
    for name in sorted(closure(targets)):
        actual = digest((root / name).read_bytes())
        if name not in recorded:
            if actual == supplemental_pins.get(name):
                supplemental.append(name)
            else:
                missing.append(name)
        elif actual != recorded.get(name):
            changed.append(name)
        else:
            exact += 1
    checks.append({'receipt': prefix, 'exactImportAndPackageInputs': exact, 'changed': changed,
                   'notPinnedByOriginalReceipt': missing, 'pinnedBySupplementalArchitectureGate': supplemental,
                   'scope': 'Own-package Dart import/export/part closure and pubspec pins; not blanket verifier fingerprint equality'})

(evidence / 'final-input-audit.json').write_bytes((json.dumps(checks, indent=2)+'\n').encode('utf-8'))
print(json.dumps(checks))

artifacts = []
for path in sorted([Path('docs/development/full-system/bundles/B16.md')] + list(evidence.rglob('*'))):
    if path.is_file() and path.name != 'B16-artifact-index.json':
        raw = path.read_bytes()
        artifacts.append({'path': path.as_posix(), 'bytes': len(raw), 'sha256': digest(raw)})
(evidence / 'B16-artifact-index.json').write_bytes((json.dumps({'artifacts': artifacts}, indent=2)+'\n').encode('utf-8'))

if '--committed' in __import__('sys').argv:
    blobs = {}
    for entry in subprocess.check_output(['git', 'ls-tree', '-rz', 'HEAD']).split(b'\0'):
        if entry:
            meta, name = entry.split(b'\t', 1)
            blobs[name.decode()] = meta.split()[2].decode()
    for item in artifacts:
        raw = subprocess.check_output(['git', 'cat-file', 'blob', blobs[item['path']]])
        assert digest(raw) == item['sha256'], item['path']
    print(f'Verified {len(artifacts)} committed artifact blobs')
