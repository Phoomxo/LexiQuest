"""Offline, pinned source join. Does not translate, infer levels, or call APIs."""
import argparse
import collections
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

PINS = {'cefrj': 'b0dd3c635f1c9a4fdf1490c7e5b7c48e8bbe55b652ad0c9860a95f98e10ae498',
        'lexitron': '604fa2d1cccacfca01f919764ed5a99c78730afe55ddcd1863b42a8d56194840'}
POS = {'noun': {'N'}, 'verb': {'VT', 'VI', 'V'}, 'adjective': {'ADJ'},
       'adverb': {'ADV'}, 'pronoun': {'PRON'}, 'preposition': {'PREP'},
       'determiner': {'DET', 'ART'}, 'conjunction': {'CONJ'}, 'number': {'N', 'ADJ'},
       'interjection': {'INT'}, 'modal auxiliary': {'AUX'},
       'be-verb': {'AUX', 'VI'}, 'do-verb': {'AUX', 'VT', 'VI'},
       'have-verb': {'AUX', 'VT'}}
LEVELS = ['A1', 'A2', 'B1', 'B2']


def clean_meaning(value):
    if not isinstance(value, str) or '\ufffd' in value or re.search(r'[\x00-\x1f\x7f]', value):
        return None
    value = ' '.join(value.split())
    return value if 1 <= len(value) <= 500 and re.search('[ก-๙]', value) else None


def join_entries(cefr, lex, levels=LEVELS, prefix='cefrj15:'):
    index = collections.defaultdict(list)
    for row in lex:
        meaning = clean_meaning(row['t-entry'])
        if meaning:
            index[(row['e-entry'].strip(), row['e-cat'].strip())].append((row['id'], meaning))
    selected = {}
    for row_number, row in enumerate(cefr, 2):
        pos, level = row['pos'], row['CEFR']
        if pos not in POS or level not in levels:
            continue
        # A slash-separated spelling is one source headword, not extra cards.
        variants = row['headword'].split('/')
        for variant in variants:
            word = variant.strip().lower()
            if not re.fullmatch(r"[a-z]+(?:[-'][a-z]+)*", word):
                continue
            matches = sorted((entry for tag in POS[pos] for entry in index[(variant.strip(), tag)]), key=lambda x: int(x[0]))
            if not matches:
                continue
            meanings = list(dict.fromkeys(meaning for _, meaning in matches))
            candidate = {'id': prefix + word, 'word': variant.strip(), 'partOfSpeech': pos,
                         'cefrLevel': level, 'meanings': meanings,
                         'cefrjRow': row_number, 'cefrjHeadword': row['headword'],
                         'lexitronIds': [entry[0] for entry in matches]}
            old = selected.get(word)
            if old is None or levels.index(level) < levels.index(old['cefrLevel']):
                selected[word] = candidate
            break
    return sorted(selected.values(), key=lambda item: (levels.index(item['cefrLevel']), item['word'].lower()))


def spread(items, count):
    if count == 0:
        return []
    return [items[min(len(items) - 1, int((i + 0.5) * len(items) / count))] for i in range(count)]


def select_entries(entries, count):
    if len(entries) < count or count < 1:
        raise ValueError('Insufficient source-backed unique vocabulary')
    groups = {level: sorted((x for x in entries if x['cefrLevel'] == level), key=lambda x: x['word'].lower()) for level in LEVELS}
    result = []
    for level in ['A1', 'A2']:
        result += spread(groups[level], min(len(groups[level]), count - len(result)))
    remaining = count - len(result)
    b1_count = min(len(groups['B1']), (remaining + 1) // 2)
    b2_count = min(len(groups['B2']), remaining - b1_count)
    b1_count = min(len(groups['B1']), remaining - b2_count)
    result += spread(groups['B1'], b1_count) + spread(groups['B2'], b2_count)
    if len(result) != count or len({x['word'] for x in result}) != count:
        raise ValueError('Invalid selection')
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    cefr_bytes = (args.sources / 'cefrj.csv').read_bytes()
    lex_bytes = (args.sources / 'lexitron.zip').read_bytes()
    assert hashlib.sha256(cefr_bytes).hexdigest() == PINS['cefrj']
    assert hashlib.sha256(lex_bytes).hexdigest() == PINS['lexitron']
    archive = zipfile.ZipFile(io.BytesIO(lex_bytes))
    cefr = list(csv.DictReader(io.StringIO(cefr_bytes.decode('utf-8-sig'))))
    lex = list(csv.DictReader(io.StringIO(archive.read('LEXiTRON_2.0_csv/etlex.csv').decode('utf-8-sig'))))
    eligible = join_entries(cefr, lex)
    entries = select_entries(eligible, 3000)
    payload = {'schemaVersion': 1, 'edition': 'cefr-starter-3000-r1',
               'sourcePins': PINS, 'count': len(entries),
               'qualityStatus': 'source-joined-not-independently-reviewed',
               'selection': 'all eligible A1/A2, remaining split B1/B2 and evenly sampled alphabetically; not frequency ranked',
               'entries': entries}
    args.output.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(payload, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    (args.output / 'catalog.json').write_bytes(data)
    for name, encoding in [('LICENSE.txt', 'ascii'), ('LICENSE-th.txt', 'cp874')]:
        text = archive.read('LEXiTRON_2.0_csv/' + name).decode(encoding).replace('\r\r\n', '\n').replace('\r\n', '\n')
        (args.output / name).write_text(text, encoding='utf-8')
    print(json.dumps({'count': len(entries), 'eligible': len(eligible), 'levels': dict(collections.Counter(x['cefrLevel'] for x in entries)), 'sha256': hashlib.sha256(data).hexdigest()}, indent=2))


if __name__ == '__main__':
    main()
