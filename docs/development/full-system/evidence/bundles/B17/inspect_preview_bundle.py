"""Inspect and retain actual unsigned Flutter bundle bytes, without installing."""
import hashlib
import json
import re
import shutil
from pathlib import Path

root = Path.cwd()
bundle = root / 'build/flutter_assets'
out = Path('C:/Users/Phet/.codex/visualizations/2026/09/13/01a09c93-db97-7201-9675-bd181f19e76a/B17-artifacts')
out.mkdir(parents=True, exist_ok=True)
zip_path = out / 'local-preview-bundle.zip'
assert not zip_path.exists(), 'Refuse to overwrite captured artifact'
rows = []
for file in sorted(bundle.rglob('*')):
    if file.is_file():
        raw = file.read_bytes()
        rows.append({'path': file.relative_to(bundle).as_posix(), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
assets = sorted(set(re.findall(r'^\s*- (assets/[^\r\n]+)', Path('pubspec.yaml').read_text(), re.M)))
for name in assets:
    assert (bundle/name).read_bytes() == Path(name).read_bytes(), name
assert (bundle/'kernel_blob.bin').stat().st_size > 0
assert not list(bundle.rglob('candidate.tflite')), 'Unreleased candidate must not be bundled'
shutil.make_archive(str(zip_path.with_suffix('')), 'zip', bundle)
result = {'artifactPath': str(zip_path), 'artifactSha256': hashlib.sha256(zip_path.read_bytes()).hexdigest(),
          'files': rows, 'declaredAssetsVerified': len(assets),
          'profile': json.loads(Path('tool/cli/profiles/local-learning-preview.json').read_text()),
          'buildReceipt': 'G7.7-bundle-verifier.json',
          'claims': ['Actual debug kernel and asset bundle inspected and retained; all declared assets byte-identical',
                     'Profile bound by recorded compiler arguments plus B16 production-factory compiled tests',
                     'No independent kernel boolean decoding; installed-binary flags NOT RUN',
                     'Not an APK; no release build, signing, installation or native-device runtime proof',
                     'Baseline device model remains downloaded/pinned by production manifest; candidate is not packaged']}
Path(__file__).with_name('G7.7-bundle-inspection.json').write_bytes((json.dumps(result, indent=2)+'\n').encode())
print(json.dumps({k:v for k,v in result.items() if k!='files'}))
