"""Hash the declared Flutter and AI API inputs for a frozen verification run."""

from hashlib import sha256
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
paths = {
    p for folder in ('lib', 'test', 'assets')
    for p in (root / folder).rglob('*')
    if p.is_file() and 'test/screens/failures/' not in p.relative_to(root).as_posix()
}
paths.update(root / name for name in (
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    'backend/ai_api/pyproject.toml', 'backend/ai_api/uv.lock',
    '.github/workflows/ci.yml',
))
paths.update((root / 'backend/ai_api/src').rglob('*.py'))
paths.update((root / 'backend/ai_api/tests').rglob('*.py'))
assert paths and all(p.is_file() and p.is_relative_to(root) for p in paths)
lines = [f'{p.relative_to(root).as_posix()}\t{sha256(p.read_bytes()).hexdigest()}'
         for p in sorted(paths, key=lambda p: p.relative_to(root).as_posix())]
target = root / sys.argv[1]
assert target.parent == root / 'build' and target.suffix == '.tsv'
target.write_bytes(('\n'.join(lines) + '\n').encode())
print(f'{len(paths)} inputs; {sha256(target.read_bytes()).hexdigest()}')
