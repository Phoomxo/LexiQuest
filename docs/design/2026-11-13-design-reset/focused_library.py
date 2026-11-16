"""Native frames for the word shelf, dictionary entry and contextual tutor."""

INK, MUTED, LINE = "#1F2441", "#525B73", "#DADEEB"
INDIGO, SOFT, GOLD, WHITE = "#3942AD", "#EBEDF9", "#FFE39B", "#FFFFFF"


def back(d, destination):
    d.back()


def action(d, x, y, w, label, to, fill, ink):
    n = d.link(x, y, w, 48, label, to, fill, 9)
    d.text(14, 10, label, 17, ink, True, w - 31, n)


def line_link(d, y, title, detail, to):
    n = d.link(24, y, 342, 60, title, to)
    d.text(0, 2, title, 17, INK, True, 302, n)
    d.text(0, 29, detail, 14, MUTED, False, 310, n)
    d.text(317, 11, "›", 23, INDIGO, True, 21, n)
    d.box(0, 59, 342, 1, LINE, parent=n)


def collection_row(d, y, title, detail, target):
    row = d.link(24, y, 342, 98, "เปิดชุด" + title, target)
    d.box(0, 8, 66, 80, SOFT, 5, row, "ปกชุด" + title)
    if target == "vocab_list_screen":
        # A train seen head-on, drawn on the cover.
        d.box(14, 20, 38, 43, INDIGO, 8, row, "ตัวรถไฟ")
        d.box(19, 26, 28, 15, SOFT, 3, row, "กระจกหน้า")
        d.box(32, 26, 2, 15, INDIGO, parent=row, name="ขอบกระจก")
        for x in (20, 41):
            d.box(x, 49, 5, 5, SOFT, parent=row, name="ไฟหน้า", typ="ellipse")
        for x in (21, 41):
            d.box(x, 62, 5, 7, INDIGO, 2, row, "ล้อ")
        d.box(11, 70, 44, 2, INDIGO, parent=row, name="ราง")
    else:
        # A saucepan signifies the collection even when it has no saved words.
        d.box(11, 45, 45, 4, INDIGO, 2, row, "หูหม้อ")
        d.box(16, 40, 35, 22, INDIGO, 7, row, "หม้อ")
        d.box(16, 40, 35, 6, INDIGO, parent=row, name="ขอบหม้อ")
        d.box(14, 35, 39, 3, INDIGO, 2, row, "ฝาหม้อ")
        d.box(29, 29, 10, 4, INDIGO, 2, row, "จุกฝาหม้อ")
    d.text(84, 13, title, 22, INK, True, 220, row)
    d.text(84, 53, detail, 16, MUTED, False, 225, row)
    d.text(325, 27, "›", 22, MUTED, False, 16, row)


def shelf(d):
    d.text(24, 52, "คลังคำศัพท์", 32, INK, True, 220)
    add = d.link(270, 52, 96, 48, "เพิ่มคำ", "_add_to_library", INDIGO, 9)
    d.box(14, 23, 12, 2, WHITE, 1, add, "เครื่องหมายบวก")
    d.box(19, 18, 2, 12, WHITE, 1, add, "เครื่องหมายบวก")
    d.text(34, 10, "เพิ่มคำ", 17, WHITE, True, 58, add)

    search = d.link(24, 135, 342, 58, "ค้นหาคำในคลัง", "_search_library", LINE, 10)
    d.box(1, 1, 340, 56, WHITE, 9, search, "ช่องค้นหา")
    d.box(17, 19, 17, 17, MUTED, 9, search, "แว่นขยาย")
    d.box(19, 21, 13, 13, WHITE, 7, search, "กระจก")
    for i in range(4):
        d.box(31 + i, 33 + i, 3, 3, MUTED, 1, search, "ด้ามแว่นขยาย")
    d.text(49, 14, "ค้นหาคำในคลัง", 17, MUTED, False, 275, search)

    d.text(24, 245, "ชุดคำของฉัน", 22, INK, True)
    collection_row(d, 301, "การเดินทาง", "station · platform · ticket", "vocab_list_screen")
    d.box(108, 404, 258, 1, LINE, name="เส้นคั่นชุดคำ")
    collection_row(d, 412, "ของใช้ในครัว", "รวมชื่ออุปกรณ์ทำอาหาร", "_kitchen_empty")
    d.box(24, 550, 342, 1, LINE, name="เส้นคั่นส่วนคลังคำศัพท์")

    for y, label, target in (
        (567, "เลือกชุดคำศัพท์", "_packs"),
        (635, "ทบทวนคำศัพท์", "_review_desk"),
    ):
        row = d.link(24, y, 342, 52, label, target)
        d.text(0, 10, label, 17, MUTED, False, 300, row)
        d.text(325, 6, "›", 22, MUTED, False, 16, row)
    d.tabs("คลังคำศัพท์")


def add_to_library(d):
    d.text(24, 52, "เพิ่มคำศัพท์", 32, INK, True, 225)
    cancel = d.link(284, 52, 82, 48, "ยกเลิก", "categories_page")
    d.text(18, 10, "ยกเลิก", 17, INDIGO, True, 64, cancel)
    for y, title, detail, target in (
        (151, "พิมพ์คำศัพท์", "ใส่คำภาษาอังกฤษและคำแปลด้วยตัวเอง", "add_vocab_screen"),
        (271, "ถ่ายภาพสิ่งของ", "ใช้กล้องหาคำศัพท์จากสิ่งที่เห็น", "object_scanner_screen"),
        (391, "นำเข้าจากไฟล์", "ตรวจคำศัพท์ในไฟล์ก่อนเก็บเข้าคลัง", "wordbook_import_screen"),
    ):
        row = d.link(24, y, 342, 104, title, target)
        d.text(0, 11, title, 22, INK, True, 297, row)
        d.text(0, 52, detail, 16, MUTED, False, 303, row)
        d.text(325, 27, "›", 22, MUTED, False, 16, row)
        d.box(0, 103, 342, 1, LINE, parent=row, name="เส้นคั่นวิธีเพิ่มคำ")


def install(s):
    family, _, eyebrow, blocks, buttons, _ = s["categories_page"]
    s["categories_page"] = (family, "คลังคำศัพท์", eyebrow, blocks, buttons, "คลังคำศัพท์")
    s["_add_to_library"] = ("list", "เพิ่มคำศัพท์", "", [], [], None)


def word(d):
    back(d, "ย้อนกลับ")
    d.text(24, 93, "การเดินทาง", 16, INDIGO, True)
    action(d,219,71,147,"จัดการคำนี้","_word_tools",SOFT,INDIGO)
    d.text(22, 127, "station", 59, INK, True, 340)
    d.text(25, 223, "/ˈsteɪʃən/    ·    คำนาม", 18, MUTED)
    d.box(24, 280, 342, 2, INK)
    d.text(24, 306, "01", 15, INDIGO, True, 41)
    d.text(77, 293, "สถานี", 32, INK, True, 282)
    d.text(77, 352, "เช่น สถานีรถไฟ หรือสถานีขนส่ง", 16, MUTED, w=280)
    d.box(24, 426, 3, 84, "#D4AB56", 1)
    d.text(39, 424, "Meet me at the station.", 23, INK, True, 317)
    d.text(39, 473, "มาเจอกันที่สถานีนะ", 17, MUTED, w=315)
    line_link(d, 549, "ฟังและฝึกพูด", "ฝึกเสียงของคำ แล้วลองพูดตาม", "phonetic_explorer_screen")
    line_link(d, 620, "ถามผู้ช่วยเรื่องคำนี้", "station กับ platform ต่างกันยังไง", "ai_tutor_screen")
    if "_station_details" in d.ids:
        action(d,24,693,342,"ดูระดับคำและคำใกล้เคียง","_station_details",SOFT,INDIGO)
    action(d, 24, 755, 342, "ฝึกฟังแล้วเขียน", "dictation_quiz_screen", INDIGO, WHITE)


def tutor(d, reply):
    back(d, "ย้อนกลับ")
    d.text(24, 76, "ผู้ช่วยภาษาอังกฤษ", 28, INK, True)
    context = d.link(24, 141, 342, 54, "ดูคำว่า station", "_word", SOFT, 9)
    d.text(14, 13, "คำที่กำลังฝึก", 14, MUTED, False, 110, context)
    d.text(133, 9, "station", 19, INDIGO, True, 145, context)
    d.text(314, 11, "›", 22, INDIGO, True, 20, context)
    if not reply:
        d.text(24, 237, "ประโยคที่เลือกไว้", 15, MUTED, True)
        d.box(24, 281, 3, 83, "#D3A548", 1)
        d.text(40, 277, "Meet me at the station.", 22, INK, True, 325)
        d.text(40, 324, "มาเจอกันที่สถานีนะ", 17, MUTED)
        d.box(0, 433, 390, 411, WHITE)
        d.box(0, 433, 390, 1, LINE)
        d.text(24, 461, "คำถามของฉัน", 20, INK, True)
        d.box(24, 513, 342, 98, "#F3F4FA", 12)
        d.text(40, 534, "station กับ platform ต่างกันยังไง", 18, INK, False, 312)
        d.text(24, 645, "เมื่อกดส่ง ผู้ช่วยจะได้รับคำศัพท์", 15, MUTED)
        d.text(24, 672, "ประโยคที่เลือกไว้ และคำถามนี้", 15, MUTED)
        action(d, 24, 754, 342, "ส่งคำถามตัวอย่าง", "_tutor_reply", INDIGO, WHITE)
        return
    d.text(277, 218, "คำถามของฉัน", 14, MUTED, True, 90)
    d.box(78, 251, 288, 62, SOFT, 13)
    d.text(94, 266, "station กับ platform ต่างกันยังไง", 17, INK, False, 259)
    d.text(24, 348, "คำตอบตัวอย่างจากผู้ช่วย", 15, INDIGO, True)
    d.text(24, 389, "station", 26, INK, True)
    d.text(25, 434, "หมายถึงสถานีทั้งแห่ง", 17, INK)
    d.text(25, 468, "Meet me at the station.", 16, MUTED)
    d.box(24, 518, 342, 1, LINE)
    d.text(24, 542, "platform", 26, INK, True)
    d.text(25, 587, "หมายถึงชานชาลาที่รอขึ้นรถไฟ", 17, INK)
    d.text(25, 621, "Meet me on the platform.", 16, MUTED)
    action(d, 24, 754, 342, "เปิดคำว่า platform", "_platform", INDIGO, WHITE)


def render(d):
    if d.key == "categories_page":
        shelf(d)
    elif d.key == "_add_to_library":
        add_to_library(d)
    elif d.key == "_word":
        word(d)
    elif d.key in {"ai_tutor_screen", "_tutor_reply"}:
        tutor(d, d.key == "_tutor_reply")
    else:
        return False
    return True
