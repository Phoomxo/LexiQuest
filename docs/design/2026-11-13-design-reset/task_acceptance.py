"""Publish user journeys separately from the historical 64-package engineering ledger."""
from collections import defaultdict
import csv
from html import escape as e
import json
import re
import subprocess

from coverage_index import flutter_calls
from whole_review import current_route, steps

ORIGINAL="9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe"
AMENDED="53d46a42ce1f1cd31b2d88ee6b73f484cc786f58"
LEDGER="docs/development/2026-09-13-full-system-work-ledger.json"

def ledger(root,revision):
    return json.loads(subprocess.check_output(["git","show",revision+":"+LEDGER],cwd=root))

def write(out,root,design,cases,expects,owners):
    original,later=(ledger(root,r) for r in (ORIGINAL,AMENDED))
    packages=original["packages"]
    ids={p["id"] for p in packages}
    assert len(ids)==len(packages)==64 and len(later["packages"])==67
    by_package=defaultdict(list)
    for c in original["coverage"]:
        for pid in c["packages"]:
            assert pid in ids
            by_package[pid].append(c)
    audit={}
    for line in (out/"feature-64-evidence.md").read_text(encoding="utf8").splitlines():
        if not re.match(r"^\| P\d",line):continue
        pid,caption,_,note=map(str.strip,line.strip("|").split("|"))
        assert pid not in audit
        audit[pid]=(caption,note)
    assert set(audit)==ids
    def probe(key,label):
        assert key in design.ids,key
        return f'<a href="ลองใช้งาน.html#{e(key)}">{e(label)}</a>'
    def title(key):return design.screens[key][1]
    def rows(p):
        caption,note=audit[p["id"]]
        assert caption==p["title"],p["id"]
        links=re.findall(r"\[([^\]]+)\]\(ลองใช้งาน\.html#(\w+)\)",note)
        return by_package[p["id"]],note.partition(" · [")[0],[probe(key,label) for label,key in links]
    css='''*{box-sizing:border-box}body{font:16px/1.65 system-ui,sans-serif;color:#20253b;max-width:1040px;margin:auto;padding:28px clamp(18px,5vw,60px) 100px}h1,h2{line-height:1.35}h1{font-size:32px}h2{margin-top:32px}summary{cursor:pointer;font-weight:620;padding:9px 0}details{border-top:1px solid #d9ddec;padding:4px 0}li{margin:6px 0}a{color:#363e98}code{overflow-wrap:anywhere}small{color:#555d72}.trail{color:#404965;font-size:15px}.jump{background:#f0f1fb;padding:14px;border-radius:8px}'''
    h=[f'<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>64 แพ็กเกจและ 14 เส้นทาง · LexiQuest</title><style>{css}</style><main><h1>64 แพ็กเกจ และงานที่ต้องกดให้จบใน 14 หน้า</h1><p class="jump"><a href="#jobs">ลองเส้นทาง 14 หน้า</a> · <a href="#packages">ดู 64 รหัสเดิม</a> · <a href="system-map.html">แผนผังทั้งระบบ</a> · <a href="packages-64.csv">ดาวน์โหลดตารางเทียบ</a></p>']
    h.append('<p>แผนแม่บทระบุ 64 แพ็กเกจใน 9 ระยะ อีกทะเบียนหนึ่งระบุ 44 ความสามารถของผลิตภัณฑ์ 14 โหมดเรียน 2 เส้นทาง และ 14 กลุ่มปฏิสัมพันธ์ บางรายการใช้หลายแพ็กเกจ และบางแพ็กเกจเป็นการทดสอบหรือส่งมอบ ไม่ได้มีหน้าจอของตัวเอง</p>')
    files,refs=flutter_calls(root)
    reachable={"main","app_route_factory"}
    while True:
        prior=len(reachable)
        reachable.update(b for a,b,*_ in refs if a in reachable)
        if len(reachable)==prior:break
    detached=files-reachable
    assert len(detached)==14
    by_screen=defaultdict(list)
    case_names=set()
    for name,old_path in cases:
        path=current_route(old_path)
        assert name not in case_names and path[0] in {"choose_mode_screen","categories_page","mastery_dashboard_screen","profile_settings_screen"} and all(k in design.ids for k in path),name
        case_names.add(name)
        by_screen[owners[name]].append((name,path))
    assert detached==set(by_screen) and case_names==set(expects)==set(owners)
    assert all(len(jobs)>=2 for jobs in by_screen.values())
    h.append(f'<h2 id="jobs">14 หน้าที่ตามสายเรียกจากจุดเริ่มของ Flutter ไม่ถึง</h2><p>{len(cases)} งานให้ลองกด เปิดหน้าต้นทาง แล้วทำตามชื่อปุ่ม แต่ละกรณีระบุข้อความที่ควรเห็นกับหน้าที่ควรกลับถึง การไม่พบสายเรียกเป็นผลจากการอ่านโค้ด ส่วนการกดตรวจในรอบนี้ทำบนต้นแบบ</p><p><a href="detached-a.md">เหตุผลและทางเข้าออก · ตัวละคร ด่านสะกดคำ การอ่าน ระดับคำ ฝึกฟัง</a> · <a href="detached-b.md">เสียง ผลด่าน พื้นหลัง เรียงประโยค คิวฟัง กราฟ นำเข้า</a></p>')
    for key in sorted(detached):
        h.append(f'<details id="{key}"><summary>{e(title(key))} · {len(by_screen[key])} งานให้ลอง</summary><small>{e(key)}</small><ul>')
        for name,path in by_screen[key]:
            node,expected=expects[name]
            assert node in path,(name,node)
            buttons=" → ".join(map(e,steps(design,path)))
            h.append(f'<li><b>{e(name)}</b> · {probe(path[0],"เริ่มที่"+title(path[0]))}<div class="trail">{buttons}</div>เกณฑ์: เห็น “{e(expected)}” ในหน้า {e(title(node))} · จบที่ {e(title(path[-1]))}</li>')
        h.append('</ul></details>')
    h.append('<h2 id="packages">ทะเบียน 64 แพ็กเกจฉบับต้นทาง</h2><p>ชื่อและความสัมพันธ์มาจากทะเบียนงาน กดที่ชื่อเพื่อดูว่าผู้เรียนทำอะไรได้ และยังต้องใช้หลักฐานอะไรอีก 43 งานมีลิงก์ให้ดูตัวอย่างหน้าจอ อีก 21 งานต้องตรวจจากซอร์ส ข้อมูล โมเดล หรือรุ่นที่ติดตั้งจริง</p>')
    with (out/"packages-64.csv").open("w",encoding="utf-8-sig",newline="") as f:
        w=csv.writer(f);w.writerow(["รหัสแสดงผล","รหัสดั้งเดิม","ระยะ","งาน","รหัสความครอบคลุมต้นทาง","สิ่งที่ทำได้หรือควรตรวจ","หลักฐานตามแผน","ข้อกำหนด","รหัสที่ต้องเสร็จก่อน","ตัวอย่าง test targets ตามแผน"])
        for phase in original["phases"]:
            prefix=f'G{phase["id"]}.'
            phase_rows=[p for p in packages if p["displayId"].startswith(prefix)]
            assert len(phase_rows)==phase["count"]
            h.append(f'<h3>{e(phase["gate"])} · {e(phase["title"])} ({len(phase_rows)})</h3>')
            for p in phase_rows:
                matches,note,links=rows(p)
                names=", ".join(c["id"] for c in matches)
                w.writerow([p["displayId"],p["id"],phase["title"],p["title"],names,note,p["verificationKind"],", ".join(p["requirements"]),", ".join(p["dependencies"]),"; ".join(p.get("testTargets",[]))])
                h.append(f'<details><summary>{e(p["displayId"])} · {e(p["title"])}</summary><p>{e(note)}</p><p>{" · ".join(links)}</p><small>รหัสเดิม {e(p["id"])} · วิธีตรวจตามแผน <code>{e(p["verificationKind"])}</code><br>{e(names) if names else "ไม่มีรหัสความสามารถผูกโดยตรงในทะเบียน"}</small></details>')
    delta=[p for p in later["packages"] if p["id"] not in ids]
    assert len(delta)==3 and ids<={p["id"] for p in later["packages"]}
    h.append('<h2>ฉบับแก้ไข: 67 แพ็กเกจ</h2><p>คง 64 รหัสเดิม และเพิ่ม '+', '.join(e(p["displayId"]+" "+p["title"]) for p in delta)+'</p>')
    h.append(f'<p><a href="feature-64-evidence.md">บันทึกหลักฐาน</a> · <a href="present-evidence.json">ผลกดใน FigCraft</a><br><small>Git: {ORIGINAL[:12]} → {AMENDED[:12]} · {LEDGER}</small></p></main></html>')
    (out/"task-acceptance.html").write_text("".join(h),encoding="utf8")
