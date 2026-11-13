"""Editable practice hub shared by the initial and assignment-complete states."""

INK = "#1F2441"
MUTED = "#525B73"
INDIGO = "#3942AD"
LINE = "#DADEEB"
SKY = "#E8EBF8"
STATES = {
    "choose_mode_screen": (False, False),
    "_today_after_assignment": (True, False),
    "_home_after_review": (False, True),
    "_home_after_both": (True, True),
}


def platform_scene(d, card):
    """A station canopy, a hanging platform number and the yellow platform edge."""
    steel = "#5B6597"
    pale = "#B7C0E0"
    gold = "#ECC266"
    def shape(x, y, w, h, color, name, radius=0):
        d.box(x, y, w, h, color, radius, card, name)

    shape(222, 34, 120, 7, pale, "หลังคาชานชาลา")
    shape(229, 41, 113, 3, steel, "คานหลังคา")
    shape(324, 44, 6, 101, pale, "เสารับหลังคา")
    for x in (251, 278):
        shape(x, 44, 2, 11, steel, "สายแขวนป้าย")
    shape(242, 55, 48, 44, INK, "ป้ายหมายเลขชานชาลา", 3)
    d.text(254, 57, "2", 26, "#FFFFFF", True, 25, card)
    shape(268, 119, 44, 4, steel, "พนักพิงม้านั่ง", 1)
    shape(265, 127, 50, 4, steel, "ที่นั่ง", 1)
    for x in (271, 306):
        shape(x, 131, 3, 11, steel, "ขาม้านั่ง")
    shape(216, 143, 126, 3, steel, "ขอบชานชาลา")
    shape(231, 149, 111, 4, gold, "เส้นเตือนริมชานชาลา")
    shape(250, 158, 92, 2, pale, "รางรถไฟ")


def render(d, assignment_done, remembered):
    d.text(24, 52, "ฝึกภาษา", 32, INK, True, 185)
    label = "งานที่ทำเสร็จ" if assignment_done else "งานที่ได้รับ"
    dest = "_today_jobs_done" if assignment_done else "_today_jobs"
    work = d.link(226, 51, 140, 48, label, dest)
    d.text(10, 8, label, 17, INDIGO, True, 109, work)
    d.text(122, 5, "›", 22, INDIGO, True, 17, work)

    heading = "ทบทวนครบแล้ว" if remembered else "ถึงเวลาทบทวน 1 คำ"
    action, target = ("ใช้คำในประโยค", "fill_in_the_blanks_screen") if remembered else ("ทบทวนคำนี้", "srs_flashcards_screen")
    d.text(24, 153, heading, 22, INK, True, 342)
    card = d.link(24, 206, 342, 201, action, target, SKY, 14)
    d.text(20, 18, "คำที่จำได้ · การเดินทาง" if remembered else "ชุดการเดินทาง", 15, MUTED, False, 184, card)
    d.text(18, 43, "platform", 36, INK, True, 194, card)
    d.text(20, 99, "ชานชาลา" if remembered else "Meet me on platform two.", 15, INK, False, 190, card)
    platform_scene(d, card)
    d.box(20, 137, 165, 48, INDIGO, 9, card, action)
    d.text(36, 146, action, 17, "#FFFFFF", True, 118, card)
    d.text(159, 142, "›", 22, "#FFFFFF", True, 17, card)

    d.text(24, 457, "ฝึกเพิ่มเติม", 22, INK, True, 342)
    for y, title, detail, to in [
        (512, "ฝึกจากชุดคำ", "เลือกชุดคำศัพท์แล้วฝึกตอบคำถาม", "select_category_for_quiz"),
        (594, "อ่านเรื่องนัดกันที่สถานี", "บทอ่านระดับ A2 · ประมาณ 1 นาที", "cefr_article_reader_screen"),
    ]:
        option = d.link(24, y, 342, 70, title, to)
        d.text(0, 2, title, 20, INK, True, 300, option)
        d.text(0, 35, detail, 15, MUTED, False, 306, option)
        d.text(324, 13, "›", 22, INDIGO, True, 16, option)
        d.box(0, 69, 342, 1, LINE, parent=option, name="เส้นแบ่งแบบฝึก")
    all_modes = d.link(24, 680, 342, 52, "ดูแบบฝึกทั้งหมด", "main_navigation_screen")
    d.text(0, 9, "ดูแบบฝึกทั้งหมด", 17, INDIGO, True, 303, all_modes)
    d.text(324, 7, "›", 22, INDIGO, True, 16, all_modes)
    d.tabs("ฝึกภาษา")
