"""Read-only input/byte audit; does not rerun inherited passed tests."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[6]
sys.path.insert(0, str(ROOT / 'tools'))
from camera_development_evaluation import load_inputs, validate_development, fingerprint, prediction_metrics
EVIDENCE = Path(__file__).parent

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def closure(path, relocate=False):
    gate = read(path)
    result = dict(gate=str(path.relative_to(ROOT)), fingerprint=gate['fingerprint'],
                  raw_exact=0, lf_crlf_only=0, evidence_attributes_only=[], differences=[])
    for entry in gate['inputClosure']:
        source = ROOT / entry['path']
        if relocate and entry['path'] == 'test/b11a_candidate_runtime_probe_test.dart':
            source = ROOT / 'docs/development/full-system/evidence/bundles/B11A/candidate_runtime_test.dart'
        if not source.exists():
            result['differences'].append(dict(path=entry['path'], reason='missing')); continue
        raw = source.read_bytes(); expected = entry['sha256'].lower()
        if digest(raw) == expected:
            result['raw_exact'] += 1
        elif expected in [digest(raw.replace(b'\r\n', b'\n')),
                          digest(raw.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))]:
            result['lf_crlf_only'] += 1
        elif entry['path'] == '.gitattributes':
            result['evidence_attributes_only'].append(entry['path'])
        else:
            result['differences'].append(dict(path=entry['path'], expected=expected, actual=digest(raw)))
    if result['differences']:
        raise ValueError(result)
    return result

gates = [closure(ROOT/'docs/development/full-system/evidence/bundles/B11/G5.3-final/targeted-learning-9b2f24f0c92c67c196b6882b108f5aa49486fcb34a18d324bfb24755ffc1a1a4.json')]
probe_dir = ROOT/'docs/development/full-system/evidence/bundles/B11A/G5.3c-runtime-passed'
gates.append(closure(next(probe_dir.glob('targeted-*.json')), True))
gates.append(closure(next((EVIDENCE/'G5.5-manifest-gate').glob('targeted-*.json'))))
config = read(EVIDENCE/'G5.4-config.json')
rows, predictions = load_inputs(config)
freeze = validate_development(rows, config, read(EVIDENCE/'G5.4-freeze.json'))
metrics = prediction_metrics(config['labels'], config['threshold'], predictions)
recorded_metrics = read(EVIDENCE/'G5.5-metrics.json')
for key in metrics:
    if key != 'scope' and metrics[key] != recorded_metrics[key]:
        raise ValueError('Metric recomputation differs: '+key)
legacy = []
for path in ['tools/camera_accuracy.py','tools/test_camera_accuracy.py']:
    accepted = subprocess.check_output(['git','show','e1b3fcb17fbdbdab158780142383f3ee15d8da0a:'+path],cwd=ROOT)
    pin = dict(path=path, sha256=digest(accepted))
    raw = (ROOT/pin['path']).read_bytes()
    variants = [raw, raw.replace(b'\r\n',b'\n'), raw.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')]
    if pin['sha256'] not in [digest(v) for v in variants]:
        raise ValueError('F3/F4 source changed')
    legacy.append(dict(path=pin['path'], expected=pin['sha256'], actual=digest(raw),
                       byteIdentity='raw' if digest(raw)==pin['sha256'] else 'LF/CRLF only'))
source_delta = subprocess.check_output(['git','diff','93eb652a1a550e496262cba4e7b5602da84ede8e','HEAD','--',
                                        'lib','test','tool/cli','pubspec.yaml','pubspec.lock'],cwd=ROOT)
if source_delta:
    raise ValueError('Production/runtime delta requires new scoped verification')
attribute_delta = subprocess.check_output(['git','diff','93eb652a1a550e496262cba4e7b5602da84ede8e','HEAD','--','.gitattributes'],cwd=ROOT).decode()
for line in attribute_delta.splitlines():
    if line.startswith('+') and not line.startswith('+++') and line != '+':
        if not line.startswith('+docs/development/full-system/evidence/bundles/B12/'):
            raise ValueError('Unexpected attribute policy change')
result = dict(status='passed', gates=gates, legacyPythonSource=legacy,
    legacyPythonGate='G0.2/python-run.json exit0; exact accepted e1b3fcb1 source plus explicit EOL comparison. Precommit repair-manifest pins were stale; not used as final source authority. Not a fresh run.',
    gateReuse='No rerun of unchanged passed tests. Global fingerprints are not claimed equal: B12 evidence attributes and LF/CRLF explicitly audited. Runtime source/dependencies unchanged from B11A.',
    candidateModel=config['candidate_model'], validationSamples=len(predictions),
    freezeFingerprint=fingerprint(freeze), metricsRecomputed=True,
    productionDelta=False, freshTestOpened=False)
with (EVIDENCE/'G5.6-input-audit.json').open('x',encoding='utf-8',newline='\n') as stream:
    json.dump(result,stream,indent=2,allow_nan=False); stream.write('\n')
print(json.dumps(result))
