"""Four account views with editable identity, collection and shop artwork."""

INK = "#1F2441"
SUB = "#525B73"
INDIGO = "#3942AD"
WHITE = "#FFFFFF"
RULE = "#DADEEB"
LILAC = "#EBEDF9"
GOLD = "#F6C05A"
CREAM = "#FFF0D5"
TEAL = "#216E70"
MIST = "#E2F2EE"


def pill(d, x, y, w, label, dest, primary=False):
    p = d.link(x, y, w, 48, label, dest, INDIGO if primary else LILAC, 12)
    d.text(14, 10, label, 16, WHITE if primary else INDIGO, True, w-48, p)
    d.text(w-27, 7, "›", 21, WHITE if primary else INDIGO, True, 18, p)


def back(d, title):
    d.back()
    d.text(24, 75, title, 32, INK, True, 342)


def icon(d, p, name, x, y, ink, paper):
    def mark(a, b, w, h, c=ink, r=1):
        d.box(x+a, y+b, w, h, c, r, p, name)
    if name == "ข้อมูล":
        mark(3, 5, 18, 15, r=3); mark(6, 8, 12, 3, paper); mark(7, 14, 6, 2, paper)
    elif name == "การแสดงผล":
        mark(4, 3, 17, 17, r=8); mark(10, 5, 9, 12, paper, 5); mark(9, 2, 9, 6, paper, 3)
    elif name == "สิทธิ์":
        mark(1, 8, 23, 14, r=3); mark(6, 4, 8, 5); mark(9, 10, 9, 9, paper, 4); mark(11, 12, 5, 5, r=2)
    elif name == "ผู้ช่วย":
        mark(2, 3, 21, 15, r=5); mark(5, 15, 5, 6); mark(7, 9, 2, 3, paper); mark(12, 9, 2, 3, paper); mark(17, 9, 2, 3, paper)
    else:
        for a in (2, 13): mark(a, 4, 9, 16, r=2)
        for a in (4, 15): mark(a, 8, 5, 2, paper)


def row(d, y, label, detail, dest, glyph, bg=LILAC, fg=INDIGO):
    p = d.link(24, y, 342, 68, label, dest)
    d.box(0, 13, 42, 42, bg, 12, p)
    icon(d, p, glyph, 9, 22, fg, bg)
    d.text(55, 5, label, 18, INK, True, 243, p)
    d.text(55, 35, detail, 14, SUB, False, 255, p)
    d.text(319, 17, "›", 22, SUB, False, 18, p); d.box(55, 67, 287, 1, RULE, parent=p)


def medal(d, p, x, y, won):
    ring, core, edge = (GOLD, "#FFE5AA", "#935B24") if won else ("#C4C8D6", "#EDF0F6", "#6B7390")
    for a in (7, 24):
        d.box(x+a, y+26, 9, 15, edge, 2, p, "ริบบิ้น")
    d.box(x+2, y, 36, 36, ring, 18, p, "เหรียญ")
    d.box(x+6, y+4, 28, 28, core, 14, p, "หน้าตรา")
    for a, h in ((12, 7), (18, 12), (24, 16)):
        d.box(x+a, y+25-h, 4, h, edge, 1, p, "ลายบนตรา")


def render(d):
    if d.key == "profile_settings_screen":
        d.text(24, 52, "บัญชี", 36, INK, True, 330)
        # The bookplate keeps the profile tied to a learner's notebook.
        p = d.add(d.frame, "frame", "บัตรเจ้าของสมุด", 24, 112, 342, 167, "#353C89", children=[], clip=True,
                  corners={"radii":[18]*4,"smoothing":0})
        d.text(19, 17, "สมุดคำศัพท์ของ", 14, "#DFE2FF", True, 175, p)
        d.text(17, 48, "นักอ่าน", 34, WHITE, True, 185, p)
        d.text(19, 119, "กำลังใช้งานบนอุปกรณ์นี้", 15, "#E5E8FF", False, 205, p)
        d.box(226, 24, 89, 110, "#7981CC", 5, p, "เงาสมุด")
        d.box(220, 20, 89, 110, "#FFE19B", 5, p, "ปกสมุด"); d.box(231, 20, 2, 110, "#B99051", 1, p)
        d.box(247, 43, 45, 37, "#FFF2CF", 4, p, "ป้ายชื่อ")
        d.art(p, 250, 48, "book", .48, "#654513", "#FFF2CF")
        d.box(278, 21, 8, 17, "#C9604B", 1, p, "ที่คั่นหน้า")
        pill(d, 24, 296, 342, "เข้าสู่ระบบหรือสร้างบัญชี", "login_screen")
        d.text(24, 389, "จัดการบัญชี", 21, INK, True, 342)
        row(d, 430, "ข้อมูลของฉัน", "สำเนาข้อมูลและความเป็นส่วนตัว", "_account_data", "ข้อมูล", MIST, TEAL)
        row(d, 507, "ตั้งค่า", "การแสดงผล กล้อง ไมค์ และผู้ช่วย", "setting_screen", "การแสดงผล")
        row(d, 584, "ของสะสม", "ความสำเร็จและของตกแต่งที่มี", "achievements_screen", "สมุด", CREAM, "#8B5822")
        d.tabs("บัญชี")
    elif d.key == "setting_screen":
        back(d, "ตั้งค่า")
        d.text(24, 168, "การใช้งานบนเครื่องนี้", 15, INDIGO, True, 342)
        row(d, 214, "การแสดงผล", "โหมดสว่าง โหมดมืด และพื้นหลัง", "appearance_settings_screen", "การแสดงผล")
        row(d, 291, "กล้องและไมโครโฟน", "เลือกสิทธิ์สำหรับเก็บคำและฝึกพูด", "device_permission_center_screen", "สิทธิ์", MIST, TEAL)
        d.text(24, 407, "บริการและข้อมูล", 15, INDIGO, True, 342)
        row(d, 450, "ผู้ช่วยฝึกภาษา", "ตั้งค่าการเชื่อมต่อและข้อมูลที่แชร์", "gemini_settings_screen", "ผู้ช่วย")
        row(d, 527, "ข้อมูลและความเป็นส่วนตัว", "สำเนาข้อมูล บัญชี และงานวิจัย", "_account_data", "ข้อมูล", MIST, TEAL)
        row(d, 605, "ข้อมูลในเครื่อง", "คิวรอส่งและเนื้อหาออฟไลน์", "_local_status", "ข้อมูล")
        row(d, 682, "การเข้าร่วมวิจัย", "ตรวจสถานะ แยกจากการเรียนปกติ", "_research_choice", "สิทธิ์")
    elif d.key == "achievements_screen":
        back(d, "ของสะสม")
        d.text(24, 162, "ความสำเร็จจากการฝึก", 20, INK, True, 340)
        for i, (label, state, detail, won) in enumerate([
            ("เรียนจบรอบแรก", "ได้รับแล้ว", "จบการฝึกครบหนึ่งรอบ", True),
            ("ตอบถูกครบทั้งรอบ", "ยังไม่ได้รับ", "ตอบถูกทุกข้อในรอบเดียว", False),
        ]):
            x = 24+i*176
            p = d.add(d.frame, "frame", label, x, 214, 166, 210, "#FFF4DA" if won else "#EFF0F6",
                      children=[], corners={"radii":[14]*4,"smoothing":0})
            d.box(13, 17, 70, 70, "#FFE4AD" if won else "#E1E4EF", 35, p)
            medal(d, p, 29, 31, won)
            d.text(13, 99, state, 13, "#79511E" if won else SUB, True, 141, p)
            d.text(13, 125, label, 18, INK, True, 141, p)
            d.text(13, 160, detail, 13, SUB, False, 141, p)
        d.text(24, 474, "แต่งตัวละครและหน้าฝึก", 20, INK, True, 342)
        row(d, 527, "ของตกแต่งของฉัน", "ดูของที่มีและเลือกชิ้นที่ใช้", "avatar_equipment_screen", "สมุด", CREAM, "#8B5822")
        pill(d, 24, 625, 342, "ไปที่ร้านของตกแต่ง", "shop_page", True)
    elif d.key == "shop_page":
        back(d, "ร้านของตกแต่ง")
        d.box(24, 153, 342, 65, CREAM, 12)
        d.box(39, 169, 33, 33, GOLD, 17); d.box(46, 176, 19, 19, "#FFDB87", 9)
        d.text(85, 170, "เหรียญที่มี", 16, "#6E4B23", True, 145)
        d.text(235, 165, "140 เหรียญ", 21, "#52380F", True, 117)
        d.text(24, 258, "เลือกดูของตกแต่ง", 20, INK, True, 342)
        for i,(label,detail,to) in enumerate([
            ("พื้นหลังสมาธิ","มีแล้ว · ดูตัวอย่างบนบัตรคำ","_wallpaper_preview"),
            ("หมวกนักออกเสียง","มีแล้ว · ดูในของตกแต่งของฉัน","_equipment_from_shop"),
        ]):
            p=d.link(24,311+i*113,342,102,label,to,WHITE,12)
            d.box(0,3,86,96,MIST if i==0 else CREAM,12,p)
            if i==0:
                for j,hh in enumerate((18,27,37,45,39,28,20)):
                    d.box(14+j*9,65-hh,4,hh,"#5C9187",2,p,"ลายพื้นหลังสมาธิ")
            else:
                d.box(22,29,40,36,INDIGO,15,p,"หมวก");d.box(17,56,58,8,"#384085",4,p,"ปีกหมวก")
                d.box(20,52,45,6,GOLD,2,p,"แถบหมวก");d.box(37,37,8,8,WHITE,4,p,"ตราหมวก")
            d.text(103,19,label,19,INK,True,202,p)
            d.text(103,55,detail,14,SUB,False,215,p)
            d.text(319,30,"›",22,INDIGO,False,19,p)
        pill(d,24,612,342,"กลับไปฝึกคำ","choose_mode_screen")
    else:
        return False
    return True
