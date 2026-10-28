"""Copy the selected bounded verifier receipt and its raw logs into B16."""
import json
import shutil
import sys
from pathlib import Path

evidence = Path(__file__).parent
receipt = Path(sys.argv[1])
prefix = sys.argv[2]
raw = receipt.read_bytes()
data = json.loads(raw.decode('utf-8-sig'))
shutil.copyfile(receipt, evidence / f'{prefix}-verifier.json')

def copy_logs(value):
    if isinstance(value, dict):
        for child in value.values():
            copy_logs(child)
    elif isinstance(value, list):
        for child in value:
            copy_logs(child)
    elif isinstance(value, str) and value.endswith('.log'):
        source = Path(value)
        if source.is_file():
            shutil.copyfile(source, evidence / f'{prefix}-{source.name}')

copy_logs(data)
print(json.dumps({'receipt': str(receipt), 'prefix': prefix,
                  'results': data.get('results', data.get('commands'))}))
