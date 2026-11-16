"""Native compositions for the result, seven-day progress, and reading views."""

INK, SUB, INDIGO = "#1F2441", "#525B73", "#3942AD"
PAPER, WHITE, RULE = "#FBFBFE", "#FFFFFF", "#DADEEB"
LAVENDER, AMBER = "#EBEDF9", "#FFE39B"


def back(d):
    d.back()


def action(d, y, label, dest, primary=True):
    target = d.link(24, y, 342, 54, label, dest, INDIGO if primary else PAPER, 12)
    fg = WHITE if primary else INDIGO
    d.text(16, 12, label, 18, fg, True, 280, target)
    d.text(310, 8, "›", 23, fg, True, 24, target)


def row(d, y, label, detail, dest):
    target = d.link(24, y, 342, 66, label, dest)
    d.text(0, 2, label, 18, INK, True, 295, target)
    d.text(0, 34, detail, 14, SUB, False, 306, target)
    d.text(320, 13, "›", 22, INDIGO, True, 20, target)
    d.box(0, 65, 342, 1, RULE, parent=target)


def result(d, correct):
    back(d)
    d.text(212, 29, "เลือกความหมาย · 1 ข้อ", 14, SUB, False, 155)
    d.text(24, 97, "ผลการฝึกครั้งนี้", 33, INK, True)
    d.text(25, 150, "ชุดคำศัพท์การเดินทาง", 16, SUB)

    tint, accent = ("#E7F3EB", "#246646") if correct else ("#FFF1DA", "#884313")
    d.box(24, 207, 342, 146, tint, 16, name="สรุปผลรอบนี้")
    d.text(42, 221, "ข้อที่ตอบถูก", 15, accent, True, 225)
    d.text(39, 249, "1 / 1" if correct else "0 / 1", 48, INK, True, 175)
    d.text(43, 318, "เลือกคำแปลได้ถูกต้อง" if correct else "ฝึกคำเดิมได้อีกครั้ง", 15, accent, True, 280)
    d.text(25, 392, "คำที่ตอบได้" if correct else "คำที่ควรกลับมาฝึก", 17, SUB, True)
    d.text(22, 425, "platform", 42, INK, True, 220)
    d.text(239, 446, "ชานชาลา", 22, INK, True, 124)
    d.box(24, 505, 342, 1, RULE)
    d.text(25, 525, "Meet me on the platform.", 19, INK, False)
    d.text(25, 560, "มาเจอกันที่ชานชาลา", 16, SUB)
    if not correct:
        row(d, 607, "ดูคำที่ยังสับสน", "เทียบความหมายของ station กับ platform", "weakness_clinic_screen")
    action(d, 693, "ลองเติมคำในประโยค" if correct else "ฝึกคำนี้อีกครั้ง", "fill_in_the_blanks_screen")
    action(d, 756, "กลับหน้าฝึกภาษา", "choose_mode_screen", False)


def progress(d):
    d.text(24, 52, "ความก้าวหน้า", 36, INK, True)
    d.text(25, 107, "7 วันที่ผ่านมา", 16, SUB)
    d.box(24, 145, 342, 130, LAVENDER, 12, name="สรุปการเลือกความหมาย")
    d.text(42, 153, "เลือกความหมาย", 16, INDIGO, True)
    d.text(39, 179, "8 / 12", 45, INK, True, 166)
    d.text(210, 185, "ข้อที่ตอบถูก", 20, INK, True, 136)
    d.text(211, 224, "ฝึกทั้งหมด 3 รอบ", 15, SUB, False, 138)
    d.text(25, 303, "ผลแต่ละรอบ", 20, INK, True)
    for i, (label, right, total) in enumerate([("3 วันก่อน", 3, 5), ("เมื่อวาน", 5, 6), ("วันนี้", 0, 1)]):
        y = 355 + 39 * i
        d.text(25, y, label, 15, SUB, False, 80)
        d.box(119, y+9, 164, 8, RULE, 4)
        if right:
            d.box(119, y+9, 164*right/total, 8, INDIGO, 4)
        d.text(305, y-2, f"{right} / {total}", 17, INK, True, 60)
    d.box(24, 475, 342, 1, RULE)
    row(d, 495, "คำที่ยังสับสน", "platform · ลองฝึกคำที่พลาดครั้งล่าสุด", "weakness_clinic_screen")
    row(d, 571, "ประวัติการฝึก", "ย้อนดูคำตอบของแต่ละรอบ", "_history")
    row(d, 645, "ของสะสม", "ตราที่ได้รับและของตกแต่ง", "achievements_screen")
    action(d,720,"วางแผนการฝึก","_plan_studio",False)
    d.tabs("ความก้าวหน้า")


def reading(d,term="_article_term",recall="associative_reading_session_screen"):
    back(d)
    d.text(235, 30, "อ่านประมาณ 1 นาที", 14, SUB, False, 132)
    d.text(25, 95, "บทอ่าน A2 · การเดินทาง", 15, INDIGO, True)
    d.text(22, 127, "นัดกันที่สถานี", 34, INK, True)
    panel = d.add(d.frame, "frame", "สถานีและป้ายชานชาลา", 24, 206, 342, 134,
                  "#343C91", children=[], clip=True, corners={"radii": [14]*4, "smoothing": 0})
    d.train(panel, 13, 13)
    d.box(182, 18, 3, 78, "#AFB8F6", 1, panel)
    d.box(296, 18, 3, 78, "#AFB8F6", 1, panel)
    d.box(161, 39, 160, 54, AMBER, 5, panel, "ป้ายชานชาลา")
    d.text(171, 51, "PLATFORM  2", 19, INK, True, 144, panel)
    d.text(25, 378, "Mina arrives at the station.", 22, INK, False)
    d.text(25, 419, "Her friend is on platform two.", 22, INK, False)
    d.text(25, 485, "She follows the signs.", 22, INK, False)
    d.text(25, 526, "They meet on the platform.", 22, INK, False)
    term_button=d.link(24,567,342,48,"ดูความหมายของ platform",term,LAVENDER,8)
    d.text(14,10,"ดูความหมายของ platform",17,INDIGO,True,303,term_button)
    d.text(25, 623, "ทั้งสองคนมาเจอกันที่ไหน", 19, INK, True)
    d.text(25, 663, "ลองนึกคำจากเรื่อง แล้วใช้แต่งประโยค", 16, SUB)
    action(d, 736, "ฝึกคำจากเรื่องนี้", recall)


def render(d):
    if d.key in ("score_screen", "_score_right"):
        result(d, d.key == "_score_right")
    elif d.key == "mastery_dashboard_screen":
        progress(d)
    elif d.key == "cefr_article_reader_screen":
        reading(d)
    else:
        return False
    return True
