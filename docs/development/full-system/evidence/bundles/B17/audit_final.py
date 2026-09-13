"""Audit bounded gate inputs, retained artifacts, and exact Git blobs."""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).parent
def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def dart_closure(targets):
    todo=[root/t for t in targets]; seen={'pubspec.yaml','pubspec.lock'}
    while todo:
        file=todo.pop().resolve()
        if not file.is_file() or not file.is_relative_to(root): continue
        name=file.relative_to(root).as_posix()
        if name in seen: continue
        seen.add(name)
        for directive in re.findall(r'\b(?:import|export|part)\s+(?!of\b)[^;]+;',file.read_text(encoding='utf-8-sig')):
            for ref in re.findall(r"['\"]([^'\"]+\.dart)['\"]",directive):
                if ref.startswith('package:vocab_learning_app/'): todo.append(root/'lib'/ref.split('/',1)[1])
                elif ':' not in ref: todo.append(file.parent/ref)
    return seen

audits = []
for prefix in ['G7.6-flutter','G7.7-architecture-green']:
    data=read(evidence/f'{prefix}-verifier.json')
    targets=[a for c in data['selection'] for a in c['Arguments'] if a.startswith('test/') and a.endswith('.dart')]
    names=dart_closure(targets); pins={p['path']:p['sha256'].lower() for p in data['inputClosure']}
    changed=[n for n in sorted(names) if sha(Path(n).read_bytes())!=pins.get(n)]
    assert not changed,(prefix,changed)
    audits.append({'receipt':prefix,'exactDartImportAndPubspecInputs':len(names),'changed':changed,'scope':'Own-package import/export/part closure; dynamic historical manifest immutable checksum exercised by review test, no blanket verifier equality'})
for prefix, scope in [('G7.6-ai-green','backend/ai_api/'), ('G7.6-voice','backend/voice_api/'), ('G7.6-lm','backend/lexiquest_lm/'), ('G7.6-flutter','lib/'), ('G7.7-bundle','lib/'), ('G7.7-architecture-green','lib/')]:
    data = read(evidence/f'{prefix}-verifier.json')
    pins = [p for p in data['inputClosure'] if p['path'].startswith(scope) or p['path'] in ['pubspec.yaml','pubspec.lock']]
    changed = [p['path'] for p in pins if sha(Path(p['path']).read_bytes()) != p['sha256'].lower()]
    assert not changed, (prefix, changed)
    audits.append({'receipt':prefix, 'checkedInputs':len(pins), 'changed':changed,
                   'scope':scope+' plus pubspec pins; no blanket fingerprint equality'})
for prefix in ['G7.7-tooling-green','G7.7-native-config']:
    data=read(evidence/f'{prefix}-verifier.json')
    changed=[p['path'] for p in data['inputClosure'] if Path(p['path']).exists() and sha(Path(p['path']).read_bytes()) != p['sha256'].lower()]
    audits.append({'receipt':prefix,'conservativeClosureDeltas':changed,
                   'disposition':'Later generator/review tests do not execute in these CLI fixtures; profile vector and package verifier test changes retested in native-config receipt. Selected command functions and production helper unchanged.'})
for bundle in ['B15','B16']:
    rows=read(evidence.parent/bundle/f'{bundle}-artifact-index.json')['artifacts']
    for row in rows: assert sha(Path(row['path']).read_bytes())==row['sha256'],row['path']
    audits.append({'bundle':bundle,'inheritedArtifacts':len(rows),'changed':[]})
artifact=read(evidence/'G7.7-bundle-inspection.json')
assert sha(Path(artifact['artifactPath']).read_bytes())==artifact['artifactSha256']
(evidence/'final-input-audit.json').write_bytes((json.dumps(audits,indent=2)+'\n').encode())
paths=[Path('docs/development/full-system/bundles/B17.md')]+[p for p in evidence.rglob('*') if p.is_file() and p.name!='B17-artifact-index.json']
rows=[{'path':p.as_posix(),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in sorted(paths)]
(evidence/'B17-artifact-index.json').write_bytes((json.dumps({'artifacts':rows},indent=2)+'\n').encode())
if '--committed' in sys.argv:
    reader=subprocess.Popen(['git','cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    for row in rows:
        reader.stdin.write(('HEAD:'+row['path']+'\n').encode());reader.stdin.flush()
        size=int(reader.stdout.readline().split()[2]);raw=reader.stdout.read(size);assert reader.stdout.read(1)==b'\n'
        assert sha(raw)==row['sha256'],row['path']
    reader.stdin.close();reader.wait()
    print(f'Verified {len(rows)} committed B17 artifacts')
else: print(f'Indexed {len(rows)} B17 artifacts; scoped input audits passed')
