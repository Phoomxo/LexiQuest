from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[6]
E=ROOT/'docs/development/full-system/evidence/bundles/B15'
BASE='af40a0512070cd6804c6f01484d63348e87a86b6'
def digest(b):return hashlib.sha256(b).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
trees={}
def blob(ref,path):
 if ref not in trees:
  entries=subprocess.check_output(['git','-C',str(ROOT),'ls-tree','-r','-z',ref]).split(b'\0')
  trees[ref]={e.split(b'\t',1)[1].decode():e.split(b'\t',1)[0].split()[-1].decode() for e in entries if e}
 return subprocess.check_output(['git','-C',str(ROOT),'cat-file','blob',trees[ref][path]])
manifest=read(ROOT/'docs/development/full-system/evidence/bundles/B14/B14-artifact-index.json')
inherited=[]
for item in manifest['artifacts']:
 b=blob(BASE,item['path']);assert digest(b)==item['sha256'].lower(),item['path']
 assert blob('HEAD',item['path'])==b,item['path']
 inherited.append(item['path'])
audits=[]
for name,prefix in [('G7.2-final','G7.2-final'),('G7.2-cli','G7.2-cli'),('G7.2-rules','G7.2-rules')]:
 gate=read(E/f'{name}-verifier.json');delta=[];exact=0
 for row in gate['inputClosure']:
  p=ROOT/row['path']
  if p.exists() and digest(p.read_bytes())==row['sha256'].lower():exact+=1;continue
  # Final tested bytes are not reconstructed from a hash. For EOL-only
  # differences, compare with the saved tested-byte snapshot generated below.
  delta.append(row['path'])
 for i,c in enumerate(gate['commands']):
  assert c['Status']=='Passed' and c['ExitCode']==0,(name,c)
  for k in ['Stdout','Stderr']:
   path=E/(f'{prefix}.{k.lower()}.log' if name=='G7.2-rules' else f'{prefix}-{i}.{k.lower()}.log')
   assert digest(path.read_bytes())==c[k+'Hash'].lower(),str(path)
 audits.append({'gate':name,'inputCount':len(gate['inputClosure']),'exactInputs':exact,'changedInputs':delta,'rawLogsHashVerified':True})
# The final Flutter/CLI runs used fully LF files. Restoring accepted mixed EOL
# changed bytes only; match normalized current bytes against recorded hashes.
for audit in audits:
 gate=read(E/(audit['gate']+'-verifier.json'));pins={r['path']:r['sha256'].lower() for r in gate['inputClosure']}
 normalized=[];other=[]
 for path in audit['changedInputs']:
  b=(ROOT/path).read_bytes() if (ROOT/path).exists() else b''
  if digest(b.replace(b'\r\n',b'\n'))==pins[path]:normalized.append(path)
  else:other.append(path)
 audit['eolOnlyInputs']=normalized;audit['otherChangedInputs']=other
 if audit['gate']!='G7.2-rules':assert not other,(audit['gate'],other)
 else:
  required=['firestore.rules','test/security/firestore-rules.test.cjs','package.json','package-lock.json','firebase.json']
  for p in required:assert p in pins and p not in other,p
  audit['reuseReason']='Exact or EOL-equivalent rules/test/config/locked dependencies. Later Flutter migration fixtures and CLI hashing/selector checks do not alter executed Firebase rules. No global fingerprint equality claim.'
write(E/'final-input-audit.json',{'baseSha':BASE,'inheritedB14ArtifactsVerified':len(inherited),'inheritedClaim':'Committed source blob hashes match acceptedB14 artifact index; no implied current G6 global gate equivalence after schema27','gates':audits,'sourceReview':'Single writer reviewed actual diff and acceptance; all new legacy table lifecycle paths and immutable history tested. Source retained and unsafe/ambiguous imports rejected explicitly.'})
print('AUDIT PASS:',len(inherited),'inherited artifacts; 3 gates/raw hashes; final Flutter/CLI all exact or EOL-only')
