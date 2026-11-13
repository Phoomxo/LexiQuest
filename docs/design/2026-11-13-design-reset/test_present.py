"""Walk user tasks in the FigCraft 0.18.1 desktop presenter, not the HTML mirror."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from html.parser import HTMLParser
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
from whole_review import ADD_HUB, can_navigate, current_route

OUT=Path(__file__).resolve().parent
APP=Path(os.environ["ProgramFiles"])/"ArtCraft/FigCraft/figcraft.exe"

def run(cases,expects):
    with tempfile.TemporaryDirectory(prefix="lexiquest-present-") as folder:
        tmp=Path(folder)
        native=tmp/"LexiQuest.figcraft"
        shutil.copyfile(OUT/native.name,native)
        subprocess.run([APP.with_name("figcraft-cli.exe"),"convert",native,tmp/"readback.json"],check=True,stdout=subprocess.DEVNULL)
        nodes=json.loads((tmp/"readback.json").read_text(encoding="utf8"))["nodes"]
        class Sections(HTMLParser):
            def handle_starttag(self,tag,attrs):
                if tag=="section":self.frames.append((dict(attrs)["id"],dict(attrs)["aria-label"]))
        mirror=Sections();mirror.frames=[]
        mirror.feed((OUT/"ลองใช้งาน.html").read_text(encoding="utf8"))
        frame_ids=nodes["1"]["children"]
        assert len(frame_ids)==len(mirror.frames)
        frames={}
        for fid,(key,title) in zip(frame_ids,mirror.frames):
            assert nodes[str(fid)]["name"]==f"LQ{fid:03d} · {title}"
            frames[key]=fid
        def text_layers(fid):
            node=nodes[str(fid)]
            if node.get("characters"):yield node["characters"]
            for child in node.get("children",[]):yield from text_layers(child)
        with closing(socket.socket()) as s:
            s.bind(("127.0.0.1",0))
            port=s.getsockname()[1]
        proc=subprocess.Popen([APP,"--control",str(port),"--automation-read-root",tmp,"--automation-write-root",tmp,native])
        try:
            deadline=time.monotonic()+18
            while True:
                try:sock=socket.create_connection(("127.0.0.1",port),.6);break
                except OSError:
                    if proc.poll() is not None or time.monotonic()>deadline:raise
                    time.sleep(.15)
            with closing(sock),sock.makefile("rwb") as io:
                sock.settimeout(12)
                def call(method,**params):
                    io.write((json.dumps(dict(id=1,method=method,params=params,timeoutMs=8000))+"\n").encode());io.flush()
                    result=json.loads(io.readline())
                    if not result.get("ok"):raise RuntimeError((method,result.get("error")))
                    return result["result"]
                def state(expected):
                    for _ in range(15):
                        st=call("ui.inspect").get("presenter") or {}
                        hotspots=[h for h in st.get("hotspots") or []
                                  if any(i["trigger"]["type"]=="onClick" for i in nodes[str(h["id"])].get("interactions",[]))]
                        if st.get("current")==expected and hotspots and all(nodes[str(h["id"])].get("parent")==expected for h in hotspots):
                            return st|{"hotspots":hotspots}
                        time.sleep(.08)
                    raise AssertionError(("presenter",expected,st.get("current"),st.get("name"),list(st)))
                doc=call("document.inspect",depth=0)
                assert Path(doc["path"]).resolve()==native.resolve(),doc.get("path")
                counts=[]
                for title,old_path in cases:
                    route=current_route(old_path)
                    if counts:
                        call("ui.input",events=[{"key":"Escape"}])
                        for _ in range(20):
                            if not call("ui.inspect").get("presenter"):break
                            time.sleep(.08)
                        else:raise AssertionError(("previous presentation did not close",title))
                    call("engine.execute",command="proto.present",params={"start":frames[route[0]]})
                    st=state(frames[route[0]])
                    stack=[]
                    clicked=[]
                    witness,literal=expects[title]
                    assert witness in route,(title,witness)
                    verified=False
                    def check_visible(key):
                        if key!=witness:return False
                        assert st["current"]==frames[key] and literal in " ".join(text_layers(st["current"])),(title,key,literal)
                        return True
                    verified=check_visible(route[0])
                    for start,end in zip(route,route[1:]):
                        buttons=[(nodes[str(item["id"])],item["rect"]) for item in st["hotspots"]]
                        def match(node,back):
                            acts=node["interactions"][0]["actions"]
                            if back:
                                return stack and stack[-1]==end and any(act["type"]=="back" for act in acts)
                            return can_navigate(acts,frames[end])
                        found=next(((n["name"],rect,back) for back in (False,True) for n,rect in buttons if match(n,back)),None)
                        if found is None:raise AssertionError((title,start,end,"missing hotspot",[n["name"] for n,_ in buttons]))
                        label,rect,back=found
                        pt=[(rect[0]+rect[2])/2,(rect[1]+rect[3])/2]
                        call("ui.input",events=[{"move":pt},{"down":pt}])
                        call("ui.input",events=[{"up":pt}])
                        st=state(frames[end])
                        clicked.append(label)
                        verified=check_visible(end) or verified
                        if back:stack.pop()
                        else:stack.append(start)
                    assert verified,title
                    counts.append(dict(task=title,start=route[0],buttons=clicked,clicks=len(clicked),witness=witness,text=literal,landing=route[-1]))
                return dict(figcraft_sha256=hashlib.sha256(native.read_bytes()).hexdigest(),presenter="FigCraft desktop 0.18.1",cases=counts,clicks=sum(c["clicks"] for c in counts))
        finally:
            proc.terminate();proc.wait(timeout=10)

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument("--probe",action="store_true")
    mode.add_argument("--whole",action="store_true",help="Also run the 34 screen and 44 capability walks")
    mode.add_argument("--camera-boundaries",action="store_true",help="Check the library after denial, failed save and retry")
    mode.add_argument("--menus",action="store_true",help="Exercise the practice and vocabulary menus and their returns")
    args=parser.parse_args()
    if args.probe:
        cases=[("ทดสอบโหมดนำเสนอ",["categories_page","object_scanner_screen","_scan_permission"])]
        expects={cases[0][0]:("categories_page","คลังคำศัพท์")}
    elif args.menus:
        home,library="choose_mode_screen","categories_page"
        search,word="_search_library","_station_in_library"
        review=["srs_flashcards_screen","_card_reveal","_card_remembered"]
        assignment=["_today_jobs","_assigned_word","_assigned_reveal","_today_jobs_done"]
        menu_tasks=[
            ("ยกเลิกเพิ่มคำแล้วกลับไปฝึกภาษา",[home,library,ADD_HUB,library,home],ADD_HUB,"เพิ่มคำศัพท์"),
            ("เปิดการพิมพ์คำแล้วกลับคลัง",[library,ADD_HUB,"add_vocab_screen",ADD_HUB,library],"add_vocab_screen","suitcase"),
            ("เปิดกล้องแล้วกลับคลัง",[library,ADD_HUB,"object_scanner_screen",ADD_HUB,library],"object_scanner_screen","ถ้วย"),
            ("เลือกนำเข้าไฟล์แล้วกลับคลัง",[library,ADD_HUB,"wordbook_import_screen",library],"wordbook_import_screen","คำบนรถไฟ.csv"),
            ("ค้น station จากทุกชุด อ่านคำแล้วกลับเข้าชุดเดิม",[library,search,word,"_word",word,library,"vocab_list_screen",library],word,"การเดินทาง"),
            ("เปิดข้อความจากเมนูฝึก อ่านคำแล้วกลับมาหน้าฝึก",[home,"main_navigation_screen","source_practice_screen","_ticket","source_practice_screen","main_navigation_screen",home],"_ticket","Here is my ticket."),
            ("ทำงานที่ได้รับก่อน ทบทวนคำ แล้วกลับจากคลัง",
             [home,*assignment,"_today_after_assignment",library,"_today_after_assignment",*review,
              "_home_after_both",library,"_home_after_both","_today_jobs_done","_home_after_both"],
             "_home_after_both","ใช้คำในประโยค"),
            ("ทบทวนคำก่อน ทำงานที่ได้รับ แล้วกลับมาใช้คำในประโยค",
             [home,*review,"_home_after_review",library,"_home_after_review",*assignment,
              "_home_after_both","fill_in_the_blanks_screen","_fill_right","_home_after_both"],
             "_home_after_both","งานที่ทำเสร็จ"),
        ]
        cases=[(name,path) for name,path,_,_ in menu_tasks]
        expects={name:(frame,label) for name,_,frame,label in menu_tasks}
    elif args.camera_boundaries:
        library,scanner="categories_page","object_scanner_screen"
        check_empty=[library,"_kitchen_empty",library,"_search_library","_cup_not_found",library]
        denied="ปฏิเสธกล้องแล้วกลับมาตรวจชุดครัวและการค้นหา"
        retry="ตรวจคลังหลังบันทึกไม่ผ่าน แล้วลองเก็บอีกครั้ง"
        cases=[
            (denied,[library,scanner,"_scan_permission","_scan_denied","_scan_locked",
                     "device_permission_center_screen","choose_mode_screen",*check_empty]),
            (retry,[library,scanner,"_scan_examples","_scan_save_failed","_scan_examples",scanner,ADD_HUB,*check_empty,
                    scanner,"_scan_examples","_scan_save_failed","_scan_saved","_scan_collection",library,
                    "choose_mode_screen",library,"_scan_collection","_scan_cup_detail",library,
                    "_search_library","_scan_cup_detail",library])]
        expects={denied:("_kitchen_empty","ยังไม่มีคำในชุดนี้"),retry:("_scan_cup_detail","เก็บจากกล้อง · ชุดของใช้ในครัว")}
    else:
        from finish_routes_a import CASES as a, EXPECT as ea
        from finish_routes_b import CASES as b, EXPECT as eb
        cases=[*a,*b]
        expects=ea|eb
        if args.whole:
            from make_prototype import build_design
            from whole_review import suites
            pages,features=suites(build_design())
            for records,is_feature in ((features,True),(pages,False)):
                for key,(job,path,witness,literal,_) in sorted(records.items()):
                    label=(f"f{key:02d}" if is_feature else key)+" · "+job
                    cases.append((label,path));expects[label]=(witness,literal)
    report=run(cases,expects)
    if not args.probe:
        def write_report(filename,data):
            (OUT/filename).write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
        if args.camera_boundaries:
            write_report("camera-boundaries.json",report)
        elif args.menus:
            write_report("menu-present.json",report)
        elif args.whole:
            write_report("whole-present.json",report)
            old=report["cases"][:len(a)+len(b)]
            write_report("present-evidence.json",report|dict(cases=old,clicks=sum(case["clicks"] for case in old)))
        else:
            write_report("present-evidence.json",report)
    print("FigCraft desktop:",len(cases),"completed cases,",report["clicks"],"clicks")
