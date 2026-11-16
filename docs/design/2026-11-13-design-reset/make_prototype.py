"""Build the editable FigCraft document and its offline click-through from the same layers."""
from __future__ import annotations
import base64
import functools
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import ImageFont
import focused_library
import focused_learning
import focused_account
import camera_routes
import exam_routes
import pack_routes
import coverage_index
import proposed_planner
import finish_routes_a
import finish_routes_b
import task_acceptance
import screen_review
import whole_review
import feature_tasks_a
import feature_tasks_b
import feature_tasks_c
import learn_home

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
CLI = shutil.which("figcraft-cli") or str(Path(os.environ.get("ProgramFiles", "")) / "ArtCraft/FigCraft/figcraft-cli.exe")
FONT = ROOT / "assets/fonts/NotoSansThai-Variable.ttf"
W, H = 390, 844
PAPER, INK, SUB, RULE = "#FBFBFE", "#1F2441", "#525B73", "#DADEEB"
DEEP, MINT, RUST, LIME = "#3942AD", "#EBEDF9", "#9C4823", "#FFE39B"
WHITE = "#FFFFFF"
TABS = {"ฝึกภาษา":"choose_mode_screen", "คลังคำศัพท์":"categories_page", "ความก้าวหน้า":"mastery_dashboard_screen", "บัญชี":"profile_settings_screen"}
SCALE = {13:"หมายเหตุ",15:"คำกำกับ",17:"เนื้อหา",20:"หัวข้อย่อย",22:"หัวข้อส่วน",26:"ชื่อหน้ารอง",32:"ชื่อหน้า",36:"คำเป้าหมาย"}


@functools.lru_cache(None)
def font(size, bold):
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_name("Bold" if bold else "Regular")
    return f


def color(s):
    return dict(zip(("r","g","b","a"), [int(s[k:k+2],16)/255 for k in (1,3,5)] + [1]))


def paint(s):
    return [{"type":"solid","color":color(s),"opacity":1,"visible":True,"blend":"normal"}] if s else []


def commands(*args):
    result = subprocess.run([CLI, *map(str,args)],capture_output=True, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(result.stderr + result.stdout[-1500:])
    return result.stdout


CUP_SAVED = "cup-saved"
ASSIGNED = "assignment-done"
REMEMBERED = "platform-remembered"
VARIABLES = {
    CUP_SAVED: ("เก็บคำว่า cup แล้ว", "ยังไม่ได้เก็บ cup"),
    ASSIGNED: ("ทำงานที่ได้รับแล้ว", "ยังไม่ได้ทำงานที่ได้รับ"),
    REMEMBERED: ("ทบทวน platform แล้ว", "ยังต้องทบทวน platform"),
}
COMPLETIONS = {
    ("_scan_result", "_scan_saved"): CUP_SAVED,
    ("_scan_save_failed", "_scan_saved"): CUP_SAVED,
    ("_assigned_reveal", "_today_jobs_done"): ASSIGNED,
    ("_card_reveal", "_card_remembered"): REMEMBERED,
}
SAVED_DESTINATIONS = {
    ("categories_page", "_kitchen_empty"): "_scan_collection",
    ("_search_library", "_cup_not_found"): "_scan_cup_detail",
}
HOME_BRANCH = (ASSIGNED, (REMEMBERED, "_home_after_both", "_today_after_assignment"),
                         (REMEMBERED, "_home_after_review", "choose_mode_screen"))
JOBS_BRANCH = (ASSIGNED, "_today_jobs_done", "_today_jobs")


def route_branch(source,target):
    if target in learn_home.STATES:
        return HOME_BRANCH
    if target == "_today_jobs":
        return JOBS_BRANCH
    if saved := SAVED_DESTINATIONS.get((source,target)):
        return (CUP_SAVED, saved, target)
    return target


def destinations(branch, conditions=()):
    if isinstance(branch,str):
        yield branch, " · ".join(conditions)
        return
    flag,yes,no = branch
    for option,condition in zip((yes,no), VARIABLES[flag]):
        yield from destinations(option, (*conditions,condition))


def native_actions(ids, branch, current=None):
    if branch == "@back":
        return [{"type":"back"}]
    if isinstance(branch,str):
        return [] if branch == current else [{"type":"navigate","dest":ids[branch]}]
    flag, yes, no = branch
    return [{"type":"conditional","blocks":[
        {"condition":{"value":{"type":"alias","value":flag}}, "actions":native_actions(ids,yes,current)},
        {"actions":native_actions(ids,no,current)},
    ]}]


def click_actions(ids,source,target):
    actions = native_actions(ids,route_branch(source,target))
    if flag := COMPLETIONS.get((source,target)):
        actions.insert(0, {"type":"setVariable","variable":flag,"value":True})
    return actions


class Design:
    def __init__(self, screens):
        self.screens = screens
        self.styles = {}
        self.nodes = {1:dict(id=1,type="page",name="LexiQuest · ต้นแบบ",width=0,height=0,children=[],flows=[],background=color("#D4DAD6"))}
        self.ids, self.links, self.source_frames = {}, {}, {}
        self.page = self.nodes[1]
        for key, spec in screens.items():
            i = len(self.ids)
            fid = self.add(1,"frame",spec[1],(i%9)*460,(i//9)*930,W,H,PAPER,children=[],clip=True)
            self.ids[key] = fid
            self.links[key] = []
        for key, (family, title, eyebrow, blocks, buttons, tab) in screens.items():
            self.key, self.frame = key,self.ids[key]
            self.dark = key == "_appearance_dark"
            self.paper,self.ink,self.sub,self.rule = (("#203831","#F3F7EF","#C4D6C9","#526D60") if self.dark else (PAPER,INK,SUB,RULE))
            self.nodes[self.frame]["fills"] = paint(self.paper)
            if key=="_wallpaper_preview":
                for j in range(7):
                    self.box(298+j*14,59,2,88-j*8,"#D6DED1",1,name="เส้นบนกระดาษ")
            self.render(family,title,eyebrow,blocks,buttons,tab)
            if key in learn_home.STATES or key == "_today_jobs":
                # Back in the native presenter restores the actual previous frame.
                # Refresh a stale hub/queue when re-entered through that history.
                branch = HOME_BRANCH if key in learn_home.STATES else JOBS_BRANCH
                self.nodes[self.frame]["interactions"] = [{"trigger":{"type":"afterDelay","ms":1},
                    "actions":native_actions(self.ids,branch,key), "transition":{"type":"instant"},
                    "duration_ms":0,"easing":"linear"}]
        for label, start in TABS.items():
            self.page["flows"].append(dict(start=self.ids[start],name=label,description=""))

    def add(self,parent,typ,name,x,y,w,h,fill=None,**more):
        i=len(self.nodes)+1
        self.nodes[i]=dict(id=i,parent=parent,type=typ,name=name,transform=[1,0,0,1,x,y],width=w,height=h,fills=paint(fill),**more)
        self.nodes[parent]["children"].append(i)
        return i

    def box(self,x,y,w,h,fill,r=0,parent=None,name="พื้น",typ="rectangle"):
        n=self.add(parent or self.frame,typ,name,x,y,w,h,fill)
        if r: self.nodes[n]["corners"]={"radii":[r]*4,"smoothing":0}
        return n

    def text(self,x,y,s,sz=17,c=None,b=False,w=340,parent=None,minimum=12):
        s=str(s)
        if not s: return
        sz = 13 if sz<=13 else 15 if sz<=16 else 17 if sz<=19 else 20 if sz<=21 else 22 if sz<=25 else 26 if sz<=29 else 32 if sz<=39 else 36
        while sz>13 and font(sz,b).getlength(s)>w-3: sz=max(n for n in SCALE if n<sz)
        if font(sz,b).getlength(s)>w+1:
            raise ValueError(f"{self.key}: text needs editorial shortening: {s} ({w}px)")
        n=self.add(parent or self.frame,"text",s,x,y,w,round(sz*1.65),c or self.ink,characters=s,
                   style=dict(font_family="Noto Sans Thai",font_size=sz,font_style="Bold" if b else "Regular",
                              line_height={"unit":"auto"},letter_spacing={"unit":"percent","value":0},case="original",decoration="none"))
        token=(sz,b)
        if token not in self.styles:
            self.styles[token]=dict(id=f"S:{len(self.styles)+1}",name=SCALE[sz]+("/เน้น" if b else "/ปกติ"),type="text",style=self.nodes[n]["style"])
        self.nodes[n]["styles"]={"text":self.styles[token]["id"]}
        return n

    def back(self):
        n=self.link(20,16,82,48,"ย้อนกลับ","@back")
        self.text(4,8,"‹  กลับ",17,self.sub,True,70,n)

    def link(self,x,y,w,h,label,target,fill=None,r=0):
        assert target in self.ids or target=="@back",(self.key,target)
        n=self.add(self.frame,"frame",label,x,y,w,h,fill,children=[],clip=False,
                   interactions=[{"trigger":{"type":"onClick"},"actions":click_actions(self.ids,self.key,target),"transition":{"type":"instant"},"duration_ms":0,"easing":"linear"}])
        if r: self.nodes[n]["corners"]={"radii":[r]*4,"smoothing":0}
        assert w>=48 and h>=48,(self.key,label,w,h)
        self.links[self.key].append((n,label,target,x,y,w,h))
        return n

    def art(self,p,x,y,motif,scale=1,fg=LIME,bg=DEEP):
        # All marks remain editable shapes. Each illustration uses the same two inks.
        def mark(a,b,w,h,c=fg,r=0,typ="rectangle"):
            self.box(x+a*scale,y+b*scale,w*scale,h*scale,c,r*scale,p,"ภาพประกอบ",typ)
        if motif=="wave":
            for i,hh in enumerate([10,20,34,46,28,14,38,54,32,18,8]):
                mark(i*6,30-hh/2,3,hh,fg,2)
        elif motif=="scan":
            for a,b,dx,dy in [(1,2,0,0),(55,2,9,0),(1,47,0,-9),(55,47,9,-9)]:
                mark(a,b,11,3); mark(a+dx,b+dy,3,12)
            mark(19,17,28,20,fg,4); mark(26,12,12,7,fg,1); mark(29,21,8,8,bg,0,"ellipse")
        elif motif=="medal":
            mark(15,9,40,40,fg,0,"ellipse");mark(21,15,28,28,bg,0,"ellipse")
            mark(25,19,20,20,fg,0,"ellipse");mark(22,46,8,10);mark(39,46,8,10)
        elif motif=="book":
            mark(3,8,27,40,fg,3);mark(32,8,27,40,fg,3)
            for col in [8,37]:
                for yy,ww in [(17,15),(23,17),(29,12)]: mark(col,yy,ww,2,bg)
        else:
            for off in (0,12): mark(1,17+off,64,2)
            for a in (6,31,55):
                mark(a,12,11,11,fg,0,"ellipse");mark(a+3,15,5,5,bg,0,"ellipse")
            mark(54,30,2,17);mark(50,44,10,3)

    def train(self,parent,x,y):
        def r(dx,dy,w,h,c,rad=0):self.box(x+dx,y+dy,w,h,c,rad,parent,"สถานีรถไฟ")
        for dx,dy,w,h in [(4,12,100,4),(9,17,3,66),(89,17,3,60),(0,86,115,3),(4,94,105,2)]:
            r(dx,dy,w,h,"#AFB8F6")
        r(20,31,79,42,"#F3F1E9",11);r(18,56,82,12,"#FFD785",3)
        for dx in (28,46,64,82):r(dx,39,12,12,"#333B7B",2)
        r(31,70,12,9,"#202656",4);r(77,70,12,9,"#202656",4)
        r(1,20,31,13,"#FFD785",2);r(6,24,21,2,"#715725")

    def quiz(self):
        current=self.key
        correct=current=="_quiz_right"
        selected={"_quiz_right":1,"_quiz_station":0,"_quiz_ticket":2}.get(current)
        self.back()
        self.box(112,41,170,5,RULE,2);self.box(112,41,170,5,DEEP,2)
        self.text(303,28,"1 / 1",17,SUB,True,62)
        self.text(25,108,"ชุดการเดินทาง",15,DEEP,True)
        self.text(24,153,"คำนี้หมายถึงอะไร",26,INK,True)
        self.text(21,202,"platform",54,INK,True)
        self.text(25,288,"นึกถึงจุดที่ยืนรอรถไฟ",17,SUB)
        labels=["สถานี","ชานชาลา","ตั๋ว"]
        for i,(label,to) in enumerate(zip(labels,["_quiz_station","_quiz_right","_quiz_ticket"])):
            yy=344+i*69
            bg=("#E2F2E8" if i==1 else "#FFF0E7") if selected is not None and i in {1,selected} else WHITE
            border=("#37815A" if i==1 else "#AF694C") if selected is not None and i in {1,selected} else RULE
            n=self.link(24,yy,342,56,label,to,border,12) if selected is None else self.add(self.frame,"frame",label,24,yy,342,56,border,children=[],corners={"radii":[12]*4,"smoothing":0})
            self.box(1,1,340,54,bg,11,n)
            self.text(16,14,str(i+1).zfill(2),15,SUB,True,34,n)
            self.text(59,9,label,21,INK,True,165,n)
            if selected is not None and (i==1 or i==selected):self.text(215,16,"คำตอบที่ถูก" if i==1 else "คุณเลือกข้อนี้",13,INK,True,118,n)
        if selected is not None:
            self.box(0,580,390,264,"#E3F2EA" if correct else "#FFF0E7")
            self.text(24,603,"ตอบถูกแล้ว" if correct else "ลองแยกสองคำนี้",23,INK,True)
            self.text(24,650,"platform คือ ชานชาลา",19,INK,True)
            self.text(24,686,"Wait on platform two." if correct else f"{['station','platform','ticket'][selected]} คือ {labels[selected]}",17,SUB)
            self.text(24,719,"บันทึกคำตอบแล้ว",15,SUB)
            dest="_score_right" if correct else "score_screen"
            n=self.link(24,757,342,54,"ดูผลการฝึก",dest,DEEP,12)
            self.text(114,13,"ดูผลการฝึก  ›",18,WHITE,True,178,n)
        return



    def tabs(self,tab):
        assert tab in TABS,tab
        self.box(0,775,W,69,self.paper);self.box(0,775,W,1,self.rule)
        left=12
        for name,dest in TABS.items():
            ww=85.5
            n=self.link(left,782,ww,56,name,dest)
            fg=DEEP if name==tab else self.sub
            cx=ww/2
            if name==tab:self.box(cx-21,1,42,25,MINT,12,n,"แท็บที่เปิดอยู่")
            if name=="ความก้าวหน้า":
                for j,hh in enumerate([6,10,15]):self.box(cx-8+j*6,21-hh,4,hh,fg,1,n)
            elif name=="บัญชี":
                self.box(cx-4,5,8,8,fg,4,n);self.box(cx-8,15,16,6,fg,3,n)
            elif name=="คลังคำศัพท์":
                for j,h in [(-9,14),(-3,17),(3,12)]:self.box(cx+j,21-h,4,h,fg,1,n)
                self.box(cx-11,22,22,2,fg,1,n)
            else:
                for dx in [-10,1]:self.box(cx+dx,6,9,14,fg,2,n)
                self.box(cx-2,19,4,3,fg,1,n)
            tw=font(15,name==tab).getlength(name)
            self.text(max(2,(ww-tw)/2),27,name,15,fg,name==tab,ww-4,n)
            left+=ww+8

    def render(self,family,title,eyebrow,blocks,buttons,tab):
        f=self.frame
        if feature_tasks_a.render(self) or feature_tasks_b.render(self) or feature_tasks_c.render(self) or finish_routes_a.render(self) or finish_routes_b.render(self) or camera_routes.render(self) or proposed_planner.render(self) or focused_library.render(self) or focused_learning.render(self) or focused_account.render(self):return
        if self.key in {"quiz_screen","_quiz_right","_quiz_ticket","_quiz_station"}:return self.quiz()
        if self.key in ("smart_audio_playlist_screen","_playlist_play","_playlist_next","_playlist_last"):
            return self.playlist(title,buttons)
        if not tab:
            self.back()
        else:
            self.text(24,18,"LexiQuest",17,self.ink,True,120)
        self.text(24,71,title,32,self.ink,True,342)
        self.text(24,133,eyebrow,15,self.sub,False,342)
        heights={"hero":136,"quote":98,"row":65,"choice":57,"field":80,"note":62,"meter":50,"tiles":75,"stat":105,"lines":96,"art":107}
        y=175
        end=759 if tab else 827
        btnstart=end-56*len(buttons)
        def button(top,i,label,dest):
            n=self.link(24,top,342,48,label,dest,DEEP if i==0 else None,6)
            self.text(15,9,label,18,WHITE if i==0 else self.ink,True,290,n)
            self.text(311,7,"›",22,WHITE if i==0 else self.ink,True,22,n)
        for kind,*a in blocks:
            h=heights[kind]
            if kind=="hero" and family in ("reader","practice","result"):
                self.text(25,y+3,a[0],15,DEEP,True)
                self.text(22,y+33,a[1],35,self.ink,True,344)
                self.text(25,y+94,a[2],16,self.sub,False,341)
            elif kind=="hero":
                panel=self.add(f,"frame",a[0] or a[1],24,y,342,122,DEEP,children=[],clip=True)
                self.text(17,10,a[0],14,LIME,True,245,panel)
                room=220 if len(a[1])<16 else 309
                self.text(15,33,a[1],34,WHITE,True,room,panel,minimum=18)
                self.text(17,86,a[2],16,"#E8F2E9",False,309,panel)
                if room==220:
                    motif={"audio":"wave","reader":"book","profile":"medal","list":"book","scan":"scan","form":"book"}.get(family,"route")
                    self.art(panel,252,27,motif,.95)
            elif kind=="art":
                panel=self.add(f,"frame",a[1],24,y,342,94,DEEP,children=[],clip=True)
                self.art(panel,17,15,a[0],1.1)
                self.text(103,32,a[1],19,WHITE,True,222,panel)
            elif kind in ("lines","quote"):
                tint=("#314C42" if self.dark else MINT) if kind=="quote" else self.paper
                self.box(24,y,342,h-8,tint)
                self.box(24,y,3,h-8,RUST if kind=="quote" else self.rule)
                self.text(39,y+5,a[0],13,self.sub,True,312)
                self.text(39,y+27,a[1],19,self.ink,True,313)
                self.text(39,y+56,a[2],16,self.sub,False,313)
            elif kind=="row":
                label,detail,dest=a
                n=self.link(24,y,342,57,label,dest) if dest else self.add(f,"frame",label,24,y,342,57,None,children=[])
                self.text(0,2,label,18,self.ink,True,304,n)
                self.text(0,30,detail,14,self.sub,False,308,n)
                if dest:self.text(321,10,"›",22,self.sub,False,20,n)
                self.box(0,56,342,1,self.rule,parent=n)
            elif kind=="choice":
                label,dest=a
                n=self.link(24,y,342,49,label,dest,RULE,10)
                self.box(1,1,340,47,WHITE,9,n)
                self.box(13,17,14,14,DEEP,7,n);self.box(16,20,8,8,WHITE,4,n)
                self.text(38,9,label,18,INK,False,291,n)
            elif kind=="field":
                self.text(24,y,a[0],14,self.sub,True,340)
                self.box(24,y+24,342,46,"#F0F1F9",6)
                self.text(36,y+32,a[1],17,INK,False,314)
                self.box(24,y+69,342,1,"#7D839D")
            elif kind=="note":
                self.box(24,y+1,3,46,"#9DAD8E")
                self.text(37,y,a[0],15,self.ink,True,326)
                self.text(37,y+25,a[1],14,self.sub,False,326)
            elif kind=="stat":
                self.text(24,y-2,a[0],36,self.ink,True,140)
                self.text(168,y+13,a[1],17,self.ink,True,195)
                self.box(24,y+56,342,1,self.rule)
                self.text(24,y+65,a[2],15,self.sub,False,340)
            elif kind=="meter":
                self.text(24,y,a[0],15,self.sub,True,342)
                self.box(24,y+31,342,5,self.rule,2)
                if a[1]>0:self.box(24,y+31,342*min(a[1],1),5,DEEP,2)
            elif kind=="tiles":
                words,dest=a
                n=self.link(24,y,342,56,"เรียงคำ: "+" ".join(words),dest)
                gap=5
                weights=[max(23,font(17,True).getlength(w)+14) for w in words]
                unit=(342-gap*(len(words)-1))/sum(weights);left=0
                for word,wt in zip(words,weights):
                    ww=wt*unit
                    self.box(left,0,ww,48,MINT,4,n)
                    self.text(left+4,9,word,18,INK,True,ww-6,n)
                    left+=ww+gap
            y+=h
        assert y-6<=btnstart-8,(self.key,"blocks touch buttons",y,btnstart)
        # Keep actions close to their evidence; the tab bar alone is pinned to the viewport.
        btnstart=min(btnstart,y+18)
        for i,(label,dest) in enumerate(buttons):
            button(btnstart+56*i,i,label,dest)
        if tab:self.tabs(tab)

    def playlist(self,title,buttons):
        i={"smart_audio_playlist_screen":0,"_playlist_play":0,"_playlist_next":1,"_playlist_last":2}[self.key]
        words=[("station","สถานี"),("platform","ชานชาลา"),("ticket","ตั๋ว")]
        self.back()
        self.text(24,83,title,30,INK,True);self.text(24,135,"ชุดการเดินทาง  ·  3 คำ",16,SUB)
        p=self.add(self.frame,"frame","เครื่องเล่นชุดคำ",24,195,342,230,"#263451",children=[],clip=True,corners={"radii":[14]*4,"smoothing":0})
        self.text(18,16,"ตัวอย่างการฟัง",14,"#D8DFF3",True,250,p)
        self.text(17,50,words[i][0],37,WHITE,True,270,p)
        self.text(19,113,words[i][1],19,WHITE,False,240,p)
        for j in range(37):
            hh=([9,13,21,34,43,34,17,8,21,34,19,10][(j+i*3)%12])
            self.box(20+j*8.2,183-hh/2,3.5,hh,"#FFDC91" if j<=(i+1)*12 else "#647595",2,p,"คลื่นเสียงตัวอย่าง")
        self.text(24,454,"ลำดับคำในชุด",19,INK,True)
        nxt={0:"_playlist_next",1:"_playlist_last"}
        for j,(word,meaning) in enumerate(words):
            y=502+j*57
            active=j==i
            dest=nxt.get(i) if self.key in ("_playlist_play","_playlist_next") and j==i+1 else None
            n=self.link(24,y,342,52,word,dest) if dest else self.add(self.frame,"frame",word,24,y,342,52,None,children=[])
            self.text(0,7,f"0{j+1}",15,DEEP if active else SUB,active,36,n)
            self.text(48,4,word,20,INK,active,149,n);self.text(198,8,meaning,15,SUB,False,99,n)
            if dest:self.text(318,2,"›",20,DEEP,True,22,n)
            self.box(0,50,342,1,RULE,parent=n)
        for j,(label,dest) in enumerate(buttons):
            n=self.link(24,698+j*59,342,49,label,dest,DEEP if j==0 else MINT,10)
            self.text(18,10,label,17,WHITE if j==0 else DEEP,True,290,n)
            self.text(313,8,"›",20,WHITE if j==0 else DEEP,True,20,n)

    def document(self):
        return dict(format="figcraft",version=1,name="LexiQuest · สมุดคำศัพท์",current_page=1,pages=[1],
                    next_id=max(self.nodes)+1,nodes=self.nodes,styles=list(self.styles.values()),comments=[],document_colors=[],
                    variables={"collections":[{"id":"learner-state","name":"สถานะในรอบนี้","modes":[{"id":"default","name":"ค่าเริ่มต้น"}]}],
                               "variables":[{"id":key,"name":label,"collection":"learner-state",
                                             "description":"","resolvedType":"boolean","values":{"default":{"type":"boolean","value":False}}}
                                            for key,(label,_) in VARIABLES.items()]},imageIndex=[])


def validate(design, doc):
    nodes = doc["nodes"]
    assert doc["variables"]==design.document()["variables"]
    styles={s["id"]:s["style"] for s in doc["styles"] if s["type"]=="text"}
    assert styles and all(n["styles"]["text"] in styles and styles[n["styles"]["text"]]["font_size"]==n["style"]["font_size"] for n in nodes.values() if n["type"]=="text")
    assert {k for k in design.ids if not k.startswith("_")} == {p.stem for p in (ROOT/"lib/screens").glob("*.dart")}
    page=nodes["1"]
    assert set(page["children"])==set(design.ids.values())
    assert {f["start"] for f in page["flows"]}=={design.ids[k] for k in TABS.values()}
    for key,links in design.links.items():
        for i,(n,label,target,x,y,w,h) in enumerate(links):
            layer=nodes[str(n)]
            assert layer["parent"]==design.ids[key] and layer["name"]==label
            assert layer["interactions"][0]["actions"]==click_actions(design.ids,key,target)
            assert layer["interactions"][0]["trigger"]["type"]=="onClick"
            assert x>=0 and y>=0 and x+w<=W and y+h<=H
            for _,label2,_,xx,yy,ww,hh in links[:i]:
                assert min(x+w,xx+ww)+8<=max(x,xx) or min(y+h,yy+hh)+8<=max(y,yy),(key,label,label2)
    seen=set()
    queue=[TABS["ฝึกภาษา"]]
    while queue:
        k=queue.pop()
        if k in seen:continue
        seen.add(k)
        for _,_,target,*_ in design.links[k]:
            queue.extend(t for t,_ in destinations(route_branch(k,target)) if t!="@back")
    assert seen==set(design.ids),set(design.ids)-seen
    return sum(map(len,design.links.values()))


def offline(design, native, tmp):
    # Export actual FigCraft frames, preserving the native renderer's Thai text and art.
    renders=tmp/"frames"
    renders.mkdir()
    commands("export",native,"--format","webp","-o",renders)
    contents=[]
    for key,fid in design.ids.items():
        title=design.screens[key][1]
        label=html.escape(title,quote=True)
        imgfile=next(renders.glob(f"LQ{fid:03d}*.webp"))
        picture=base64.b64encode(imgfile.read_bytes()).decode()
        contents.append(f'<section id="{key}" aria-label="{label}" hidden><img alt="{label}" src="data:image/webp;base64,{picture}">')
        def text_layers(node):
            if node["type"]=="text":
                yield node["characters"]
            for child in node.get("children",[]):
                yield from text_layers(design.nodes[child])
        contents.append('<span class="sr">'+html.escape(" · ".join(text_layers(design.nodes[fid])))+'</span>')
        for _,name,target,x,y,w,h in design.links[key]:
            state=""
            if flag := COMPLETIONS.get((key,target)):
                state=f' data-completes="{flag}"'
            branch=route_branch(key,target)
            if not isinstance(branch,str):
                state+=f' data-branch="{html.escape(json.dumps(branch),quote=True)}"'
            contents.append(f'<a href="#{target}"{state} aria-label="{html.escape(name,quote=True)}" style="left:{x/W*100:.4f}%;top:{y/H*100:.4f}%;width:{w/W*100:.4f}%;height:{h/H*100:.4f}%"></a>')
        contents.append('</section>')
    navigation = (f"const homeStates={json.dumps(learn_home.STATES)}, homeBranch={json.dumps(HOME_BRANCH)}, "
                  f"jobsBranch={json.dumps(JOBS_BRANCH)}, assignment={json.dumps(ASSIGNED)}, remembered={json.dumps(REMEMBERED)};")
    page='''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LexiQuest · ลองใช้งาน</title><style>
*{box-sizing:border-box}body{margin:0;background:#dce3dd;min-height:100dvh;display:grid;place-items:center}main{width:min(100%,390px);background:#fbfaf6;position:relative}
section{position:relative;aspect-ratio:390/844}img{width:100%;height:100%;display:block}a{position:absolute;border-radius:5px}a:focus-visible{outline:3px solid #c3651f;outline-offset:-3px}a:hover{background:#2b57380c}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
</style><main>'''+''.join(contents)+'''</main><script>'''+navigation+'''
const home='choose_mode_screen', flags=Object.create(null);
let current='',depth=0;
function resolve(branch){
  if(typeof branch==='string')return branch;
  const [flag,yes,no]=branch;
  return resolve(flags[flag]?yes:no);
}
function show(request){
  let key=request||home;
  if(key in homeStates)key=resolve(homeBranch);
  else if(key==='_today_jobs')key=resolve(jobsBranch);
  const el=document.getElementById(key)||document.getElementById(resolve(homeBranch));
  if(request&&el.id!==request)history.replaceState({depth},'', '#'+el.id);
  document.querySelector('section:not([hidden])')?.setAttribute('hidden','');
  el.hidden=false;current=el.id;document.title=el.getAttribute('aria-label')+' · LexiQuest';window.scrollTo(0,0);
}
document.addEventListener('click',e=>{
  const a=e.target.closest('a');if(!a)return;
  e.preventDefault();
  if(a.dataset.completes)flags[a.dataset.completes]=true;
  let key=a.dataset.branch?resolve(JSON.parse(a.dataset.branch)):a.hash.slice(1);
  if(key==='@back'){if(depth){history.back();return}key=resolve(homeBranch)}
  if(key===current)return;
  history.pushState({depth:++depth},'', '#'+key);show(key);
});
addEventListener('popstate',e=>{depth=e.state?.depth||0;show(location.hash.slice(1))});
const start=location.hash.slice(1);
if(start in homeStates)[flags[assignment],flags[remembered]]=homeStates[start];
if(start==='_today_jobs_done')flags[assignment]=true;
if(start==='_card_remembered')flags[remembered]=true;
show(start);
</script></html>'''
    (OUT/"ลองใช้งาน.html").write_text(page,encoding="utf-8")
    from PIL import Image
    for name,keys in [
        ("practice-preview",["choose_mode_screen","quiz_screen","_quiz_station","score_screen"]),
        ("library-preview",["categories_page","_word","ai_tutor_screen","_tutor_reply"]),
        ("tools-preview",["object_scanner_screen","smart_audio_playlist_screen","mastery_dashboard_screen","profile_settings_screen"]),
        ("camera-review",["object_scanner_screen","_scan_denied","_scan_result","_scan_recall"]),
        ("import-task",["_import_json_error","_import_deck","_import_card_1","_import_deck_done"]),
    ]:
        cover=Image.new("RGB",(4*314+5*18,712),"#E1E4EB")
        for i,k in enumerate(keys):
            with Image.open(next(renders.glob(f"LQ{design.ids[k]:03d}*.webp"))) as im:
                assert im.size==(W,H)
                cover.paste(im.convert("RGB").resize((314,680),Image.Resampling.LANCZOS),(18+i*332,16))
        cover.save(OUT/(name+".png"),optimize=True)


def build_design():
    from learn_frames import SCREENS as learn
    from library_frames import SCREENS as library
    from account_frames import SCREENS as account
    screens=learn|library|account
    assert len(screens)==len(learn)+len(library)+len(account)
    for scope in (exam_routes,camera_routes,pack_routes,proposed_planner,finish_routes_a,finish_routes_b,
                  screen_review,feature_tasks_a,feature_tasks_b,feature_tasks_c,focused_library):scope.install(screens)
    design=Design(screens)
    for key,fid in design.ids.items():
        design.nodes[fid]["name"]=f"LQ{fid:03d} · {screens[key][1]}"
        design.nodes[fid]["description"]=key if key.startswith("_") else "lib/screens/"+key+".dart"
    return design


def main():
    design=build_design()
    with tempfile.TemporaryDirectory(prefix="lq-figcraft-") as td:
        tmp=Path(td)
        source=tmp/"prototype.json"
        source.write_text(json.dumps(design.document(),ensure_ascii=False),encoding="utf-8")
        native=tmp/"LexiQuest.figcraft"
        commands("convert",source,native)
        commands("convert",native,tmp/"roundtrip.json")
        doc=json.loads((tmp/"roundtrip.json").read_text(encoding="utf-8"))
        count=validate(design,doc)
        offline(design,native,tmp)
        whole_review.write(OUT,design,tmp/"frames")
        coverage_index.write(OUT,ROOT,design)
        task_acceptance.write(OUT,ROOT,design,finish_routes_a.CASES+finish_routes_b.CASES,
                              finish_routes_a.EXPECT|finish_routes_b.EXPECT,finish_routes_a.OWNERS|finish_routes_b.OWNERS)
        shutil.copyfile(native,OUT/native.name)
        print(f"{len(design.ids)} frames; {count} verified on-click targets; {len(doc['nodes'])} editable nodes; {len(doc['nodes']['1']['flows'])} flows")


if __name__=="__main__":
    main()
