"""Read-only complete source/fixture manifest for the approved final gates."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[2]
if Path.cwd().resolve() != root:
    raise SystemExit('Wrong worktree')
scopes = [
    'lib', 'test', 'integration_test', 'test_driver', 'android', 'ios',
    'linux', 'macos', 'windows', 'web', 'assets', 'tool', 'tools', 'backend',
    'supabase', 'package.json', 'package-lock.json', 'firebase.json',
    'firestore.rules', 'firestore.indexes.json', 'storage.rules',
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'dart_test.yaml',
    'docs/generated', 'docs/database', 'docs/field', 'docs/runbooks',
    'docs/superpowers', '.github', 'osv-scanner.toml',
    'hosting/public/.well-known/assetlinks.json',
]
raw = subprocess.check_output(
    ['git', 'ls-files', '-z', '-c', '-o', '--exclude-standard', '--', *scopes]
)
paths = {p.decode('utf-8') for p in raw.split(b'\0') if p}
paths.add('.dart_tool/package_config.json')
paths.update(p.relative_to(root).as_posix() for p in (root / '.superpowers/sdd').iterdir()
             if p.is_file() and (p.name.startswith('motivation-') or p.name in {
                 'device-current-source-gate.ps1', 'ui-final-cli-tests.ps1',
                 'pm8-summarize-flutter.ps1'}))
entries = []
deleted = []
known_deleted_path = 'lib/learning/storage/learning_database.g.dart'
known_deleted_blob = '8b137891791fe96927ad78e64b0aad7bded08bdc'
for rel in sorted(paths):
    original = root / rel
    path = original.resolve()
    if not path.is_relative_to(root):
        raise SystemExit(f'Invalid manifest input: {rel}')
    if not path.is_file():
        if rel != known_deleted_path or original.exists() or original.is_symlink():
            raise SystemExit(f'Invalid manifest input: {rel}')
        index = subprocess.check_output(
            ['git', 'ls-files', '--stage', '--', rel], text=True,
        ).strip()
        if index != f'100644 {known_deleted_blob} 0\t{rel}':
            raise SystemExit(f'Unreviewed deleted source identity: {rel}')
        deleted.append({'path': rel, 'indexBlob': known_deleted_blob})
        continue
    entries.append({'path': rel, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
canonical = '\n'.join(sorted(
    [e['path'] + '\0' + e['sha256'] for e in entries]
    + [e['path'] + '\0DELETED\0' + e['indexBlob'] for e in deleted]
))
record = {
    'utc': datetime.now(timezone.utc).isoformat(),
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'fingerprint': hashlib.sha256(canonical.encode()).hexdigest(),
    'fileCount': len(entries), 'files': entries, 'deletedTrackedFiles': deleted,
}
destination = root / sys.argv[1]
destination.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in record.items() if k != 'files'}))
