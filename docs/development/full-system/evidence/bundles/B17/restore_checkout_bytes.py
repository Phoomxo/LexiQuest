"""Restore only checkout EOL transformations to accepted Git bytes."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path.cwd()
records = []
reader = subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
for entry in subprocess.check_output(['git', 'ls-tree', '-rz', 'HEAD']).split(b'\0'):
    if not entry:
        continue
    meta, name = entry.split(b'\t', 1)
    path = root / name.decode()
    reader.stdin.write(meta.split()[2] + b'\n')
    reader.stdin.flush()
    size = int(reader.stdout.readline().split()[2])
    raw = reader.stdout.read(size)
    assert reader.stdout.read(1) == b'\n'
    actual = path.read_bytes()
    if actual == raw:
        continue
    if b'\0' not in raw and actual.replace(b'\r\n', b'\n') == raw.replace(b'\r\n', b'\n'):
        path.write_bytes(raw)
        records.append({'path': name.decode(), 'sha256': hashlib.sha256(raw).hexdigest()})
    else:
        raise RuntimeError('Non-EOL difference: ' + name.decode())
reader.stdin.close()
reader.wait()
Path(__file__).with_name('checkout-byte-restoration.json').write_text(json.dumps({'note': 'Prior per-file reader stopped for batching after partial EOL-only restoration; list covers remaining transformations.', 'remainingRestored': records}, indent=2))
print(f'Restored {len(records)} EOL-only checkout transformations')
