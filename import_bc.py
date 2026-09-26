import hashlib, json, os, pathlib, re, shutil, subprocess, zipfile
from datetime import datetime, timezone
root = pathlib.Path(__file__).parent.resolve()
source = pathlib.Path(r'C:\Users\Phet\.codex\worktrees\0684\LexiQuest')
mp = pathlib.Path('docs/development/ux-delivery/handoffs/S01-BC-source-manifest.json')
def digest(p):
    with p.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()
assert digest(source/mp) == '6c8940bb472ea4fc3529490300fe5d323a7fbe5f674860b384d40f1a2cfe6699'
m = json.loads((source/mp).read_text(encoding='utf-8-sig'))
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()==m['baseSha']
assert root != source and root.name == 'LexiQuest' and root.parent.name == 's01-bc-logout'
assert hashlib.sha256(json.dumps(m['files'],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()==m['overlayFingerprintSha256']
def target(name):
    assert isinstance(name,str) and '\\' not in name and ':' not in name
    parts=name.split('/')
    for s in parts:
        assert s and s not in ('.','..') and not s.endswith((' ','.'))
        assert not any(ord(c)<32 or c in '<>"|?*' for c in s)
        assert not re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])',s.split('.')[0],re.I)
    p=root.joinpath(*parts).resolve()
    assert p.is_relative_to(root) and p != root
    return p
entries={}
fold=set()
for f in m['files']:
    target(f['path'])
    assert f['path'].casefold() not in fold
    fold.add(f['path'].casefold()); entries[f['path']]=f
archive=source/m['archivePath']
assert archive.stat().st_size==m['archiveBytes'] and digest(archive)==m['archiveSha256']
with zipfile.ZipFile(archive) as z:
    infos=z.infolist()
    assert len(infos)==3002 and len({i.filename.casefold() for i in infos})==len(infos)
    assert {i.filename for i in infos}=={p for p,f in entries.items() if f['exists']}
    for i in infos:
        target(i.filename)
        assert not i.is_dir() and (i.external_attr>>16)&0o170000 != 0o120000
        f=entries[i.filename]
        assert i.file_size==f['bytes']
        with z.open(i) as stream: assert hashlib.file_digest(stream,'sha256').hexdigest()==f['sha256']
    print('All archive paths, membership, CRC, sizes and hashes verified',flush=True)
    for i in infos:
        p=target(i.filename); p.parent.mkdir(parents=True,exist_ok=True)
        with z.open(i) as src,p.open('wb') as dst: shutil.copyfileobj(src,dst)
for name,f in entries.items():
    p=target(name)
    if not f['exists']:
        if p.exists():
            assert p.is_file(); p.unlink()
        assert not p.exists()
    else: assert p.stat().st_size==f['bytes'] and digest(p)==f['sha256']
shutil.copyfile(source/mp,root/mp)
receipt={'schemaVersion':1,'dispatchId':m['dispatchId'],'threadId':os.environ['CODEX_THREAD_ID'],'worktree':str(root),'branch':subprocess.check_output(['git','branch','--show-current'],cwd=root,text=True).strip(),'baseSha':m['baseSha'],'importedAtUtc':datetime.now(timezone.utc).isoformat(),'sourceRoot':str(source),'manifestSha256':digest(root/mp),'archiveSha256':m['archiveSha256'],'fingerprint':m['overlayFingerprintSha256'],'files':len(infos),'deletions':sum(not f['exists'] for f in entries.values()),'verified':'raw segments/reserved names/containment/casefold/membership/CRC/size/SHA256 and final bytes','archives':sum(f['exists'] and p.endswith('.zip') for p,f in entries.items())}
p=root/'docs/development/ux-delivery/handoffs/S01-BC-source-receipt.json'
p.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt),flush=True)
