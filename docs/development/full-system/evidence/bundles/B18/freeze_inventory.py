"""Inventory accepted Git bytes; restore only proven checkout EOL changes."""
import collections
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path.cwd()
OUT = Path(__file__).resolve().parent
BASE = 'b0321b3416ca67c9098644f5df59d353071cfdc3'

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def save(name, value):
    (OUT / name).write_bytes((json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode())

def classify(name, raw):
    p = Path(name)
    if p.suffix in {'.cjs', '.rc'}:
        return 'handwritten-source', 'Executable JavaScript or native resource source'
    if p.suffix in {'.pro', '.example', '.xcsettings', '.storyboard', '.xib', '.manifest'}:
        return 'configuration', 'Native build, UI or runtime configuration'
    if p.name == 'LICENSE' or p.suffix in {'.svg', '.jsonl', '.ico'}:
        return 'reference', 'License, visual reference, training log or native icon'
    if name.endswith(('.g.dart', '.freezed.dart')) or 'generated_plugin' in name or 'GeneratedPluginRegistrant' in name:
        return 'generated', 'Review generator, dependencies and reproducibility in REV-12'
    if name.startswith('assets/'):
        return 'asset', 'Pinned content/model/font/media input; inspect manifest and consumers'
    if p.suffix.lower() in {'.md', '.pdf', '.docx', '.log', '.png', '.jpg', '.jpeg', '.webp', '.gif', '.ttf', '.tflite', '.zip', '.csv'}:
        return 'reference', 'Documentation, retained evidence, fixture or binary input; not executable source'
    if p.suffix.lower() in {'.dart','.py','.ps1','.psm1','.sh','.bat','.cmd','.js','.ts','.tsx','.jsx','.kt','.kts','.java','.swift','.m','.mm','.h','.cpp','.c','.cc','.sql','.rules','.html'} or p.name in {'Dockerfile','CMakeLists.txt','Makefile','gradlew'}:
        return 'handwritten-source', 'Semantic review required, including historical executable tools'
    if p.suffix.lower() in {'.json','.yaml','.yml','.toml','.xml','.plist','.lock','.properties','.xcconfig','.entitlements','.gradle','.txt','.cmake','.config','.pbxproj','.xcscheme','.xcworkspacedata'} or p.name.startswith('.') or p.name == 'Podfile':
        if name.startswith('docs/'):
            return 'reference', 'Retained structured evidence/plan; inspect authoritative pins and consumers'
        return 'configuration', 'Review build/dependency/runtime or fixture input semantics'
    return 'unclassified', 'Manual disposition required'

reader = subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
rows, restored = [], []
for entry in subprocess.check_output(['git', 'ls-tree', '-rz', BASE]).split(b'\0'):
    if not entry:
        continue
    meta, encoded = entry.split(b'\t', 1)
    mode, kind, blob = meta.split()
    assert kind == b'blob', entry
    name = encoded.decode()
    reader.stdin.write(blob + b'\n'); reader.stdin.flush()
    size = int(reader.stdout.readline().split()[2])
    raw = reader.stdout.read(size)
    assert reader.stdout.read(1) == b'\n'
    actual = (ROOT / name).read_bytes()
    if actual != raw:
        assert b'\0' not in raw and actual.replace(b'\r\n', b'\n') == raw.replace(b'\r\n', b'\n'), name
        (ROOT / name).write_bytes(raw)
        restored.append(name)
    category, reason = classify(name, raw)
    rows.append(dict(path=name, blob=blob.decode(), sha256=digest(raw), bytes=size,
                     lines=raw.count(b'\n'), category=category, rationale=reason,
                     status='pending-review' if category in {'handwritten-source','configuration','unclassified'} else 'classified'))
reader.stdin.close()
assert reader.wait() == 0
untracked = subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z']).decode().split('\0')
save('G8.1-inventory.json', dict(sourceSha=BASE, trackedCount=len(rows),
     counts=dict(collections.Counter(r['category'] for r in rows)), files=rows,
     untracked=[dict(path=n, disposition='B18 review tooling; review delta before final freeze') for n in untracked if n]))
save('checkout-byte-audit.json',dict(sourceSha=BASE, checked=len(rows), restoredEolOnly=restored, nonEolDifferences=[]))
print(json.dumps(dict(files=len(rows),restored=len(restored),counts=collections.Counter(r['category'] for r in rows))))
for row in rows:
    if row['category']=='unclassified': print(row['path'])
