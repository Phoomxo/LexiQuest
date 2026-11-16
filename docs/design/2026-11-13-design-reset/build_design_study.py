"""Regenerate editable SVG studies, not application screenshots or validated UI."""
from pathlib import Path
from xml.etree import ElementTree as ET
from html import escape
from base64 import b64encode

OUT = Path(__file__).resolve().parent
FONT = OUT.parents[2] / 'assets/fonts/NotoSansThai-Variable.ttf'
INK, MUTED, LINE = '#172B3A', '#526573', '#D7E0E5'
BLUE, PALE, GREEN, RED = '#174F78', '#E8F1F7', '#176348', '#A92F34'


class Board:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
                      '<title>LexiQuest — แบบศึกษาการออกแบบใหม่</title>',
                      '<desc>ข้อมูลสมมติสำหรับตรวจแบบ ยังไม่ใช่หน้าจอแอปจริง</desc>']
        font = b64encode(FONT.read_bytes()).decode('ascii')
        self.parts.append(f'<style>@font-face{{font-family:LQThai;src:url(data:font/ttf;base64,{font});font-weight:100 900}}</style>')

    def rect(self, x, y, w, h, fill, radius=0, stroke='none'):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>')

    def text(self, x, y, content, size=16, color=INK, weight=400):
        self.parts.append(f'<text x="{x}" y="{y}" font-family="LQThai, Noto Sans Thai, sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}">{escape(content)}</text>')

    def line(self, x1, y1, x2, y2, color=LINE):
        self.parts.append(f'<path d="M{x1} {y1}H{x2}" transform="translate(0 {y2-y1})" stroke="{color}"/>')

    def save(self, name):
        content = '\n'.join(self.parts + ['</svg>'])
        root = ET.fromstring(content)
        assert root.tag.endswith('svg') and len(list(root.iter())) > 100
        assert '<foreignObject' not in content and '<script' not in content
        (OUT / name).write_text(content, encoding='utf-8')


class Phone:
    def __init__(self, board, x, y, title, nav=True, warm=False):
        self.b, self.x, self.y, self.nav = board, x, y, nav
        self.accent = '#9B3B27' if warm else BLUE
        self.tint = '#F8ECE5' if warm else PALE
        board.parts.append(f'<g id="{escape(title)}" transform="translate({x} {y})">')
        board.rect(0, 0, 390, 844, '#FFFFFF', 20, LINE)
        board.text(20, 28, '9:41', 12, INK, 600)
        board.text(318, 28, '▰  ▰', 12)
        board.text(20, 76, title, 22, INK, 700)
        if nav:
            board.rect(1, 760, 388, 64, '#F6F8FA')
            labels = ['วันนี้', 'คลังคำ', 'ความก้าวหน้า', 'บัญชี']
            active = labels.index(title) if title in labels else 0
            board.rect(9 + active * 93, 775, 89, 38, self.tint, 10)
            for i, label in enumerate(labels):
                board.text(17 + i * 93, 800, label, 13, self.accent if i == active else MUTED, 700 if i == active else 400)
        board.rect(150, 832, 90, 4, INK, 2)

    def t(self, x, y, text, size=16, color=INK, weight=400):
        assert 0 <= x <= 370 and 0 <= y <= 830, (x, y, text)
        self.b.text(x, y, text, size, color, weight)

    def box(self, x, y, w, h, fill=None, r=12, stroke='none'):
        assert x >= 0 and y >= 0 and x + w <= 390 and y + h <= 832
        self.b.rect(x, y, w, h, fill or self.tint, r, stroke)

    def button(self, y, label, secondary=False):
        self.box(20, y, 350, 52, '#FFFFFF' if secondary else self.accent, 12, self.accent if secondary else 'none')
        self.t(36, y + 33, label, 17, self.accent if secondary else '#FFFFFF', 600)

    def row(self, y, title, detail, suffix='›'):
        self.t(20, y, title, 18, INK, 600)
        self.t(20, y + 25, detail, 14, MUTED)
        self.t(348, y + 10, suffix, 22, self.accent)
        self.b.line(20, y + 43, 370, y + 43)

    def close(self):
        self.b.parts.append('</g>')


def study():
    b = Board(1720, 2070)
    b.rect(0, 0, 1720, 2070, '#EDF1F4')
    b.text(38, 52, 'LexiQuest / ออกแบบจากงานที่ผู้เรียนต้องทำ', 30, INK, 700)
    b.text(38, 86, 'แบบเสนอเพื่อพิจารณา · ตัวเลขและคำศัพท์เป็นข้อมูลสมมติ · ยังไม่ใช่ผลทดสอบแอป', 17, MUTED)
    for row, warm in enumerate([False, True]):
        y = 155 + row * 960
        b.text(38, y - 23, 'ก. เรียนจากคำ แล้วนำไปใช้' if not warm else 'ข. แผนฝึกวันนี้ แล้วเลือกชุดคำ', 24, INK, 700)
        p = Phone(b, 38, y, 'วันนี้', warm=warm)
        if not warm:
            p.t(20, 118, 'กลับมาต่อจากคำที่ยังสับสน', 16, MUTED)
            p.box(20, 140, 350, 232, '#173C56')
            p.t(40, 178, 'การเดินทาง · คำที่เคยตอบผิด', 15, '#D8EAF4')
            p.t(40, 235, 'station', 44, '#FFFFFF', 600)
            p.t(40, 271, 'สถานี', 22, '#FFFFFF')
            p.t(40, 316, 'Meet me at the station.', 20, '#FFFFFF')
            p.t(40, 346, 'ใช้คำในประโยค แล้วลองตอบอีกครั้ง', 14, '#D8EAF4')
            p.button(390, 'ฝึกคำที่ยังสับสน 3 คำ')
            p.row(485, 'ถึงเวลาทบทวน 5 คำ', 'ฝึกจากชุดการเดินทางและชีวิตประจำวัน')
            p.row(575, 'เก็บคำใหม่มาเรียน', 'พิมพ์คำ นำเข้า หรือเลือกจากข้อความ')
            p.t(20, 680, 'ครั้งล่าสุด: ฝึกชุดการเดินทาง', 15, MUTED)
            p.t(20, 710, 'ดูคำที่ฝึกไว้ ›', 16, p.accent, 600)
        else:
            p.t(20, 119, 'ศุกร์ 13 พฤศจิกายน', 16, MUTED)
            p.t(20, 167, 'เริ่มจากคำที่ถึงเวลาทบทวน', 24, INK, 700)
            p.box(20, 192, 350, 151)
            p.t(38, 230, 'ทบทวน 5 คำ', 28, INK, 700)
            p.t(38, 264, 'การเดินทาง + ชีวิตประจำวัน', 17)
            p.t(38, 300, 'เลือกจากประวัติการฝึกของคุณ', 14, MUTED)
            p.button(361, 'เริ่มทบทวน')
            p.t(20, 468, 'ฝึกต่อจากครั้งก่อน', 20, INK, 700)
            p.row(514, 'การเดินทาง', 'station · platform · ticket')
            p.row(604, 'ฝึกคำที่ยังสับสน 3 คำ', 'เลือกคำที่เคยตอบผิดมาฝึกอีกครั้ง')
            p.t(20, 715, 'เลือกแบบฝึกอื่น ›', 16, p.accent, 600)
        p.close()
        p = Phone(b, 458, y, 'คลังคำ', warm=warm)
        p.box(20, 101, 350, 48, '#F0F4F6')
        p.t(36, 132, 'ค้นหาคำหรือชุดคำ', 16, MUTED)
        p.t(20, 187, 'คำทั้งหมด 24', 20, INK, 700)
        p.t(212, 187, 'เพิ่มคำ  +', 16, p.accent, 600)
        for xx, width, label in [(20, 78, 'ทั้งหมด'), (106, 153, 'ถึงเวลาทบทวน'), (267, 103, 'ตอบผิด')]:
            p.box(xx, 202, width, 48, p.accent if xx == 20 else '#FFFFFF', 10, p.accent if xx == 20 else LINE)
            p.t(xx + 10, 232, label, 14, '#FFFFFF' if xx == 20 else p.accent, 600)
        for yy, word, meaning, hint in [(281, 'station', 'สถานี', 'ฝึกอีกครั้ง'), (382, 'platform', 'ชานชาลา', 'ถึงเวลาทบทวน'), (483, 'ticket', 'ตั๋ว', 'ตอบได้ครั้งล่าสุด')]:
            p.t(20, yy, word, 27, INK, 600)
            p.t(20, yy + 29, meaning, 17)
            p.t(226, yy + 29, hint, 13, p.accent)
            p.b.line(20, yy + 51, 370, yy + 51)
        p.box(20, 583, 350, 93)
        p.t(36, 614, 'มีคำอยู่ในไฟล์หรือข้อความ?', 17, INK, 600)
        p.t(36, 646, 'นำเข้าคำ แล้วตรวจทานก่อนบันทึก ›', 15, p.accent)
        p.t(20, 721, 'ดูตามชุดคำ ›', 16, p.accent, 600)
        p.close()
        p = Phone(b, 878, y, '‹  ทบทวนคำ', nav=False, warm=warm)
        p.t(20, 115, 'ข้อ 2 จาก 5 · การเดินทาง', 15, MUTED)
        p.box(20, 137, 350, 4, '#E3E9ED', 2)
        p.box(20, 137, 140, 4, p.accent, 2)
        p.t(20, 192, 'คำนี้หมายถึงอะไร', 21, INK, 600)
        p.t(20, 253, 'station', 46, INK, 600)
        p.t(20, 292, 'ฟังการออกเสียง  ♪', 15, p.accent)
        for yy, label, correct in [(330, 'สถานี', True), (397, 'ตั๋ว', False), (464, 'การเดินทาง', False)]:
            p.box(20, yy, 350, 55, '#E3F2E9' if correct else '#FFFFFF', 12, GREEN if correct else LINE)
            p.t(38, yy + 35, ('✓  ' if correct else '') + label, 19, GREEN if correct else MUTED, 600 if correct else 400)
        p.box(20, 553, 350, 145, '#F0F7F3')
        p.t(36, 585, 'ถูกต้อง · station คือ สถานี', 17, GREEN, 700)
        p.t(36, 621, 'Meet me at the station.', 20)
        p.t(36, 656, 'เจอกันที่สถานี', 17, MUTED)
        p.button(728, 'คำถัดไป')
        p.close()
        p = Phone(b, 1298, y, 'ผลการฝึกครั้งนี้', nav=False, warm=warm)
        p.t(20, 127, 'ชุดการเดินทาง', 16, MUTED)
        p.t(20, 178, 'ตอบได้ 4 จาก 5 คำ', 29, INK, 700)
        p.t(20, 213, 'บันทึกคำตอบเรียบร้อยแล้ว', 16, MUTED)
        p.box(20, 245, 350, 123)
        p.t(38, 280, 'คำที่ควรกลับมาฝึก', 17, INK, 600)
        p.t(38, 323, 'platform', 29, INK, 600)
        p.t(218, 323, 'ชานชาลา', 16)
        p.t(20, 413, 'คำที่ตอบได้ในรอบนี้', 19, INK, 700)
        for yy, text in [(456, 'station · สถานี'), (499, 'ticket · ตั๋ว'), (542, 'arrive · มาถึง'), (585, 'depart · ออกเดินทาง')]:
            p.t(20, yy, '✓  ' + text, 18, INK)
        p.t(20, 642, 'กลับมาทบทวนอีกครั้ง เพื่อดูว่ายังจำได้', 14, MUTED)
        p.button(692, 'ฝึกคำที่ยังสับสน 1 คำ')
        p.button(756, 'กลับหน้าวันนี้', secondary=True)
        p.close()
    b.text(38, 2050, 'รูปแบบ ก ใช้คำเป็นแกนของประสบการณ์ · รูปแบบ ข ใช้งานที่ถึงกำหนดเป็นแกน · ทุกเมนูเป็นภาษาไทย', 17, MUTED)
    b.save('direction-study.svg')


def system_study():
    b = Board(2150, 1300)
    b.rect(0, 0, 2150, 1300, '#EDF1F4')
    b.text(38, 52, 'LexiQuest / ระบบเดียวกัน แต่จัดหน้าตามงาน', 30, INK, 700)
    b.text(38, 87, 'แบบเสนอ · ข้อมูลสมมติ · แสดงองค์ประกอบหลัก ยังไม่ใช่ต้นแบบโต้ตอบหรือแบบที่กรรมการรับรอง', 17, MUTED)
    p = Phone(b, 38, 130, '‹  รายละเอียดคำ', nav=False)
    p.t(20, 120, 'การเดินทาง', 15, MUTED)
    p.t(20, 184, 'station', 46, INK, 600)
    p.t(20, 225, 'คำนาม · /ˈsteɪ.ʃən/', 17, MUTED)
    p.t(20, 275, 'สถานี', 27, INK, 600)
    p.box(20, 304, 350, 130)
    p.t(38, 345, 'Meet me at the station.', 21)
    p.t(38, 382, 'เจอกันที่สถานี', 18, MUTED)
    p.t(38, 415, 'ฟังตัวอย่าง  ♪', 15, BLUE, 600)
    p.row(483, 'ประวัติการฝึก', 'ตอบผิดในรอบล่าสุด · ฝึกแล้ว 3 ครั้ง')
    p.row(575, 'จำคำนี้อย่างไรดี', 'ขอคำใบ้หรือดูตัวอย่างการใช้')
    p.button(706, 'ฝึกคำนี้')
    p.button(770, 'แก้ไขคำ', secondary=True)
    p.close()
    p = Phone(b, 458, 130, '‹  ตรวจคำก่อนบันทึก', nav=False)
    p.t(20, 120, 'เลือกคำที่ต้องการเก็บเข้าคลัง', 17)
    p.box(20, 141, 350, 78)
    p.t(36, 174, 'จากข้อความที่คุณเลือก', 16, INK, 600)
    p.t(36, 200, 'ยังไม่บันทึกจนกว่าคุณจะยืนยัน', 14, MUTED)
    p.row(267, '✓  station', 'สถานี · การเดินทาง')
    p.row(360, '✓  platform', 'ชานชาลา · การเดินทาง')
    p.row(453, '□  ticket', 'มีคำนี้ในคลังแล้ว')
    p.t(20, 555, 'เก็บในชุดคำ', 16, MUTED)
    p.box(20, 573, 350, 52, '#FFFFFF', 12, LINE)
    p.t(36, 607, 'การเดินทาง                       เปลี่ยน', 16)
    p.button(710, 'บันทึก 2 คำ')
    p.button(774, 'กลับไปแก้ข้อความ', secondary=True)
    p.close()
    p = Phone(b, 878, 130, '‹  ถามเรื่องคำนี้', nav=False)
    p.box(20, 102, 350, 91)
    p.t(36, 136, 'station · สถานี', 23, INK, 600)
    p.t(36, 168, 'Meet me at the station.', 17)
    p.t(20, 239, 'อยากเข้าใจตรงไหนเพิ่ม?', 23, INK, 700)
    p.row(291, 'อธิบายคำนี้', 'ดูความหมายและตัวอย่างเพิ่มเติม')
    p.row(385, 'ช่วยแยกคำที่สับสน', 'เช่น station กับ platform')
    p.box(20, 465, 350, 111, '#F2F5F7')
    p.t(36, 497, 'ก่อนเริ่มสนทนา', 16, INK, 600)
    p.t(36, 528, 'จะส่งคำและประโยคที่แสดงด้านบน', 15, MUTED)
    p.t(36, 554, 'ไปยังบริการผู้ช่วยที่คุณตั้งค่าไว้', 15, MUTED)
    p.t(20, 624, 'การเรียนทั่วไปยังใช้ได้เมื่อออฟไลน์', 14, MUTED)
    p.box(20, 652, 350, 57, '#FFFFFF', 12, LINE)
    p.t(36, 687, 'พิมพ์คำถามของคุณ', 17, MUTED)
    p.button(730, 'ยืนยันและส่งคำถาม')
    p.close()
    p = Phone(b, 1298, 130, 'ความก้าวหน้า')
    p.t(20, 122, 'ดูคำที่ฝึกไว้ แล้วเลือกฝึกต่อ', 17, MUTED)
    p.box(20, 147, 350, 152, '#173C56')
    p.t(38, 185, 'รอบล่าสุด · การเดินทาง', 15, '#D8EAF4')
    p.t(38, 232, 'ตอบได้ 4 จาก 5 คำ', 28, '#FFFFFF', 600)
    p.t(38, 272, 'ดูคำตอบและคำที่ควรฝึกต่อ ›', 16, '#FFFFFF')
    p.t(20, 348, 'คำที่ยังสับสน', 21, INK, 700)
    p.row(395, 'platform · ชานชาลา', 'รอบล่าสุดตอบเป็น station')
    p.button(460, 'ฝึกคำที่ยังสับสน')
    p.t(20, 558, 'ประวัติการฝึก', 20, INK, 700)
    p.row(602, 'วันนี้ · การเดินทาง', '5 คำตอบ · ดูรายละเอียด')
    p.t(20, 713, 'ดูความต่อเนื่องและของรางวัล ›', 15, BLUE)
    p.close()
    p = Phone(b, 1718, 130, 'บัญชี')
    p.box(20, 104, 350, 79)
    p.t(36, 139, 'เรียนบนเครื่องนี้', 21, INK, 600)
    p.t(36, 167, 'เข้าสู่ระบบเพื่อเชื่อมข้อมูล ›', 15, BLUE)
    for yy, title, detail in [(233, 'รูปแบบการแสดงผล', 'ขนาดตัวอักษร ธีม และภาพพื้นหลัง'), (325, 'เสียงและการเข้าถึง', 'ตรวจสิทธิ์ไมโครโฟนและกล้อง'), (417, 'ข้อมูลของคุณ', 'สำรอง ส่งออก และลบข้อมูล'), (509, 'ตั้งค่าผู้ช่วย', 'การเชื่อมต่อและการส่งข้อมูล'), (601, 'เกี่ยวกับการวิจัย', 'การเข้าร่วมเป็นทางเลือก'), (693, 'ช่วยเหลือ', 'การใช้งานและการแก้ปัญหา')]:
        p.row(yy, title, detail)
    p.close()
    b.text(38, 1030, 'กติกาของระบบ', 25, INK, 700)
    rules = ['ทุกหน้าเริ่มจากงานหลักหนึ่งอย่าง ใช้แถวรายการกับข้อมูล ไม่ใส่ทุกอย่างในการ์ด',
             'ภาษาไทยสำหรับเมนูและคำสั่ง คำอังกฤษใช้เฉพาะเนื้อหาที่กำลังเรียน',
             'ระยะพื้นฐาน 8 / 12 / 16 / 24 · เป้าสัมผัส 48 · ตัวอักษรไทยไม่ตัดคำสั่งหลัก',
             'ออกแบบสถานะว่าง กำลังทำงาน ผิดพลาด ออฟไลน์ และสิทธิ์ไม่พร้อม คู่กับหน้าปกติ',
             'แท็บเล็ตแยกรายการกับรายละเอียด การฝึกจำกัดความกว้าง ไม่ยืดหน้ามือถือเต็มจอ']
    for i, rule in enumerate(rules):
        b.text(38, 1070 + i * 41, rule, 19, MUTED)
    b.save('system-study.svg')


if __name__ == '__main__':
    study()
    system_study()
    print('Generated direction-study.svg + system-study.svg: 13 editable phone studies, 390×844 each; XML self-check passed')
