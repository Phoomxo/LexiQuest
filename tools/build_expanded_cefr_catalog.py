"""Reproducible expansion; independent level and translation licensed assets."""
import argparse
import collections
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile
from build_cefr_catalog import PINS, join_entries, spread

ADVANCED_PIN = '18c33a407f2f89f7b8de9671c6d45fe3ea0bce45e7d2d7dcaab48d73e0f7b380'
LEGACY_PIN = 'b1af6f5c444650d39d6873bf7db7632585b2220b69bce323327693c021641140'

def expand(original, candidates, additions, supplement_count):
    seen = {x['word'].lower() for x in original}
    main = list(original)
    supplement = []
    for level, count in list(additions.items()) + [('C2', supplement_count)]:
        unique = {}
        for item in candidates:
            key = item['word'].lower()
            if item['cefrLevel'] == level and key not in seen:
                unique.setdefault(key, item)
        pool = [unique[k] for k in sorted(unique)]
        if len(pool) < count:
            raise ValueError(f'Insufficient unique source-backed {level} words')
        chosen = spread(pool, count)
        seen.update(x['word'].lower() for x in chosen)
        (supplement if level == 'C2' else main).extend(chosen)
    return main, supplement

def pinned(path, digest):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f'Source pin mismatch: {path.name}')
    return data

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--advanced', type=Path, required=True)
    parser.add_argument('--legacy', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    original = json.loads(pinned(args.legacy, LEGACY_PIN))['entries']
    cefr = list(csv.DictReader(io.StringIO(pinned(args.sources/'cefrj.csv', PINS['cefrj']).decode('utf-8-sig'))))
    advanced_bytes = pinned(args.advanced, ADVANCED_PIN)
    advanced = list(csv.DictReader(io.StringIO(advanced_bytes.decode('utf-8-sig'))))
    with zipfile.ZipFile(io.BytesIO(pinned(args.sources/'lexitron.zip', PINS['lexitron']))) as archive:
        lex = list(csv.DictReader(io.StringIO(archive.read('LEXiTRON_2.0_csv/etlex.csv').decode('utf-8-sig'))))
    core = join_entries(cefr, lex)
    lower_words = {x['word'].lower() for x in core}
    extra = [x for x in join_entries(advanced, lex, ['C1', 'C2'], 'octanove10:')
             if x['word'].lower() not in lower_words]
    selected, supplement = expand(original, core + extra, {'B1': 750, 'B2': 750, 'C1': 500}, 500)
    extension = selected[len(original):]
    core_extension = [x for x in extension if x['cefrLevel'] in ['B1','B2']]
    advanced_selected = [x for x in extension if x['cefrLevel'] == 'C1'] + supplement
    # The adapted Octanove index carries only its word/POS/level/source-row data.
    # NECTEC translations remain an independent dictionary lookup, not relicensed.
    profile = [{'id': x['id'], 'word': x['word'], 'partOfSpeech': x['partOfSpeech'],
                'cefrLevel': x['cefrLevel'], 'sourceRow': x['cefrjRow']} for x in advanced_selected]
    translations = [{'id': x['id'], 'word': x['word'], 'partOfSpeech': x['partOfSpeech'],
                     'meanings': x['meanings'], 'lexitronIds': x['lexitronIds']} for x in advanced_selected]
    args.output.mkdir(parents=True, exist_ok=True)
    assets = {
        'core-extension.json': {'schemaVersion':1, 'sourcePins':PINS, 'entries':core_extension},
        'advanced-profile.json': {'schemaVersion':1, 'sourceSha256':ADVANCED_PIN,
            'license':'CC-BY-SA-4.0', 'attribution':'Octanove Labs, Vocabulary Profile C1/C2 1.0, via Open Language Profiles',
            'changes':'Selected 500 C1 and 500 C2 headwords; normalized representation and assigned stable IDs. Adapted level index by LexiQuest contributors under CC BY-SA 4.0.',
            'entries':profile},
        'advanced-translations.json': {'schemaVersion':1, 'sourceSha256':PINS['lexitron'],
            'license':'LEXiTRON 2.0 license, NECTEC; see cefr_starter/LICENSE.txt and LICENSE-th.txt', 'entries':translations},
    }
    hashes = {}
    for name, value in assets.items():
        data = (json.dumps(value, ensure_ascii=False, indent=2)+'\n').encode('utf-8')
        (args.output/name).write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    (args.output/'octanove-source.csv').write_bytes(advanced_bytes)
    print(json.dumps({'mainCount':len(selected), 'supplementCount':len(supplement),
        'levels':dict(collections.Counter(x['cefrLevel'] for x in selected+supplement)),
        'eligibleAdvanced':dict(collections.Counter(x['cefrLevel'] for x in extra)), 'hashes':hashes}, indent=2))

if __name__ == '__main__': main()
