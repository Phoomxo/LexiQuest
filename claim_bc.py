import json, os, pathlib, zipfile
from datetime import datetime, timezone
r=pathlib.Path(__file__).parent
d=r/'docs/development/ux-delivery'
s=json.loads((d/'state.json').read_text(encoding='utf-8-sig'))
assert s['revision']==113 and s['writer']['status']=='RELEASED'
t=os.environ['CODEX_THREAD_ID']; now=datetime.now(timezone.utc).isoformat()
b=r/'build/ux-delivery/S01-BC'; b.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(b/'bootstrap-pre-edit.zip','x',zipfile.ZIP_DEFLATED) as z:
 z.write(d/'state.json','docs/development/ux-delivery/state.json')
w={'status':'ACTIVE','holderThreadId':t,'worktree':str(r),'branch':'feature/ux-s01-bc-logout-01a0de13','claimedAtUtc':now,'currentItem':'S01-BC-logout-recovery','dispatchId':'ux-s01-bc-20260926-0684','sourceReceipt':'docs/development/ux-delivery/handoffs/S01-BC-source-receipt.json','predecessorReleased':True,'routing':'Astra/medium deterministic fallback; not Jev-selected; Standard/default requested; runtime tier unexposed'}
s.update(revision=114,stateRole='LIVE',status='ACTIVE',writer=w,currentItem=w['currentItem'],nextAction='Inspect logout authorities and write meaningful offline RED tests; implement and verify BC sequentially in this worktree',checkpoint={'atUtc':now,'kind':'BC_IMPORTED_WRITER_ACTIVE','writerRetained':True,'sprintAccepted':False,'currentItem':w['currentItem']})
s['dispatch']={'id':w['dispatchId'],'status':'CLAIMED','successorThreadId':t}
s['nextDispatch']={'status':'NONE','successorThreadId':None}
s['nextReadyPackage']=None
s['continuation'].update(writerRetained=True,currentThreadId=t,currentItem=w['currentItem'],nextReadyPackage=None)
s['evidence'].update(sourceReceipt=w['sourceReceipt'],transferVerificationRecord=s['sourceManifest'])
for item in s['items']:
 if item['id']==w['currentItem']: item.update(status='IN_PROGRESS',acceptance='NOT_TESTED')
def save(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
save(d/'handoffs/S01-BC-writer-claim.json',w)
save(d/'state.json',s)
print(json.dumps({'revision':s['revision'],'writer':w}))
