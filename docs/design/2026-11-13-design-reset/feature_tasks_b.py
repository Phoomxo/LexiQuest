"""Retained answers, review lists, planning and motivation in the editable prototype."""

from exam_routes import example
from proposed_planner import GOAL, MOTIVE, PLAN, REMIND, TIMER

HOME = "choose_mode_screen"
LIB = "categories_page"
PROGRESS = "mastery_dashboard_screen"
ACCOUNT = "profile_settings_screen"
PRACTICE = "select_category_for_quiz"
WORD = "_word"
DESK = "_review_desk"
SETUP = "_setup_round"
WEEK = "_plan_week"
QUEST = "_plan_quest"
STREAK = "_plan_streak"
SYNC_QUESTION = "_round_sync_demo"

def row(label, detail, target=None):
    return "row", label, detail, target

def append(s, key, *, blocks=(), buttons=()):
    family, title, section, old_blocks, old_buttons, tab = s[key]
    s[key] = family, title, section, [*old_blocks, *blocks], [*old_buttons, *buttons], tab

def round_setup(s):
    s[SETUP] = example("settings", "เตรียมรอบฝึก", "ชุดการเดินทาง", [
        row("เลือกคำแปล 1 คำ", "ไม่จับเวลา · อ่านคำถามเอง", "quiz_screen"),
        row("เลือกคำแปล 2 คำ", "ไม่จับเวลา · เปรียบเทียบผลของแต่ละคำ", "_travel_q1"),
        row("ฝึกแบบอ่านเอง", "ปรับเวลาและเสียงก่อนเริ่ม", "_round_preferences"),
        row("เปลี่ยนวิธีตอบ", "เลือกจากนิยาม จับคู่ เขียน หรือสลับภาษา", "_exam_planned"),
        row("ฝึกต่อเมื่อบันทึกไม่ได้", "ลองกู้คำตอบโดยไม่ต้องเริ่มรอบใหม่", SYNC_QUESTION),
    ], [("กลับไปเลือกชุดคำ", PRACTICE)])
    for mode, title, detail in [
        ("quiet", "อ่านเอง", "ไม่เล่นเสียง · ตัวอักษรใหญ่"),
        ("listen", "ฟังและอ่าน", "เปิดปุ่มฟัง · มีประโยคให้อ่าน"),
    ]:
        setting = "_round_preferences" if mode == "quiet" else "_round_prefs_listen"
        other = "_round_prefs_listen" if mode == "quiet" else "_round_preferences"
        s[setting] = example("settings", "เลือกวิธีฝึกรอบนี้", "การเดินทาง · เลือกความหมาย 1 คำ", [
            ("lines", "วิธีรับโจทย์", title, detail),
            row("เปลี่ยนเป็น" + ("ฟังและอ่าน" if mode == "quiet" else "อ่านเอง"), "เปลี่ยนก่อนเริ่มรอบได้", other),
            row("ฝึกตามจังหวะของฉัน", "ใช้เวลาได้เท่าที่ต้องการ", "_round_" + mode),
            row("ใช้เวลาเป็นแนวทาง", "5 นาที · ยังตอบต่อได้เมื่อหมดเวลา", "_round_" + mode + "_clock"),
        ], [("กลับไปเลือกจำนวนคำ", SETUP)])
        for clock in ("", "_clock"):
            question = "_round_" + mode + clock
            time_label = "5 นาที · ไม่มีการตัดจบ" if clock else "ไม่จับเวลา"
            feedback = question + "_saved"
            options = [("choice", "ชานชาลา", feedback), ("choice", "ตั๋ว", question + "_miss")]
            blocks = [("hero", "เลือกความหมายของคำนี้", "platform", "Wait on platform two."), *options]
            if mode == "listen":
                blocks.append(row("ฟังคำนี้", "ดูคำอ่านประกอบเสียงตัวอย่าง", question + "_audio"))
                s[question + "_audio"] = example("audio", "ฟังและอ่านตาม", "การเดินทาง · เสียงตัวอย่าง", [
                    ("hero", "คำนาม", "platform", "/ˈplæt.fɔːm/"),
                    ("quote", "อ่านประโยค", "Wait on platform two.", "คำหลักอยู่หลังคำว่า on"),
                ], [("กลับไปตอบ", question)])
            s[question] = example("practice", "เลือกความหมาย", "1 จาก 1 · " + time_label, blocks, [
                ("เก็บคำนี้ไว้อ่าน", question + "_bookmark"), ("กลับไปตั้งค่ารอบ", setting)])
            bookmark(s, question, question + "_bookmark", "platform", "ชานชาลา", "กลับไปตอบคำเดิม")
            for correct, result, choice in ((True, feedback, "ชานชาลา"), (False, question + "_miss", "ตั๋ว")):
                s[result] = example("result", "ตอบถูกแล้ว" if correct else "ลองเทียบสองคำนี้", "บันทึกคำตอบแล้ว · 1 จาก 1", [
                    ("quote", "คำที่เลือก", choice, "platform คือ ชานชาลา"),
                    ("lines", "ตัวอย่างการใช้", "Wait on platform two.", "รอที่ชานชาลาสอง"),
                ], [("กลับไปเลือกชุดคำ", PRACTICE), ("ลองคำนี้อีกครั้ง", question)])
    s[SYNC_QUESTION] = example("practice", "เลือกความหมาย", "การเดินทาง · ตัวอย่างเมื่อบันทึกขัดข้อง", [
        ("hero", "คำนี้หมายถึงอะไร", "platform", "Wait on platform two."),
        ("choice", "ชานชาลา", "_round_write_error"), ("choice", "ตั๋ว", "_round_wrong_error"),
    ])
    for key, chosen, verdict, saved in [
        ("_round_write_error", "ชานชาลา", "ตอบถูกแล้ว", "_round_quiet_saved"),
        ("_round_wrong_error", "ตั๋ว", "คำที่ถูกคือชานชาลา", "_round_quiet_miss"),
    ]:
        s[key] = example("practice", "บันทึกคำตอบไม่สำเร็จ", "คำตอบของรอบนี้ยังอยู่", [
            ("quote", "คำตอบที่เลือกไว้", chosen, verdict),
            ("note", "ยังไม่นับคะแนนของข้อนี้", "กดบันทึกอีกครั้งได้โดยไม่ต้องตอบใหม่"),
        ], [("บันทึกคำตอบเดิมอีกครั้ง", saved), ("กลับไปดูโจทย์", SYNC_QUESTION)])

def bookmark(s, source, saved, word, meaning, back):
    s[saved] = example("list", "เก็บคำนี้แล้ว", "คำที่เก็บไว้ · เปิดได้ขณะออฟไลน์", [
        ("quote", "จากชุดการเดินทาง", word, meaning),
    ], [(back, source), ("นำคำนี้ออกจากรายการ", saved + "_off")])
    s[saved + "_off"] = example("list", "นำคำนี้ออกแล้ว", "คำที่เก็บไว้", [
        ("note", word + " ยังอยู่ในชุดการเดินทาง", "เก็บไว้อ่านครั้งหน้าได้ทุกเมื่อ"),
    ], [(back, source), ("เก็บคำนี้อีกครั้ง", saved)])

def reporting(s):
    for key in [key for key in s if key == "_article_term" or key.startswith("_article_term_")]:
        reader = next(target for label, target in s[key][4] if label == "อ่านต่อที่เดิม")
        saved = key + "_bookmark"
        append(s, key, buttons=[("เก็บคำนี้ไว้อ่าน", saved)])
        bookmark(s, reader, saved, "platform", "ชานชาลา", "อ่านต่อที่เดิม")
    s["_bookmarked"] = example("list", "คำที่เก็บไว้", "เก็บในเครื่อง · เปิดดูได้ขณะออฟไลน์", [
        row("station", "สถานี · ชุดการเดินทาง", WORD),
    ], [("นำ station ออกจากรายการ", "_unbookmarked"), ("กลับคลังคำ", LIB)])
    s["_unbookmarked"] = example("list", "ยังไม่มีคำที่เก็บไว้", "รายการคำของฉัน", [
        ("note", "นำ station ออกจากรายการแล้ว", "คำนี้ยังอยู่ในชุดการเดินทาง"),
    ], [("กลับไปดูคำว่า station", WORD), ("กลับศูนย์ทบทวน", DESK)])
    append(s, DESK, blocks=[row("รายงานที่รอส่ง", "ตรวจคำและปัญหาที่แจ้งไว้", "_report_queue")], buttons=[("กลับคลังคำ", LIB)])
    s["_report"] = example("form", "ตรวจรายงานก่อนส่ง", "ชุดการเดินทาง · ฉบับทดลอง 1", [
        ("lines", "คำที่แจ้ง", "station · สถานี", "Meet me at the station."),
        row("คำแปลไม่ตรงกับประโยค", "แตะเพื่อเปลี่ยนประเภทปัญหา", "_report_kind"),
        ("note", "ข้อมูลที่จะส่ง", "คำศัพท์ ประโยคตัวอย่าง และรุ่นเนื้อหา"),
    ], [("เก็บรายงานไว้ส่งเมื่อออนไลน์", "_report_queue"), ("ยกเลิก", "_provenance")])
    s["_report_kind"] = example("form", "ปัญหาที่พบ", "station · ฉบับทดลอง 1", [
        ("choice", "คำแปลไม่ตรงกับประโยค", "_report"),
        ("choice", "ประโยคตัวอย่างสะกดผิด", "_report_sentence"),
    ])
    s["_report_sentence"] = example("form", "ตรวจรายงานก่อนส่ง", "ชุดการเดินทาง · ฉบับทดลอง 1", [
        ("lines", "คำที่แจ้ง", "station · สถานี", "Meet me at the station."),
        row("ประโยคตัวอย่างสะกดผิด", "แตะเพื่อเปลี่ยนประเภทปัญหา", "_report_kind"),
        ("note", "ข้อมูลที่จะส่ง", "คำศัพท์ ประโยคตัวอย่าง และรุ่นเนื้อหา"),
    ], [("เก็บรายงานไว้ส่งเมื่อออนไลน์", "_report_queue_sentence"), ("ยกเลิก", "_provenance")])
    for key, reason in [("_report_queue", "คำแปลไม่ตรงกับประโยค"), ("_report_queue_sentence", "ประโยคตัวอย่างสะกดผิด")]:
        s[key] = example("list", "รายงานที่รอส่ง", "ออฟไลน์ · เก็บในเครื่อง", [
            ("lines", "station · ชุดการเดินทาง ฉบับทดลอง 1", reason, "ยังไม่ส่งถึงผู้จัดทำ"),
        ], [("กลับไปที่คลังคำ", LIB), ("กลับศูนย์ทบทวน", DESK)])
    append(s, "_paired_sample", blocks=[
        row("ดูคำตอบที่ใช้เปรียบเทียบ", "สองครั้งใช้คำชุดเดียวกัน", "_paired_words")], buttons=[
        ("กลับไปดูตัวเลือกงานวิจัย", "_research_choice")])
    s["_paired_words"] = example("result", "เทียบคำตอบรายคำ", "ตัวอย่างคู่ฝึก 01 · ชุดการเดินทาง ฉบับ 1", [
        ("lines", "station · เลือกความหมาย", "ก่อนฝึก ตอบว่าสถานี", "หลังฝึก ตอบว่าสถานี"),
        ("lines", "platform · เลือกความหมาย", "ก่อนฝึก ตอบว่าสถานี", "หลังฝึก ตอบว่าชานชาลา"),
        ("note", "ข้อมูลสมมติของสองรอบ", "ไม่มีการรับสมัครหรือส่งข้อมูลผู้เรียน"),
    ], [("กลับไปดูผลเปรียบเทียบ", "_paired_sample")])

DAYS = [
    ("tue", "อังคาร 10 พ.ย.", "6 นาที", "3 จาก 5 ข้อ", "ทบทวนคำในชีวิตประจำวัน"),
    ("thu", "พฤหัสบดี 12 พ.ย.", "8 นาที", "5 จาก 6 ข้อ", "ฝึกคำที่เจอระหว่างเดินทาง"),
    ("fri", "ศุกร์ 13 พ.ย.", "4 นาที", "0 จาก 1 ข้อ", "ลองแยก station กับ platform"),
]

def planning(s):
    append(s, TIMER, buttons=[("กลับไปแผนฝึก", PLAN)])
    s[WEEK] = example("list", "สัปดาห์ของฉัน", "9 ถึง 15 พฤศจิกายน · ข้อมูลตัวอย่าง", [
        ("stat", "18 นาที", "ฝึก 3 วัน", "เลือกวันที่ฝึกเพื่อดูเวลาและผลของวันนั้น"),
        *(row(day, duration + " · ตอบถูก " + score, "_calendar_" + key) for key, day, duration, score, _ in DAYS),
    ], [("กลับไปดูความก้าวหน้า", PROGRESS), ("กลับไปแผนฝึก", PLAN)])
    for key, day, duration, score, activity in DAYS:
        s["_calendar_" + key] = example("result", day, "บันทึกรายวัน · ข้อมูลตัวอย่าง", [
            ("stat", duration, "เวลาที่ฝึกจริง", "หักเวลาพักและช่วงที่ออกจากแอปแล้ว"),
            ("lines", "สิ่งที่ฝึก", activity, "ตอบถูก " + score),
        ], [("กลับไปดูทั้งสัปดาห์", WEEK)])
    s["_plan_time_log"] = example("result", "เวลาที่ฝึกรอบนี้", "ข้อมูลตัวอย่าง · รอบวันศุกร์", [
        ("stat", "2 นาที", "เวลาที่ฝึกจริง", "เริ่มฝึก 09:00 น. · จบรอบ 09:05 น."),
        ("lines", "ช่วงที่นับเวลา", "09:00–09:01 และ 09:04–09:05", "รวมเวลาฝึกสองช่วง ช่วงละหนึ่งนาที"),
        ("lines", "ช่วงที่ไม่นับ", "พักหรือออกจากแอป 09:01–09:04", "หักออก 3 นาที"),
    ], [("ดูสัปดาห์ของฉัน", WEEK), ("เริ่มรอบใหม่", TIMER)])
    s[REMIND] = example("settings", "เตือนให้กลับมาฝึก", "ปิดการเตือนอยู่", [
        ("note", "เลือกช่วงที่สะดวก", "จะเปิดการเตือนหลังคุณอนุญาต"),
        ("choice", "เสาร์และอาทิตย์ เวลา 09:00 น.", "_perm_am"),
        ("choice", "จันทร์ถึงศุกร์ เวลา 19:00 น.", "_perm_pm"),
    ], [("ปิดต่อไป", PLAN)])
    for key, name in [("am", "เสาร์และอาทิตย์ 09:00 น."), ("pm", "จันทร์ถึงศุกร์ 19:00 น.")]:
        s["_perm_" + key] = example("settings", "เปิดการแจ้งเตือนไหม", name, [
            ("note", "เตือนเฉพาะช่วงที่คุณเลือก", "ยังเรียนได้ตามปกติเมื่อปิดการเตือน"),
        ], [("อนุญาตให้เตือน", "_plan_remind_" + key), ("ยังไม่อนุญาต", "_remind_denied")])
        s["_plan_remind_" + key] = example("settings", "เปิดการเตือนแล้ว", "กำหนดการตัวอย่าง", [
            ("lines", "เวลาที่เตือน", name, "ถึงเวลาทบทวนคำที่เก็บไว้"),
        ], [("แก้วันและเวลา", REMIND), ("ปิดการเตือน", "_remind_off")])
    for key, status in [("_remind_denied", "ยังไม่เปิดการแจ้งเตือน"), ("_remind_off", "ปิดการเตือนแล้ว")]:
        s[key] = example("settings", status, "การเตือนฝึก", [
            ("note", "แผนการฝึกยังอยู่", "กลับมาเปิดการเตือนได้เมื่อสะดวก"),
        ], [("กลับไปแผนฝึก", PLAN), ("เลือกเวลาใหม่", REMIND)])
    s[QUEST] = example("practice", "ภารกิจวันนี้", "ตัวอย่างวันที่ 13 พฤศจิกายน", [
        ("meter", "ตอบถูกแล้ว 4 จาก 5 ข้อ", .8),
        ("lines", "คำที่นับเข้าภารกิจแล้ว", "train · ticket · bus · station", "อีกหนึ่งข้อจะได้รับ 50 แต้มประสบการณ์"),
    ], [("ฝึกข้อที่เหลือ", "_quest_last"), ("กลับไปดูภารกิจและเพื่อนฝึก", MOTIVE)])
    s["_quest_last"] = example("practice", "เลือกความหมาย", "ภารกิจวันนี้ · เหลืออีก 1 ข้อ", [
        ("hero", "คำนี้หมายถึงอะไร", "platform", "Meet me on platform two."),
        ("choice", "สถานี", "_quest_retry"), ("choice", "ชานชาลา", "_quest_award"),
    ])
    s["_quest_retry"] = example("practice", "ลองแยกสองคำนี้", "ภารกิจวันนี้ · ยังผ่าน 4 จาก 5 ข้อ", [
        ("lines", "คำที่เลือก", "station หมายถึงสถานี", "platform คือชานชาลาที่ใช้รอรถไฟ"),
    ], [("ลองตอบอีกครั้ง", "_quest_last"), ("พักก่อน", QUEST)])
    s["_quest_award"] = example("result", "ทำภารกิจครบแล้ว", "ภารกิจวันนี้ · 13 พฤศจิกายน", [
        ("meter", "ตอบถูกครบ 5 ข้อ", 1),
        ("quote", "คำที่ทำให้ครบ", "platform · ชานชาลา", "รวมกับสี่ข้อที่ตอบถูกก่อนหน้านี้"),
        ("note", "รางวัลภารกิจ", "50 แต้มประสบการณ์"),
    ], [("รับแต้มภารกิจ", "_quest_claimed")])
    s["_quest_claimed"] = example("result", "รับแต้มภารกิจแล้ว", "ภารกิจวันนี้ · รับแล้ว", [
        ("lines", "รางวัลที่ได้รับ", "50 แต้มประสบการณ์", "ภารกิจนี้รับแต้มได้ครั้งเดียว"),
        ("note", "คำที่ตอบถูกข้อสุดท้าย", "platform · ชานชาลา"),
    ], [("กลับไปดูภารกิจ", "_motive_claimed")])
    family, title, subtitle, blocks, buttons, tab = s[MOTIVE]
    s["_motive_claimed"] = (family, title, subtitle, [
        row("ภารกิจประจำวัน", "ครบ 5 ข้อ · รับ 50 แต้มแล้ว", "_quest_claimed"), *blocks[1:]
    ], [*buttons, ("กลับไปแผนฝึก", PLAN)], tab)

def install(s):
    round_setup(s)
    reporting(s)
    planning(s)

def render(d):
    if d.key != WEEK:
        return False
    from focused_learning import action, row as draw_row
    d.back()
    d.text(24, 84, "สัปดาห์ของฉัน", 30, d.ink, True)
    d.text(24, 135, "9 ถึง 15 พฤศจิกายน · ข้อมูลตัวอย่าง", 17, d.sub)
    d.text(24, 198, "18 นาที", 39, d.ink, True, 142)
    d.text(171, 209, "จากการฝึก 3 วัน", 18, d.sub, False, 180)
    for i, (weekday, value) in enumerate(zip(["จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส.", "อา."], [0, 6, 0, 8, 4, 0, 0])):
        x = 28 + 48*i
        if value:
            d.text(x, 342 - value*9 - 28, str(value), 16, d.ink, True, 33)
            d.box(x, 342 - value*9, 24, value*9, "#3942AD", 3)
        d.text(x, 353, weekday, 15, d.sub, False, 43)
    d.box(24, 342, 342, 1, d.rule)
    d.text(24, 408, "เลือกวันที่ฝึก", 20, d.ink, True)
    for i, (key, day, duration, score, _) in enumerate(DAYS):
        draw_row(d, 458 + i*75, day, duration + " · ตอบถูก " + score, "_calendar_"+key)
    action(d, 691, "กลับไปดูความก้าวหน้า", PROGRESS, False)
    action(d, 758, "กลับไปแผนฝึก", PLAN, False)
    return True

TODAY_ROUND = [HOME, PRACTICE]
WORD_PATH = [LIB, "vocab_list_screen", WORD]
PLANNING = [PROGRESS, PLAN]
MOTIVATION = PLANNING + [MOTIVE]
TIMED = PLANNING + [TIMER, "_plan_timer_5", "_plan_paused_5"]

TASKS = {
    16: ("ตั้งรอบหนึ่งคำให้อ่านเองโดยไม่จับเวลา แล้วฝึกจนจบ",
         TODAY_ROUND + [SETUP, "_round_preferences", "_round_quiet", "_round_quiet_saved", PRACTICE],
         "_round_quiet", "1 จาก 1 · ไม่จับเวลา", "มีชุดตัวอย่าง 1 และ 2 คำ พร้อมตัวเลือกเสียงและเวลา การใช้ค่ากับทุกรูปแบบต้องตรวจในแอป"),
    17: ("บันทึกคำตอบเดิมอีกครั้งหลังบันทึกไม่สำเร็จ",
         TODAY_ROUND + [SETUP, SYNC_QUESTION, "_round_write_error", "_round_quiet_saved", PRACTICE],
         "_round_quiet_saved", "บันทึกคำตอบแล้ว · 1 จาก 1", "จำลองการเขียนล้มเหลวและสำเร็จ ต้องทดสอบกับที่เก็บข้อมูลว่าการลองใหม่ไม่เพิ่มคะแนนซ้ำ"),
    18: ("เทียบคำที่เลือกผิดกับความหมายของ platform แล้วดูผล",
         TODAY_ROUND + ["quiz_screen", "_quiz_station", "score_screen", HOME],
         "_quiz_station", "station คือ สถานี", "เปรียบเทียบตัวลวงที่เลือกในหนึ่งข้อ ตัวลวงทุกคำต้องตรวจจากชุดเนื้อหาจริง"),
    19: ("ดูคำใบ้จากประโยคแล้วเขียนคำว่า station",
         WORD_PATH + ["dictation_quiz_screen", "_dict_hint", "_dict_write", "_dict_feedback", WORD],
         "_dict_hint", "Meet me at the ____.", "ต้นแบบใช้คำตอบที่เตรียมไว้ การพิมพ์อิสระและเสียงจริงต้องตรวจบนอุปกรณ์"),
    20: ("เก็บคำไว้อ่านระหว่างออฟไลน์แล้วนำออกจากรายการ",
         WORD_PATH + ["_word_tools", "_bookmarked", "_unbookmarked", WORD],
         "_unbookmarked", "นำ station ออกจากรายการแล้ว", "รายการเป็นตัวอย่างบนเครื่อง ยังไม่ตรวจการคงข้อมูลเมื่อเปลี่ยนบัญชีหรือเปิดแอปใหม่"),
    21: ("แจ้งว่าประโยคสะกดผิดและตรวจรายงานที่รอส่ง",
         [LIB, "_packs", "_pack", "_provenance", "_report", "_report_kind", "_report_sentence", "_report_queue_sentence", LIB],
         "_report_queue_sentence", "ประโยคตัวอย่างสะกดผิด", "ต้นแบบแสดงรายงานในคิวออฟไลน์ การส่งและรับรายงานจากผู้จัดทำต้องทดสอบที่ระบบ"),
    22: ("เปิดศูนย์ทบทวนแล้วดูรายงานที่ยังรอส่ง",
         [LIB, DESK, "_report_queue", DESK, LIB],
         "_report_queue", "ยังไม่ส่งถึงผู้จัดทำ", "ใช้รายการรายงานตัวอย่าง การอ่านคำถึงกำหนด ข้อผิด คำที่เก็บ และรายงานของผู้ใช้จริงอยู่ขั้นแอป"),
    23: ("ตั้งเวลาห้านาที พัก แล้วจบรอบหลังกลับมาฝึกต่อ",
         TIMED + ["_plan_resume_5", "_plan_time_log", TIMER, PLAN],
         "_plan_paused_5", "คงเหลือเท่าเดิม", "ต้นแบบเปลี่ยนสถานะเวลาเป็นช่วง ไม่ได้จับเวลาจริง"),
    24: ("ตรวจว่าเวลาฝึกสองนาทีหักช่วงพักสามนาทีแล้ว",
         TIMED + ["_plan_resume_5", "_plan_time_log", WEEK, PROGRESS],
         "_plan_time_log", "หักออก 3 นาที", "เวลาและเหตุการณ์ออกจากแอปเป็นข้อมูลสมมติ ต้องวัดจากวงจรชีวิตแอปจริง"),
    25: ("เลือกวันพฤหัสบดีเพื่อดูเวลาและผลของวันนั้น",
         PLANNING + [WEEK, "_calendar_thu", WEEK, PROGRESS],
         "_calendar_thu", "ตอบถูก 5 จาก 6 ข้อ", "ปฏิทินตัวอย่างมีผลสามวันในหนึ่งสัปดาห์ ยังไม่ทดสอบการรวมผลข้ามเขตเวลา"),
    26: ("เลื่อนวันเป้าหมายจากหนึ่งเป็นสองสัปดาห์แล้วปิดเป้าหมาย",
         PLANNING + [GOAL, "_plan_goal_7", GOAL, "_plan_goal_14", "_plan_goal_off", PLAN],
         "_plan_goal_14", "14 วัน", "นับถอยหลังจากวันที่ตัวอย่าง 13 พฤศจิกายน การเปลี่ยนวันตามนาฬิกาจริงต้องทดสอบในแอป"),
    27: ("เปิดเตือนเฉพาะเย็นวันธรรมดาแล้วปิดการเตือน",
         PLANNING + [REMIND, "_perm_pm", "_plan_remind_pm", "_remind_off", PLAN],
         "_plan_remind_pm", "จันทร์ถึงศุกร์ 19:00 น.", "ใช้หน้าสิทธิ์และกำหนดการตัวอย่าง ไม่มีการตั้งเวลาส่งการแจ้งเตือนจริง"),
    28: ("เปิดหลักฐานรายคำของผลก่อนและหลังฝึก แล้วกลับตัวเลือกงานวิจัย",
         [ACCOUNT, "setting_screen", "_research_choice", "_paired_sample", "_paired_words", "_paired_sample", "_research_choice", HOME],
         "_paired_words", "หลังฝึก ตอบว่าชานชาลา", "เป็นการอ่านข้อมูลสมมติ ไม่มีข้อมูลผู้เข้าร่วม การวัดจริงต้องยืนยันแบบวัด สิทธิ์ และการจับคู่รอบ"),
    29: ("ทำข้อสุดท้ายของภารกิจและกลับมาดูว่าได้รับแต้มแล้ว",
         MOTIVATION + [QUEST, "_quest_last", "_quest_retry", "_quest_last", "_quest_award", "_quest_claimed", "_motive_claimed"],
         "_motive_claimed", "ครบ 5 ข้อ · รับ 50 แต้มแล้ว", "ใช้เงื่อนไขภารกิจตอบถูกห้าข้อตามซอร์ส การป้องกันการให้รางวัลซ้ำต้องทดสอบกับตัวบันทึกจริง"),
    30: ("ดูวันที่กลับมาฝึกหลังวันพักแล้วเปิดสัปดาห์เดิม",
         MOTIVATION + [STREAK, WEEK, "_calendar_thu", WEEK, PROGRESS],
         STREAK, "เว้นไปหนึ่งวันก็เริ่มฝึกต่อได้", "ใช้ประวัติตัวอย่างหนึ่งสัปดาห์ การตัดวันและนับช่วงต่อเนื่องอยู่ที่ข้อมูลจริง"),
}
