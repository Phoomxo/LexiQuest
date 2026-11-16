"""Publish an offline architecture index from source call sites and final FigCraft actions."""
import csv
from collections import defaultdict
from html import escape
from pathlib import Path
import re

GROUPS = [
    ("เนื้อหาและชุดเรียน", "ค้นชุด ดูคำ ตรวจที่มา แล้วเลือกสิ่งที่จะฝึก", [1,2,3,4]),
    ("รูปแบบการฝึก", "เลือกรูปแบบโจทย์ ลงมือตอบ และเห็นผลรอบเดียวกัน", list(range(5,14))),
    ("การจำและผลตอบกลับ", "ทบทวน เปิดคำใบ้ เข้าใจตัวลวง และเก็บคำที่อยากฝึกต่อ", list(range(14,22))),
    ("ทบทวน เวลา และการประเมิน", "วางแผนเวลาและดูว่าฝึกอะไรไปแล้ว", list(range(22,29))),
    ("แรงจูงใจ", "ดูภารกิจ ความต่อเนื่อง ความสำเร็จ และของสะสม", list(range(29,35))),
    ("ปรับตามผู้เรียน", "ตั้งเป้า เลือกวิธีเรียน และปรับการแสดงผล", list(range(35,40))),
    ("ออฟไลน์และความพร้อม", "ตรวจเนื้อหาในเครื่อง คิวที่รอส่ง และข้อจำกัดของบริการ", [40,41,44]),
    ("วันนี้และประวัติ", "กลับมาต่องานที่ถึงกำหนดและเปิดดูผลแต่ละรอบ", [42,43]),
]

# Prefer the narrowest actual frame; fallback to the audited original only when present.
NEW = {
    1:"_packs",2:"_pack",4:"_provenance",8:"_definition_quiz",10:"_matching",
    11:"_source_recall",12:"_scratchpad",15:"_recall_ladder",16:"_setup_round",20:"_bookmarked",
    21:"_report",22:"_review_desk",23:"_plan_timer",24:"_plan_time_log",25:"_plan_week",26:"_plan_goal",28:"_paired_sample",
    27:"_plan_reminder",29:"_plan_quest",30:"_plan_streak",33:"_plan_friend",34:"_plan_share",
    35:"_plan_preferences",36:"_plan_profile",38:"_plan_access",39:"_plan_still",40:"_local_status",
    41:"_availability",44:"_offline_manager",
}
LIMITS = {
    5:"ยังต้องตรวจองค์ประกอบระหว่างทุกชนิดโจทย์และช่วงแป้นพิมพ์",
    11:"ใช้คำตอบตัวอย่าง ยังไม่ได้ทดสอบป้อนคำอิสระด้วย IME",
    12:"ใช้สถานะขีดเขียนจำลอง ยังไม่ได้วาดเส้นอิสระ",
    16:"เลือกชุดและตัวอย่างรอบหนึ่งหรือสองคำได้ ยังไม่มีการตั้งค่าครบร่วมกันทั้งเวลา เสียง และการช่วยการเข้าถึง",
    17:"มี feedback และทางไปต่อ ยังต้องตรวจ write failure/retry จากระบบจัดเก็บจริง",
    22:"ทางเข้าศูนย์ทบทวนเป็นข้อเสนอ การเก็บและเรียกรายการจริงยังขึ้นกับระบบในแอป",
    24:"แสดงวิธีคิดเวลาด้วยตัวอย่าง ยังไม่ได้วัดระยะเวลาจากเครื่อง",
    27:"วันเวลาเตือนเป็นสถานะต้นแบบ ยังไม่ส่งการแจ้งเตือน",
    28:"ใช้ข้อมูลคู่ก่อน–หลังสมมติเพื่อแสดงวิธีอ่านผล การใช้ข้อมูลวิจัยจริงต้องมีสิทธิ์และแบบวัดที่ตรวจสอบได้",
    38:"แบบตัวอักษรใหญ่/ภาพนิ่งเป็นตัวอย่าง ยังต้องทดสอบ TalkBack และการปรับตัวอักษรจริง",
    40:"แสดงสถานะออฟไลน์ด้วยข้อมูลตัวอย่าง การคืนคิวและแก้ conflict ยังต้องตรวจในแอป",
}

NAMED = {"login":"login_screen","register":"register_screen","home":"main_navigation_screen","emailVerification":"otp_screen"}
TABS = {"choose_mode_screen","categories_page","mastery_dashboard_screen","profile_settings_screen"}
LIMITED = {"object_scanner_screen","ai_tutor_screen","shadowing_challenge_screen","speak_to_text_screen"}


def flutter_calls(root):
    lib=root/"lib"
    files=sorted((lib/"screens").glob("*.dart"))
    classes={}
    for path in files:
        match=re.search(r"class (\w+) extends (?:Stateless|Stateful|ConsumerStateful|Consumer)Widget\b",path.read_text(encoding="utf8"))
        assert match,path
        classes[match[1]]=path.stem
    pattern=re.compile(r"\b("+"|".join(classes)+r")\s*\(")
    named=re.compile(r"\bAppRoute\.(login|register|home|emailVerification)\b")
    refs=[]
    for path in sorted(lib.rglob("*.dart")):
        if path.name.endswith((".g.dart",".freezed.dart")) or path.name=="app_routes.dart":
            continue
        source=path.stem
        rel=path.relative_to(root).as_posix()
        for ln,line in enumerate(path.read_text(encoding="utf8").splitlines(),1):
            code=line.partition("//")[0]
            for m in pattern.finditer(code):
                dest=classes[m[1]]
                if dest==source:continue
                if source=="app_route_factory": role="route factory"
                elif source=="main_navigation_screen" and dest in TABS:role="แท็บใน shell"
                else:role="จุดเรียก constructor"
                refs.append((source,dest,role,rel,ln))
            for m in named.finditer(code):
                refs.append((source,NAMED[m[1]],"named route",rel,ln))
    return {p.stem for p in files},refs


def baseline(out):
    records={}
    for line in (out/"feature-coverage.md").read_text(encoding="utf8").splitlines():
        if re.match(r"^\| f\d\d \|",line):
            code,title,source,link,status,detail,old=map(str.strip,line.strip("|").split("|"))
            m=re.search(r"ลองใช้งาน\.html#(\w+)",link)
            records[int(code[1:])]=(title,source,m[1] if m else "",status,detail)
    assert set(records)==set(range(1,45))
    return records


def write(out,root,design):
    from make_prototype import destinations,route_branch
    out,root=Path(out),Path(root)
    base=baseline(out)
    files,refs=flutter_calls(root)
    assert files=={k for k in design.screens if not k.startswith("_")}
    adj=defaultdict(set)
    for a,b,*_ in refs:adj[a].add(b)
    seen=set()
    stack=["main","app_route_factory"]
    while stack:
        a=stack.pop()
        if a not in seen:
            seen.add(a)
            stack.extend(adj[a]-seen)
    rows=[]
    incoming=defaultdict(list)
    outgoing=defaultdict(list)
    for src,dest,role,path,line in refs:
        citation=f"{path}:{line}"
        rows.append(["Flutter",src,dest,role,citation])
        incoming[dest].append((src,role,citation))
        outgoing[src].append((dest,role,citation))
    reverse=defaultdict(list)
    for src,links in design.links.items():
        for _,label,dest,*_ in links:
            for landing,condition in destinations(route_branch(src,dest)):
                note=condition or ("ย้อนกลับตามประวัติ" if landing=="@back" else "onClick → navigate")
                rows.append(["FigCraft",src,landing,label,note])
                if landing!="@back":reverse[landing].append(src)
    with (out/"routes.csv").open("w",encoding="utf-8-sig",newline="") as fh:
        writer=csv.writer(fh)
        writer.writerow(["ชนิดหลักฐาน","ต้นทาง","ปลายทาง","การกระทำ","ที่มา"])
        writer.writerows(rows)
    def link(key,title=None):
        if key=="@back":return "ย้อนกลับตามประวัติ"
        return f'<a href="ลองใช้งาน.html#{escape(key,quote=True)}">{escape(title or design.screens[key][1])}</a>'
    def evidence(items):
        return ", ".join(f'{escape(other)} ({escape(role)} · <a href="../../../{path.split(":")[0]}">{escape(path)}</a>)' for other,role,path in items) or "ไม่พบจุดเรียกตามวิธีตรวจนี้"
    def details(title,body):
        return f"<details><summary>{title}</summary>{body}</details>"
    chunks=['''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>แผนผังระบบ LexiQuest</title><style>
*{box-sizing:border-box}body{margin:0;background:#f7f8fc;color:#21253e;font:17px/1.7 system-ui,sans-serif}main{max-width:1060px;margin:auto;padding:32px clamp(16px,4vw,54px) 80px}h1{font-size:clamp(28px,4vw,43px);line-height:1.3}h2{margin-top:38px}h3{margin:.65em 0 .25em}a{color:#303c9d;text-underline-offset:3px}details,article{padding:12px 0;border-bottom:1px solid #dce0ed}summary{cursor:pointer;font-weight:650}section{background:white;border-radius:14px;margin:16px 0;padding:10px 22px 20px}small{color:#515a70}.query{display:block;width:100%;font:inherit;padding:10px 16px;border-radius:10px;border:1px solid #7a8197}nav a{display:inline-block;margin:4px 14px 4px 0}p{margin:.45em 0}code{overflow-wrap:anywhere;font-size:.86em}li{padding:3px 0}
</style><main><h1>แผนผังระบบ LexiQuest</h1>''']
    total=sum(map(len,design.links.values()))
    chunks.append(f'<p>ทะเบียนผลิตภัณฑ์ 8 หมวด 44 ข้อ · Flutter {len(files)} ไฟล์หน้า · ต้นแบบ {len(design.ids)} เฟรม {total} จุดกด</p><p><a href="task-acceptance.html">เทียบ 64 แพ็กเกจงาน และลองเส้นทางเข้า–จบ–กลับของ 14 หน้า</a></p>')
    chunks.append('<nav><a href="ลองใช้งาน.html">เปิดต้นแบบ</a><a href="#catalog">ดูความสามารถทั้ง 44 ข้อ</a><a href="#source">ดูทางเข้า Flutter</a><a href="#actions">ดูทางเดินทั้งหมด</a><a href="routes.csv">ดาวน์โหลดตารางเส้นทาง</a><a href="feature-coverage.md">อ่านผลตรวจรุ่นตั้งต้น</a></nav>')
    chunks.append('<label for="q">ค้นหาตามชื่อฟีเจอร์ คำไทย รหัส หรือชื่อไฟล์</label><input class="query" id="q" type="search" placeholder="เช่น กล้อง จับคู่ f08"><p id="found" aria-live="polite"></p><h2 id="catalog">ความสามารถของผู้เรียน</h2><p>แต่ละข้อแสดงหลักฐานเดิมใน Flutter และลิงก์ตัวอย่างล่าสุด ผลตรวจตั้งต้นอ้างถึงรุ่น 111 เฟรม เฟรมข้อเสนอใหม่เป็นแบบให้ลองกด การเปิดใช้ใน Flutter ขึ้นกับการพัฒนาและสิทธิ์ของแต่ละฟีเจอร์</p>')
    for label,job,ids in GROUPS:
        chunks.append(f'<section><h3>{label}</h3><p>{job}</p>')
        for idx in ids:
            title,source,key,status,detail=base[idx]
            targeted=NEW.get(idx)
            proposed=targeted in design.screens
            dest=targeted if proposed else key
            page=link(dest) if dest in design.screens else "ยังไม่มีปลายทางที่ยืนยันได้"
            limit=("<p>"+escape(LIMITS[idx])+"</p>") if idx in LIMITS else ""
            chunks.append(details(f'f{idx:02d} · {escape(title)}',f'<p>ตัวอย่างปัจจุบัน · {page} {" · ข้อเสนอในต้นแบบ" if proposed else ""}</p>{limit}<p>Flutter · {escape(source)}</p><small>รุ่นตั้งต้น · {status} · {escape(detail)}</small>'))
        chunks.append('</section>')
    chunks.append('<h2 id="source">48 ไฟล์หน้าของ Flutter</h2><p>ตรวจ constructor และ AppRoute ใน lib/ พร้อมผู้เรียกจริง ติดตามสายการเรียกจาก main และ route factory รวมการฝังหน้าในแท็บ ผลนี้เป็นหลักฐานจากโค้ด การแตะได้จริงขึ้นกับเงื่อนไขขณะใช้งาน ฟีเจอร์ที่ไม่มีสายเข้าจะระบุไว้ให้ตรวจต่อ</p><section>')
    for key in sorted(files):
        state=("พบสายเรียกจากจุดเริ่ม" if key in seen else "ยังไม่พบสายจากจุดเริ่ม")
        if key in LIMITED: state+=" · จำกัดตามสิทธิ์/บริการ"
        note="ใน Flutter ไฟล์นี้เป็น shell ครอบแท็บ ส่วนต้นแบบใช้เฟรมที่ผูกชื่อไฟล์นี้เป็นหน้าเลือกวิธีฝึก" if key=="main_navigation_screen" else ""
        chunks.append(details(f'{escape(design.screens[key][1])} · <code>{key}</code>',f'<p>{state} · {link(key,"ดูตัวอย่าง")} {note}</p><p>ทางเข้าจาก source · {evidence(incoming[key])}</p><p>ทางออกจาก source · {evidence(outgoing[key])}</p>'))
    chunks.append('</section><h2 id="actions">จุดกดเข้า–ออกของทุกเฟรม</h2><p>ปุ่มย้อนกลับใช้ประวัติของผู้ใช้ ปลายทางของปุ่มอื่นแสดงตามข้อมูลที่นำไปสร้างไฟล์ FigCraft</p><section>')
    for key,links in design.links.items():
        ins=", ".join(link(src) for src in dict.fromkeys(reverse[key])) or "เริ่มจาก flow"
        def where(dest):
            return " / ".join(f'{condition} → {link(landing)}' if condition else link(landing)
                              for landing,condition in destinations(route_branch(key,dest)))
        outs="<ul>"+"".join(f'<li>{escape(label)} → {where(dest)}</li>' for _,label,dest,*_ in links)+"</ul>"
        chunks.append(details(f'{escape(design.screens[key][1])} · <code>{key}</code>',f'<p>{link(key,"เปิดเฟรมนี้")}</p><p>มาจาก {ins}</p>{outs}'))
    chunks.append('''</section><p>หลักฐานเก่า · <a href="../2026-10-20-r11-implementation-map.md">R11 จำนวน 240 ตัวอย่าง และ 942 ทางเชื่อม</a></p>
<script>let q=document.getElementById('q');q.addEventListener('input',()=>{let t=q.value.trim().toLocaleLowerCase();let n=0;for(let d of document.querySelectorAll('details')){d.hidden=!!t&&!d.textContent.toLocaleLowerCase().includes(t);if(!d.hidden)n++}for(let s of document.querySelectorAll('section'))s.hidden=!!t&&!s.querySelector('details:not([hidden])');document.getElementById('found').textContent=t?'พบ '+n+' รายการ':''});</script></main></html>''')
    (out/"system-map.html").write_text("".join(chunks),encoding="utf8")
