"""Connect the 48-screen visual audit to the 44 capability walks of the native prototype."""
from collections import deque
from html import escape as e
from pathlib import Path
import csv
from PIL import Image
from coverage_index import baseline
from screen_review import ROWS,PROFILE,TODAY,SHELF,PROGRESS
import finish_routes_a as old_a, finish_routes_b as old_b

ADD_HUB = "_add_to_library"
ADD_METHODS = {"object_scanner_screen", "add_vocab_screen", "wordbook_import_screen"}
PRACTICE_MENU = "main_navigation_screen"
SOURCE_PRACTICE = "source_practice_screen"

def current_route(route):
    """Translate only the shelf shortcuts that moved in the menu redesign."""
    path = [route[0]]
    for origin, target in zip(route, route[1:]):
        if origin == SHELF and target in ADD_METHODS:
            path.append(ADD_HUB)
        elif origin == SHELF and target == SOURCE_PRACTICE:
            if len(path) == 1:
                path[0] = TODAY
            else:
                path.append(TODAY)
            path.append(PRACTICE_MENU)
        path.append(target)
    return path

def suites(d):
    import feature_tasks_a,feature_tasks_b,feature_tasks_c
    features=feature_tasks_a.TASKS|feature_tasks_b.TASKS|feature_tasks_c.TASKS
    assert set(features)==set(range(1,45))
    old=old_a.OWNERS|old_b.OWNERS
    keys={k for k in d.ids if not k.startswith("_")}
    assert set(ROWS).isdisjoint(old.values()) and len(ROWS)==34 and keys==set(ROWS)|set(old.values())
    def path(tab,key):
        q=deque([[tab]]);seen=set()
        while q:
            route=q.popleft();k=route[-1]
            if k==key:return route
            if k in seen:continue
            seen.add(k);q.extend(route+[n] for _,_,n,*_ in d.links[k] if n not in seen and n not in ('@back',TODAY,SHELF,PROGRESS,PROFILE))
        raise ValueError((tab,key))
    screens={}
    for key,(tab,job,tail,witness,literal,note) in ROWS.items():
        if key=="otp_screen":prefix=[PROFILE,"login_screen","register_screen","_register_terms",key]
        elif key=="score_screen":prefix=[TODAY,"select_category_for_quiz","quiz_screen","_quiz_station",key]
        elif tab==SHELF and key in ADD_METHODS:prefix=[SHELF,ADD_HUB,key]
        elif tab==TODAY and key==SOURCE_PRACTICE:prefix=[TODAY,PRACTICE_MENU,key]
        else:prefix=path(tab,key)
        screens[key]=(job,current_route(prefix+tail),witness,literal,note)
    return screens,{i:(job,current_route(route),witness,literal,note)
                    for i,(job,route,witness,literal,note) in features.items()}

def can_navigate(actions,destination):
    for action in actions:
        if action["type"]=="navigate" and action["dest"]==destination:
            return True
        if action["type"]=="conditional" and any(can_navigate(block["actions"],destination) for block in action["blocks"]):
            return True
    return False

def steps(d,route):
    stack=[]
    for a,b in zip(route,route[1:]):
        direct=next((label for node,label,_,*_ in d.links[a]
                     if can_navigate(d.nodes[node]["interactions"][0]["actions"],d.ids[b])),None)
        if direct:stack.append(a);yield direct
        else:
            assert stack and stack[-1]==b,(a,b,route)
            stack.pop();yield next(label for _,label,n,*_ in d.links[a] if n=="@back")

def write(out,d,renders):
    from make_prototype import W,H,font
    screens,features=suites(d);baseline44=baseline(out)
    legacy_names={name:current_route(route) for name,route in old_a.CASES+old_b.CASES}
    legacy_expected=old_a.EXPECT|old_b.EXPECT
    keys=sorted(k for k in d.ids if not k.startswith('_'))
    known=old_a.OWNERS|old_b.OWNERS
    def texts(n):
        node=d.nodes[n]
        if node.get("characters"):yield node
        for kid in node.get("children",[]):yield from texts(kid)
    def evidence(row):
        job,path,k,literal,note=row
        assert k in path and literal in " ".join(n['characters'] for n in texts(d.ids[k])),(job,k,literal)
        buttons=" → ".join(map(e,steps(d,path)))
        return f'<p><b>{e(job)}</b></p><p>เริ่ม <a href="ลองใช้งาน.html#{path[0]}">{e(d.screens[path[0]][1])}</a> → {buttons}</p><p>เห็น “{e(literal)}” · จบที่ <b>{e(d.screens[path[-1]][1])}</b></p><p class="note">{e(note)}</p>'
    styles='''*{box-sizing:border-box}body{margin:0;color:#21253b;background:#f6f7fb;font:17px/1.65 system-ui,sans-serif}main{max-width:1060px;padding:35px clamp(16px,4vw,50px) 75px;margin:auto}h1{line-height:1.3;font-size:clamp(30px,5vw,48px)}h2{margin-top:36px}p{margin:6px 0 12px}a{color:#343f9e}summary{font-weight:650;cursor:pointer;padding:12px 0}details{background:white;border-bottom:1px solid #d9ddea;padding:0 16px}summary:focus-visible,a:focus-visible{outline:3px solid #a85021}article{display:grid;grid-template-columns:minmax(140px,195px) 1fr;gap:20px;margin-bottom:18px}article img{width:100%;height:auto}.note,small{color:#4e5669}nav{display:flex;flex-wrap:wrap;gap:10px 24px;padding:12px 0}code{overflow-wrap:anywhere}@media(max-width:560px){article{grid-template-columns:1fr}article img{width:150px}}'''
    h=[f'<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ตรวจงาน LexiQuest</title><style>{styles}</style><main><h1>ลองทำงานจริงใน LexiQuest</h1><p>ตรวจจากจุดเริ่ม ผลที่ต้องเห็น และหน้าที่ผู้เรียนควรกลับถึง</p><nav><a href="#features">44 ฟีเจอร์</a><a href="#screens">48 หน้าจอ</a><a href="ลองใช้งาน.html">เปิดต้นแบบ</a><a href="final-critique.md">คำวิจารณ์และแหล่งอ้างอิง</a><a href="whole-present.json">ผลกดใน FigCraft</a></nav><h2 id="features">44 ฟีเจอร์ที่ให้ลอง</h2><p>แต่ละข้อใช้เส้นทางตัวอย่างหนึ่งงาน ช่องท้ายอธิบายขอบเขตที่ต้นแบบพิสูจน์ได้</p>']
    for i,row in sorted(features.items()):
        h.append(f'<details id="f{i:02d}"><summary>f{i:02d} · {e(baseline44[i][0])}</summary>{evidence(row)}</details>')
    h.append('<h2 id="screens">48 หน้าจอ: ต้นทาง งาน และทางกลับ</h2><p>ภาพย่อมาจากการส่งออกไฟล์ FigCraft รุ่นนี้ กดภาพเพื่อเปิดหน้า หรือกดจุดเริ่มเพื่อเดินตามงาน ขนาดตัวอักษรเป็นค่าบนผืนงาน 390 × 844 ไม่ใช่การวัดบน Android</p>')
    imgdir=out/"screen-previews";imgdir.mkdir(exist_ok=True)
    with (out/"review-48.csv").open("w",encoding="utf-8-sig",newline="") as f:
        w=csv.writer(f);w.writerow(["หน้าจอ","เมนู","กลุ่มที่ตรวจ","งาน","จุดเริ่ม","ลำดับปุ่ม","ข้อความที่ต้องเห็น","จุดจบ","ข้อสังเกต","ขนาดฟอนต์บนผืนงาน","จำนวนปุ่ม"])
        for k in keys:
            prev=k not in screens
            if prev:
                n=next(n for n,owner in known.items() if owner==k)
                row=(n,legacy_names[n],*legacy_expected[n],"ตรวจซ้ำกับเส้นทางกลุ่ม 14 หน้า ดูกรณีทางเลือกในทะเบียนรอบก่อน")
            else:
                row=screens[k]
            label="ตรวจซ้ำ 14 หน้า" if prev else "ตรวจเพิ่ม 34 หน้า"
            nodes=list(texts(d.ids[k]));sizes=sorted({v["style"]["font_size"] for v in nodes})
            ink=[]
            for n in nodes:
                style=n["style"];size=style["font_size"];bold=style["font_style"]=="Bold"
                x,y=n["transform"][4:6];p=n["parent"]
                while p!=d.ids[k]:
                    par=d.nodes[p];x+=par["transform"][4];y+=par["transform"][5];p=par["parent"]
                x1,y1,x2,y2=font(size,bold).getbbox(n["characters"])
                l,t,r,b=x+x1,y+y1,x+x2,y+y2
                assert 0<=l<=r<=W and 0<=t<=b<=H,(k,n["characters"])
                for ll,tt,rr,bb,text in ink:
                    assert min(r,rr)-max(l,ll)<=1 or min(b,bb)-max(t,tt)<=1,(k,text,n["characters"])
                ink.append((l,t,r,b,n["characters"]))
            note=" / ".join(map(str,sizes))+" px"
            framefile=next(renders.glob(f'LQ{d.ids[k]:03d}*.webp'))
            with Image.open(framefile) as im:
                assert im.size==(W,H)
                im.resize((195,422),Image.Resampling.LANCZOS).save(imgdir/(k+".webp"),quality=87)
            w.writerow([k,d.screens[k][1],label,row[0],row[1][0]," → ".join(steps(d,row[1])),row[3],row[1][-1],row[4],note,len(d.links[k])])
            h.append(f'<details id="{k}"><summary>{e(d.screens[k][1])} · {label}</summary><article><a href="ลองใช้งาน.html#{k}"><img loading="lazy" width="195" height="422" src="screen-previews/{k}.webp" alt="{e(d.screens[k][1])}"></a><div>{evidence(row)}<small>ขนาดอักษรที่ใช้ {note} · <code>{k}</code></small></div></article></details>')
    h.append('<p><a href="review-48.csv">ดาวน์โหลดผลรายหน้า</a> · <a href="task-acceptance.html">ทะเบียน 64 ชุดงานและ 14 หน้าเดิม</a></p></main></html>')
    (out/"review-48-44.html").write_text("".join(h),encoding="utf8")
