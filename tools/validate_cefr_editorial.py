"""Structural/provenance audit; not a substitute for editorial language review."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re

FIELDS = {'id','senseKey','sourceMeaningIndex','meaning','example','translation','reviewNote','status'}

def validate(original, entries):
    source = {x['id']: x for x in original}
    expected = {x['id'] for x in original}
    seen = set()
    warnings = []
    for item in entries:
        if not FIELDS <= set(item) or set(item) - FIELDS - {'partOfSpeechOverride'} or item['id'] not in expected or item['id'] in seen:
            raise ValueError('Unknown, duplicate or malformed editorial entry')
        seen.add(item['id'])
        word = source[item['id']]
        if item['status'] != 'ai-reviewed' or item['senseKey'] != 'primary-v1':
            raise ValueError('Invalid review/identity state')
        index = item['sourceMeaningIndex']
        override=item.get('partOfSpeechOverride')
        if override is not None and (index is not None or override not in {
            'noun','verb','adjective','adverb','pronoun','preposition','determiner',
            'conjunction','number','interjection','modal auxiliary','be-verb','do-verb','have-verb'}):
            raise ValueError('Invalid POS override: '+item['id'])
        if index is not None and (type(index) is not int or not 0 <= index < len(word['meanings'])):
            raise ValueError('Invalid source sense mapping: ' + item['id'])
        for field, limit in [('meaning',500),('example',400),('translation',500),('reviewNote',500)]:
            value=item[field]
            if not isinstance(value,str) or not 0 < len(value) <= limit or value != value.strip() or re.search(r'[\x00-\x1f\x7f\ufffd]',value):
                raise ValueError(f'Invalid text {item["id"]}/{field}')
        if not re.search(r'(?<![A-Za-z])'+re.escape(word['word'])+r'(?![A-Za-z])',item['example'],re.I):
            raise ValueError('Missing target form: '+item['id'])
        if not all(re.search('[ก-๙]',item[k]) for k in ['meaning','translation']):
            raise ValueError('Missing Thai text: '+item['id'])
        if len(item['example'].split()) > (18 if word['cefrLevel']=='A1' else 22):
            warnings.append({'id':item['id'],'kind':'review-sentence-length'})
        if not re.search(r'[.!?]["\u201d\u2019\x27]?$',item['example']):
            warnings.append({'id':item['id'],'kind':'review-terminal-punctuation'})
        prefix = 'cefr-starter-3000-r1/'+word['word']+'/' + str(index) if index is not None else 'cefr-editorial-r1/'+word['word']+'/'+item['senseKey']
        if len(prefix)>60:
            raise ValueError('Import source too long')
    if seen != expected:
        raise ValueError(f'Missing editorial coverage: {len(expected-seen)}')
    repeated=collections.Counter(x['example'].casefold() for x in entries)
    return {'coverage':len(seen),'levels':dict(collections.Counter(source[x]['cefrLevel'] for x in seen)),
        'sourceLinked':sum(x['sourceMeaningIndex'] is not None for x in entries),
        'independentSenses':sum(x['sourceMeaningIndex'] is None for x in entries),
        'posOverrides':[x['id'] for x in entries if x.get('partOfSpeechOverride') is not None],
        'duplicateExampleTexts':[x for x,n in repeated.items() if n>1], 'warnings':warnings,
        'languageQualityCertifiedByThisCheck':False}

def validate_senses(original, entries):
    source={x['id']:x for x in original};seen=set();accepted=excluded=0
    keys={'id','acceptedSourceMeaningIndices','excludedSourceMeanings','status','reviewNote'}
    for row in entries:
        if set(row)!=keys or row['id'] not in source or row['id'] in seen or row['status']!='ai-reviewed':
            raise ValueError('Invalid sense review identity/schema')
        seen.add(row['id'])
        allow=row['acceptedSourceMeaningIndices'];deny=row['excludedSourceMeanings']
        if not isinstance(allow,list) or not isinstance(deny,list):raise ValueError('Invalid sense lists')
        indices=list(allow)
        for item in deny:
            if set(item)!={'index','reason'}:raise ValueError('Invalid exclusion fields')
            indices.append(item['index'])
            reason=item['reason']
            if not isinstance(reason,str) or not reason.strip() or reason!=reason.strip() or len(reason)>500 or re.search(r'[\x00-\x1f\x7f\ufffd]',reason):raise ValueError('Invalid exclusion rationale')
        if any(type(i) is not int for i in indices) or sorted(indices)!=list(range(len(source[row['id']]['meanings']))):
            raise ValueError('Sense review must partition every original index: '+row['id'])
        if not isinstance(row['reviewNote'],str) or not row['reviewNote'].strip() or row['reviewNote']!=row['reviewNote'].strip() or len(row['reviewNote'])>500 or re.search(r'[\x00-\x1f\x7f\ufffd]',row['reviewNote']):
            raise ValueError('Missing review note')
        accepted+=len(allow);excluded+=len(deny)
    if seen!=set(source):raise ValueError('Incomplete sense review coverage')
    return {'coverage':len(seen),'sourceMeaningCount':accepted+excluded,'accepted':accepted,'excluded':excluded,
            'languageQualityCertifiedByThisCheck':False}

def load_original(root):
    pins={
      'cefr_starter/catalog.json':'b1af6f5c444650d39d6873bf7db7632585b2220b69bce323327693c021641140',
      'cefr_expanded/core-extension.json':'da83baf5ecfb8b64a486da6e784c7ca3d5ae373e18e7fccc02d09179cf7bf6bf',
      'cefr_expanded/advanced-profile.json':'694a96a5cd413aa41c8547691d54eabed8f8746ca08dcf970e3dd288fc7ebe05',
      'cefr_expanded/advanced-translations.json':'3e25d52af96d5524ca786c07cc840772ee6862cb381e7b2cda96c16a1d116130',
    }
    assets={}
    for p,pin in pins.items():
        raw=(root/'assets/content'/p).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=pin:raise ValueError('Original asset changed: '+p)
        assets[p]=json.loads(raw)['entries']
    words=assets['cefr_starter/catalog.json']+assets['cefr_expanded/core-extension.json']
    thai={x['id']:x for x in assets['cefr_expanded/advanced-translations.json']}
    words += [dict(x,meanings=thai[x['id']]['meanings']) for x in assets['cefr_expanded/advanced-profile.json']]
    return words

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',type=Path,default=Path.cwd())
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--write-manifest',action='store_true')
    parser.add_argument('--complete',action='store_true')
    args=parser.parse_args()
    original=load_original(args.root)
    if not args.complete:original=[x for x in original if x['cefrLevel'] in ['A1','A2']]
    entries=[];pins={}
    names=[f'batch-{n}' for n in range(1,4)]
    if args.complete:names += [f'complete-{n}' for n in range(1,4)]
    for name in names:
        relative=f'assets/content/cefr_editorial/{name}.json'
        raw=(args.root/relative).read_bytes()
        payload=json.loads(raw)
        if payload.get('schemaVersion')!=1:raise ValueError('Invalid batch schema')
        entries.extend(payload['entries'])
        pins[relative]=hashlib.sha256(raw).hexdigest()
    report=validate(original,entries)
    report['pins']=pins
    sense_pins={}
    if args.complete:
        reviews=[]
        for n in range(1,4):
            p=f'assets/content/cefr_editorial/sense-review-{n}.json'
            raw=(args.root/p).read_bytes();payload=json.loads(raw)
            if payload.get('schemaVersion')!=1:raise ValueError('Invalid sense schema')
            reviews+=payload['entries'];sense_pins[p]=hashlib.sha256(raw).hexdigest()
        report['senseReview']=validate_senses(original,reviews)
    report['sensePins']=sense_pins
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.write_manifest:
        dart='// Generated by tools/validate_cefr_editorial.py; do not edit.\nconst cefrEditorialChecksums = <String, String>{\n'
        dart+=''.join(f"  '{p}':\n      '{digest}',\n" for p,digest in pins.items())
        dart+=f'}};\nconst cefrEditorialExpectedCount = {len(original)};\n'
        dart+='const cefrSenseReviewChecksums = <String, String>{\n'
        dart+=''.join(f"  '{p}':\n      '{digest}',\n" for p,digest in sense_pins.items())
        dart+='};\n'
        (args.root/'lib/features/vocabulary/data/cefr_editorial_manifest.dart').write_text(dart,encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ['pins','duplicateExampleTexts','warnings']}))

if __name__=='__main__':main()
