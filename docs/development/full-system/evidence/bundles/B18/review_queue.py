"""Assign the whole frozen inventory to serial review zones; never infer PASS."""
import collections
import json
from pathlib import Path

OUT=Path(__file__).resolve().parent
inventory=json.loads((OUT/'G8.1-inventory.json').read_text(encoding='utf-8'))

def zone(path):
    lower=path.lower()
    if path.startswith(('test/','integration_test/','test_driver/')) or '/tests/' in path:
        return 'REV-12'
    if path.startswith(('android/','ios/','linux/','macos/','windows/','web/')):
        return 'REV-10'
    if path.startswith(('tool/','tools/','docs/','.github/')) or '/' not in path:
        return 'REV-09' if path.endswith('.rules') else 'REV-11'
    if path.startswith('backend/'):
        return 'REV-08' if any(s in lower for s in ('ai_api','voice_api','lexiquest_lm')) else 'REV-09'
    if path.startswith(('functions/','supabase/','hosting/')): return 'REV-09'
    if any(s in lower for s in ('/sync/','/account/','/export/','/research/','/consent/')): return 'REV-09'
    if any(s in lower for s in ('/device_model/','/camera/','object_scanner','object_vocabulary','image_preprocess','model_benchmark','dataset_partition')): return 'REV-07'
    if any(s in lower for s in ('/voice/','/ai/','/ai_tutor/','speech','pronunciation','audio','voice_','ai_reading')): return 'REV-08'
    if any(s in lower for s in ('/runtime/','/navigation/','/identity/','/session/','/auth/','login','signup','sign_up','auth_service')) or path=='lib/main.dart': return 'REV-01'
    if any(s in lower for s in ('/goals/','/reminders/','/quest/','/motivation/','/achievements/','/rewards/','/companion/','/preferences/','streak','daily_quest','avatar','background','shop','reward','settings')): return 'REV-06'
    if any(s in lower for s in ('/progress/','/recommendation/','/assessment/','/time_tracking/','/today_hub/','/srs/','srs_','mastery','weakness','calendar','study_time','heatmap','learning_summary','adaptive_decay','response_time')): return 'REV-05'
    if any(s in lower for s in ('/vocabulary/','/learning_packs/','/offline_content/','/review/','lexical','cefr','word','sentence_service','phrasal','collocation','dictionary','glossary','category','vocab','content','bookmark')): return 'REV-04'
    if '/learning/presentation/' in path or '/learning/application/' in path and any(s in path for s in ('mode_adapter','lesson_mode_registry','unified_lesson_controller','session_configuration_policy','hint_use_cases','contrastive_feedback')): return 'REV-03'
    if any(s in lower for s in ('/data/local/','/history/','/learning/domain/','/learning/data/','/learning/application/','/learning/')) and '/pair_matching/' not in path: return 'REV-02'
    return 'REV-03'

rows=[]
for source in inventory['files']:
    row=dict(source)
    row['zone']='REV-12' if row['category']=='generated' else zone(row['path']) if row['category'] in {'handwritten-source','configuration'} else None
    row['status']='pending-review' if row['zone'] else 'excluded-nonexecutable'
    row['reviewerPassDate']=None
    row['findingIDs']=[]
    row['reviewNotes']=None
    rows.append(row)
target=OUT/'G8.2-review-ledger.json'
assert not target.exists(), 'Do not overwrite recorded review progress'
target.write_text(json.dumps(dict(sourceSha=inventory['sourceSha'],
    scope='Every handwritten executable and configuration; generated via generator/reproducibility',
    files=rows),indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps(collections.Counter(r['zone'] for r in rows if r['zone'])))
