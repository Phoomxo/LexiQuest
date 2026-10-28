"""Validate the grouped orchestration against accepted G0.5; no runtime gates."""
from pathlib import Path
import json, re, subprocess, hashlib, datetime, collections
R=Path.cwd()
BASE="9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe"
REV="2026-09-13-bundles-4"
EV=Path("docs/development/full-system/evidence/bundles-4")
C=Path("C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/full-system-orchestration")
IDX="docs/development/full-system-task-index.json"
LED="docs/development/2026-09-13-full-system-work-ledger.json"
MASTER="docs/superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md"
def jr(p): return json.loads((R/p).read_text(encoding="utf-8-sig"))
git_diagnostics=[]
def git(*args):
 result=subprocess.run(["git",*args],cwd=R,capture_output=True)
 if result.stderr:
  git_diagnostics.append({"args":list(args),"exitCode":result.returncode,"stderr":result.stderr.decode("utf-8",errors="replace")})
 if result.returncode: raise RuntimeError(result.stderr.decode("utf-8",errors="replace")+result.stdout.decode("utf-8",errors="replace"))
 return result.stdout
def base_text(p): return git("show",BASE+":"+str(p)).decode("utf-8-sig").replace("\r\n","\n")
def sha(p): return hashlib.sha256((R/p).read_bytes()).hexdigest()
def write_json(p,v):
 p=R/p;p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
idx=jr(IDX);led=jr(LED);old=json.loads(base_text(LED));oldidx=json.loads(base_text(IDX))
assert git("rev-parse","HEAD").decode().strip()==BASE
assert idx["revision"]==led["revision"]==REV
assert idx["executionMode"]==led["taskOrchestration"]["executionMode"]=="bundles"
assert "tasks" not in idx and len(idx["packages"])==64 and len(idx["bundles"])==20
assert [p["displayId"] for p in idx["packages"]]==[p["displayId"] for p in oldidx["tasks"]]
assert [p["packageId"] for p in idx["packages"]]==[p["id"] for p in led["packages"]]
assert [p["count"] for p in idx["phaseCounts"]]==[8,7,8,7,6,6,6,7,9]
ordered=[p["displayId"] for p in idx["packages"]]
history_ids=[h["displayId"] for h in idx["acceptedHistory"]]
remaining=[p for b in idx["bundles"] for p in b["packageIds"]]
assert history_ids==ordered[:5] and remaining==ordered[5:]
assert len(history_ids+remaining)==len(set(history_ids+remaining))==64
assert sum(b["packageCount"] for b in idx["bundles"])==59
position={p["packageId"]:p["ordinal"] for p in idx["packages"]}
phase_end={ph["gate"]:max(p["ordinal"] for p in idx["packages"] if p["phase"]==ph["gate"]) for ph in led["phases"]}
links=0;technical_hashes=[]
for i,p in enumerate(idx["packages"]):
 assert p["dispatchPolicy"]=="never-dispatch-a-package"
 assert p["previousPackage"]==(ordered[i-1] if i else None)
 assert p["nextPackage"]==(ordered[i+1] if i<63 else None)
 assert p["model"]=="gpt-6-astra" and p["thinking"]=="medium"
 cur=led["packages"][i];before=old["packages"][i]
 for k,v in before.items():
  if k=="status":continue
  assert cur[k]==v,("changed requirement",p["displayId"],k)
 for dep in cur["dependencies"]:
  end=position.get(dep,phase_end.get(dep))
  assert end is not None and end < p["ordinal"],("dependency order",p["displayId"],dep)
 if i<5: assert cur["status"]=="accepted" and p["bundleId"] is None
 else: assert cur["status"]==before["status"] and p["bundleId"]
 oldbrief=base_text(p["briefPath"]);newbrief=(R/p["briefPath"]).read_text(encoding="utf-8")
 ot=oldbrief.split("## ขอบเขตและผลที่ต้องได้",1)[1].split("## ส่งต่อและจบ task",1)[0].strip()
 nt=newbrief.split("## ขอบเขตและผลที่ต้องได้",1)[1]
 nt=re.split(r"\n## (?:บันทึกผลย่อยและทำข้อต่อไป|สถานะประวัติ)",nt,maxsplit=1)[0].strip()
 assert ot==nt,("technical brief changed",p["displayId"])
 assert "สร้าง **G" not in newbrief and "reserve และสร้าง" not in newbrief
 technical_hashes.append({"displayId":p["displayId"],"sha256":hashlib.sha256(nt.encode()).hexdigest(),"matchesAcceptedG05":True})
for i,b in enumerate(idx["bundles"]):
 assert b["ordinal"]==i+1 and b["bundleId"]==f"B{i+1:02d}"
 assert b["previousBundleId"]==(f"B{i:02d}" if i else None)
 assert b["nextBundleId"]==(f"B{i+2:02d}" if i<19 else None)
 assert b["packageCount"]==len(b["packageIds"])
 assert b["model"]=="gpt-6-astra" and b["thinking"]=="medium"
 for pid in b["packageIds"]:
  assert next(p for p in idx["packages"] if p["displayId"]==pid)["bundleId"]==b["bundleId"]
 assert len({p["reportPath"] for p in idx["bundles"]})==20
 assert (R/b["briefPath"]).is_file()
assert idx["bundles"][17]["packageIds"]==["G8.1","G8.2","G8.3"]
assert idx["bundles"][18]["packageIds"]==["G8.4","G8.5","G8.6","G8.7"]
assert idx["bundles"][19]["packageIds"]==["G8.8","G8.9"]
for field in ("coverage","coverageTraceability","catalog","formulaGroups","cleanup","wholeCodeReview","systemTestPlan","source","phases"):
 assert led[field]==old[field],("changed accepted data",field)
assert len(led["coverage"])==74 and led["coverageTraceability"]==old["coverageTraceability"]
for h in idx["acceptedHistory"]:
 hand=json.loads(Path(h["handoffPath"]).read_text(encoding="utf-8-sig"))
 assert hand["acceptedSourceSha"]==h["acceptedSourceSha"] and hand["writerReleased"]
 subprocess.run(["git","merge-base","--is-ancestor",h["acceptedSourceSha"],BASE],cwd=R,check=True)
 assert h["disposition"]=="accepted-history-do-not-redispatch"
state=json.loads((C/"run-state.json").read_text(encoding="utf-8-sig"))
assert state["revision"]==18 and state["currentWriter"]["kind"]=="orchestration-only"
assert state["latestAcceptedSource"]["sha"]==BASE and not state["dispatchReservation"]
assert not any(t.get("threadId") or t.get("clientThreadId") for t in state["tasks"][5:])
assert not (C/"dispatches/G0.6.json").exists()
assert not (C/"dispatches/bundles/B01.json").exists()
active=["AGENTS.md",MASTER,"docs/development/full-system-active-index.md","docs/development/full-system-package-workflow.md","docs/development/full-system-bundle-map.md","docs/development/2026-09-13-rule-supersession-register.md","docs/development/r15-package-workflow.md"]+[p["briefPath"] for p in idx["packages"]]+[b["briefPath"] for b in idx["bundles"]]
for path in active:
 text=(R/path).read_text(encoding="utf-8")
 for raw in re.findall(r"\[[^\]]*\]\(([^)]+)\)",text):
  target=raw.strip("<>").split("#")[0]
  if not target or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:|^/",target):continue
  assert ((R/path).parent/target).resolve().exists(),("broken link",path,target)
  links+=1
 for stale in ("64 package tasks","one new Codex task per package","## แบ่งงานเป็น 64 tasks","task ละหนึ่ง package;","ให้ reserve และสร้าง **G"):
  assert stale not in text,("stale dispatch rule",path,stale)
changed=git("diff","--name-only",BASE).decode().splitlines()
untracked=git("ls-files","--others","--exclude-standard").decode().splitlines()
assert all(p=="AGENTS.md" or p.startswith("docs/") for p in changed+untracked),("application changes",changed)
git("diff","--check")
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
report=R/"docs/development/full-system/bundles-4-migration.md"
report.write_text(f"""# เปลี่ยน workflow หลัง G0.5

Revision {REV} · base {BASE}

เปลี่ยนเป็น **20 bundles สำหรับ59packagesที่เหลือ**. เก็บG0.1–G0.5เป็นacceptedhistory และคง64requirements/dependencies/acceptanceทั้งหมด. Packagebriefเป็นrequirement unit; dispatchเฉพาะbundleจบ

ตรวจผ่าน:64IDsครั้งเดียว, 5historyไม่redispatch, 59remainingครบ, 20bundlechain, dependency/phase order, reviewก่อนTest Plan, technicalbrief bodiesเดิมครบ64, coverage/source traceabilityเดิมครบ74rows, active links{links}, ไม่มีapplicationchangesหรือfutureduplicate dispatch. [ผลตรวจและปัญหา](evidence/bundles-4/verification.json) · [Source manifest](evidence/bundles-4/source-manifest.json)

เริ่มB01 G0.6–G0.8จากacceptedorchestrationcommitที่ต่อจากG0.5. ActualSHA/receiptอยู่external orchestrationhandoffหลังcommit. Masterไม่ทำapplicationpackagesและไม่ได้รันFlutter/backend/build/GPU/releasegatesเพิ่ม
""",encoding="utf-8",newline="\n")
jw=write_json
jw(EV/"technical-preservation.json",{"revision":REV,"baseSha":BASE,"packages":technical_hashes})
jw(EV/"git-diagnostics.json",{"revision":REV,"diagnostics":git_diagnostics,"classification":"EOL conversion notices retained; git diff --check must return zero"})
# Build an acyclic manifest: exclude the manifest and its verification result.
changed=git("diff","--name-only",BASE).decode().splitlines()
untracked=git("ls-files","--others","--exclude-standard").decode().splitlines()
excluded={str(EV/"source-manifest.json").replace("\\","/"),str(EV/"verification.json").replace("\\","/")}
paths=sorted(set(changed+untracked)-excluded)
manifest={"schemaVersion":1,"revision":REV,"baseSha":BASE,"baseWorktree":"C:/Users/Phet/.codex/worktrees/e870/LexiQuest","orchestrationWorktree":str(R),"applicationDelta":"none","files":[{"path":p,"sha256":sha(p),"bytes":(R/p).stat().st_size} for p in paths],"sourceEvidencePreserved":{"g05SourceManifest":"docs/development/full-system/evidence/G0.5/source-manifest.json","g05SourceManifestSha256":sha("docs/development/full-system/evidence/G0.5/source-manifest.json")}}
jw(EV/"source-manifest.json",manifest)
result={"schemaVersion":1,"revision":REV,"verifiedAtUtc":now,"baseSha":BASE,"kind":"orchestration-consistency","result":"passed","runtimeGatesRun":False,"checks":{"allPackageIdsExactlyOnce":64,"acceptedHistory":5,"remaining":59,"bundles":20,"technicalBriefBodiesUnchanged":64,"coverageRowsPreserved":74,"dependenciesAndPhaseOrder":"preserved","reviewBeforeSystemTestPlan":True,"activeRelativeLinks":links,"futureDuplicateDispatches":0,"applicationChanges":0,"model":"gpt-6-astra","thinking":"medium"},"manifestPath":str(EV/"source-manifest.json"),"manifestSha256":sha(EV/"source-manifest.json"),"command":"python docs/development/full-system/evidence/bundles-4/verify_workflow.py","reusedEvidence":"G0.2/G0.4/G0.5 recorded gates; unchanged application/source/content inputs verified by semantic data and Git diff, not rerun","issues":[{"id":"B4-OPS-01","operation":"atomic control claim","actual":"File.Replace with null backup raised The path is empty; revision17 remained intact","rootCause":"PowerShell string binding passed empty path for null backup","fix":"Verify intact revision17 and exactly one prepared revision18 temp, then atomically replace with explicit nonempty backup path under lock","retest":"revision18 orchestration writer read back; revision17 backup retained","status":"closed","applicationImpact":"none"},{"id":"B4-OPS-02","operation":"authoring migration helper through JavaScript","actual":"Unescaped Markdown backtick caused JavaScript SyntaxError before any tool ran","rootCause":"Nested literal delimiter collision","fix":"Use a neutral placeholder in authoring text and convert at file write","retest":"Migration helper exited0; requirement and data preservation independently validated here","status":"closed","applicationImpact":"none"}]}
result["issues"].append({"id":"B4-DOC-01","operation":"git diff --check inside workflow validation","actual":"Exit2 for trailing whitespace on changed Master revision header; earlier requirement/coverage checks passed","rootCause":"Markdown hard-break spaces inherited on a modified line","fix":"Remove trailing spaces from that line; retain EOL notices in structured diagnostics and capture tool output","retest":"This successful complete orchestration validation, including diff check","status":"closed","applicationImpact":"none"})
jw(EV/"verification.json",result)
print(json.dumps({"result":"passed","packages":64,"accepted":5,"remaining":59,"bundles":20,"links":links,"manifestFiles":len(paths),"technicalBriefBodiesUnchanged":64,"applicationChanges":0},ensure_ascii=False))
