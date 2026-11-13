"""Clickable illustrations of the optional plan, motivation and preferences in the TOR."""

PLAN = "_plan_studio"
MOTIVE = "_motivation_studio"
PREF = "_plan_pref"
TIMER = "_plan_timer"
GOAL = "_plan_goal"
REMIND = "_plan_reminder"
ACCESS = "_plan_access"
SHARE = "_plan_share"
PRACTICE = "select_category_for_quiz"


def screen(title, blocks, buttons=(), section="แผนฝึกตัวอย่าง", family="settings"):
    return family, title, section, blocks, list(buttons), None


def install(screens):
    screens.update({
        PLAN: screen("แผนฝึกของฉัน", [
            ("row", "สัปดาห์นี้ฝึกเมื่อไรบ้าง", "ดูวันที่ฝึก เวลา และผลการฝึก", "_plan_week"),
            ("row", "ตั้งวันเป้าหมาย", "กำหนดวันที่อยากฝึกให้ทัน", GOAL),
            ("row", "จับเวลาฝึก", "เริ่มเว้นช่วง พัก หรือจบรอบได้", TIMER),
            ("row", "เตือนให้กลับมาฝึก", "ดูตัวอย่างวันและเวลาเตือน", REMIND),
            ("row", "ภารกิจและเพื่อนฝึก", "ดูความต่อเนื่องและสิ่งที่ทำได้", MOTIVE),
            ("row", "ปรับวิธีเรียน", "ความสนใจ เวลา และการอ่านหน้าจอ", PREF),
        ], [("ฝึกโดยไม่ตั้งแผน", PRACTICE)]),
        "_plan_week": screen("สัปดาห์ของฉัน", [
            ("stat", "18 นาที", "3 วันที่ได้ฝึก", "สัปดาห์ 9–15 พฤศจิกายน · ข้อมูลตัวอย่าง"),
            ("row", "อังคาร 10 พ.ย.", "6 นาที  ·  ตอบถูก 3 จาก 5 ข้อ", "_history"),
            ("row", "พฤหัสบดี 12 พ.ย.", "8 นาที  ·  ตอบถูก 5 จาก 6 ข้อ", "_history"),
            ("row", "ศุกร์ 13 พ.ย.", "4 นาที  ·  ตอบถูก 0 จาก 1 ข้อ", "_history"),
        ], [("ดูผลการฝึก", "mastery_dashboard_screen")]),
        GOAL: screen("ตั้งวันเป้าหมาย", [
            ("lines", "เป้าหมายตัวอย่าง", "ฝึกคำเดินทางให้ทันวันออกเดินทาง", "วันนี้ 13 พฤศจิกายน"),
            ("choice", "20 พฤศจิกายน · อีก 7 วัน", "_plan_goal_7"),
            ("choice", "27 พฤศจิกายน · อีก 14 วัน", "_plan_goal_14"),
        ], [("เรียนต่อโดยไม่ตั้งเป้าหมาย", PRACTICE)]),
        REMIND: screen("เตือนให้กลับมาฝึก", [
            ("lines", "ปิดการเตือนอยู่", "เลือกวันและเวลาที่สะดวก", "ต้นแบบแสดงตัวอย่างในหน้านี้"),
            ("choice", "เสาร์และอาทิตย์ เวลา 09:00 น.", "_plan_remind_am"),
            ("choice", "จันทร์ถึงศุกร์ เวลา 19:00 น.", "_plan_remind_pm"),
        ], [("คงการเตือนเป็นปิด", PLAN)]),
        TIMER: screen("จับเวลาฝึก", [
            ("lines", "ฝึกหนึ่งช่วง", "เริ่มจับเวลาเมื่อลงมือฝึก", "ตอนพักหรือออกจากแอป ระบบหยุดนับ"),
            ("choice", "ฝึก 5 นาที", "_plan_timer_5"),
            ("choice", "ฝึก 10 นาที", "_plan_timer_10"),
        ], [("ฝึกโดยไม่จับเวลา", PRACTICE)]),
        "_plan_time_log": screen("เวลาที่ฝึกรอบนี้", [
            ("stat", "2 นาที", "เวลาที่ลงมือฝึก", "ข้อมูลตัวอย่าง · ไม่นับช่วงหยุดพัก"),
            ("lines", "บันทึกเวลาของรอบนี้", "ฝึก 1 นาที → พัก → ฝึกอีก 1 นาที", "ดูผลคำตอบแยกได้ในความก้าวหน้า"),
        ], [("ดูสัปดาห์ของฉัน", "_plan_week"), ("เริ่มรอบใหม่", TIMER)]),
        MOTIVE: screen("ภารกิจและเพื่อนฝึก", [
            ("row", "ภารกิจประจำวัน", "ตอบคำศัพท์ให้ถูก 5 ข้อ", "_plan_quest"),
            ("row", "วันที่ได้กลับมาฝึก", "ดูช่วงที่ฝึกและวันที่พัก", "_plan_streak"),
            ("row", "เพื่อนฝึกของฉัน", "ลองดูคำใบ้หลังเลือกคำแปล", "_plan_friend"),
            ("row", "การ์ดสิ่งที่ทำสำเร็จ", "เลือกข้อมูลที่อยากบอกคนอื่น", SHARE),
        ]),
        "_plan_quest": screen("ภารกิจวันนี้", [
            ("meter", "ตอบถูกแล้ว 0 จาก 5 ข้อ", 0),
            ("lines", "ฝึกเลือกความหมาย", "ทุกคำตอบที่ถูกช่วยให้ใกล้ครบภารกิจ", "รางวัลเมื่อครบ 5 ข้อ · 50 แต้มประสบการณ์"),
        ], [("เริ่มทำข้อแรก", PRACTICE), ("ดูวันที่ได้ฝึก", "_plan_streak")], family="practice"),
        "_plan_streak": screen("วันที่ได้กลับมาฝึก", [
            ("stat", "2 วัน", "ที่ฝึกต่อเนื่อง", "พฤหัสบดีและศุกร์ · สัปดาห์ตัวอย่าง"),
            ("lines", "อังคารฝึก · พุธพัก · พฤหัสฝึก · ศุกร์ฝึก", "เว้นไปหนึ่งวันก็เริ่มฝึกต่อได้", "ประวัติการฝึกครั้งก่อนยังดูได้"),
        ], [("ดูสัปดาห์นี้", "_plan_week"), ("ลองฝึกคำเดียว", "srs_flashcards_screen")]),
        "_plan_friend": screen("เพื่อนฝึกของฉัน", [
            ("quote", "คำใบ้จากเพื่อนฝึก หลังเลือกคำว่า station", "สถานีมีหลายชานชาลา", "ถ้าเห็นป้าย platform 2 ให้ไปที่ชานชาลาสอง"),
            ("row", "ลองใช้คำว่า platform", "เติมคำที่หายไปในประโยค", "fill_in_the_blanks_screen"),
            ("row", "ปรับการแสดงผล", "ดูตัวอย่างเพื่อนฝึกแบบภาพนิ่ง", ACCESS),
        ]),
        SHARE: screen("ทำการ์ดสิ่งที่ทำสำเร็จ", [
            ("art", "medal", "กลับมาฝึก 2 วันติด"),
            ("note", "การ์ดแสดงเฉพาะสิ่งที่ทำสำเร็จ", "ซ่อนชื่อ บัญชี และคำที่ตอบผิด"),
            ("choice", "แสดงวันที่ฝึกบนการ์ด", "_plan_share_with_date"),
            ("choice", "ซ่อนวันที่ฝึก", "_plan_share_without_date"),
        ], [("ยกเลิก", MOTIVE)]),
        "_plan_share_preview": screen("ตัวอย่างก่อนแชร์", [
            ("lines", "ต้นแบบการ์ด", "ในแอปคุณจะเลือกแอปปลายทางได้", "ต้นแบบนี้ยังไม่มีการส่งการ์ดให้ใคร"),
        ], [("กลับไปแก้การ์ด", SHARE), ("จบการดูตัวอย่าง", MOTIVE)]),
        "_plan_card_saved": screen("ตัวอย่างการเก็บการ์ด", [
            ("note", "การ์ดพร้อมเก็บเป็นภาพ", "ไฟล์ตัวอย่างนี้แสดงหน้าตาหลังเลือกบันทึก"),
        ], [("กลับไปดูของสะสม", "achievements_screen")]),
        PREF: screen("ปรับวิธีเรียน", [
            ("row", "โปรไฟล์การเรียน", "ดูข้อมูลที่ใช้แนะนำแบบฝึก", "_plan_profile"),
            ("row", "เลือกสิ่งที่อยากฝึก", "กำหนดเป้าหมาย เวลา และวิธีฝึก", "_plan_preferences"),
            ("row", "การอ่านและการเคลื่อนไหว", "ตัวอย่างขนาดข้อความ ภาพนิ่ง และธีม", ACCESS),
        ], [("ข้ามและเลือกชุดคำ", PRACTICE)]),
        "_plan_profile": screen("โปรไฟล์การเรียน", [
            ("row", "เป้าหมายและความสนใจ", "ใช้ภาษาอังกฤษเวลาเดินทาง", "_plan_preferences"),
            ("row", "เวลาที่สะดวก", "ครั้งละ 5 นาที", "_plan_pref_time"),
            ("row", "วิธีที่อยากฝึก", "อ่านเรื่องสั้น", "_plan_pref_method"),
            ("note", "ใช้ข้อมูลนี้แนะนำบทอ่าน", "คุณเลือกแบบฝึกอื่นได้เสมอ"),
        ], [("ลองอ่านเรื่องที่สถานี", "cefr_article_reader_screen")]),
        "_plan_preferences": screen("อยากใช้ภาษาอังกฤษที่ไหน", [
            ("choice", "เวลาเดินทาง · ฟังประกาศและอ่านป้าย", "_plan_pref_time"),
            ("choice", "ยังไม่มีเป้าหมาย", "_plan_undecided"),
        ], [("ข้ามคำถาม", PRACTICE)]),
        "_plan_undecided": screen("เริ่มจากคำใกล้ตัว", [
            ("note", "ยังไม่ต้องตั้งเป้าหมาย", "เลือกเรื่องที่สนใจจากคลังคำได้เลย"),
        ], [("เปิดคลังคำ", "categories_page"), ("กลับไปเลือกเป้าหมาย", "_plan_preferences")]),
        "_plan_pref_time": screen("มีเวลาฝึกแค่ไหน", [
            ("choice", "ประมาณ 5 นาทีต่อครั้ง", "_plan_pref_method"),
            ("choice", "เลือกเวลาทุกครั้งที่ฝึก", TIMER),
        ], [("ข้ามเรื่องเวลา", "_plan_pref_method")]),
        "_plan_pref_method": screen("อยากฝึกแบบไหน", [
            ("choice", "อ่านเรื่องสั้นจากชีวิตประจำวัน", "_plan_pref_read"),
            ("choice", "ฟังเสียงแล้วลองพูดตาม", "_plan_pref_speak"),
        ], [("ข้ามและดูคลังคำ", "categories_page")]),
        ACCESS: screen("การอ่านและการเคลื่อนไหว", [
            ("row", "ข้อความขนาดใหญ่", "ดูคำและประโยคตัวอย่าง", "_plan_large"),
            ("row", "ลดการเคลื่อนไหว", "แสดงเพื่อนฝึกเป็นภาพนิ่ง", "_plan_still"),
            ("row", "สีของหน้าจอ", "เปรียบเทียบตัวอย่างโหมดสว่างและมืด", "appearance_settings_screen"),
            ("row", "ฝึกโดยไม่จับเวลา", "เลือกคำตามจังหวะของตัวเอง", PRACTICE),
            ("row", "พิมพ์แทนการพูด", "เพิ่มคำที่สนใจด้วยแป้นพิมพ์", "add_vocab_screen"),
        ]),
        "_plan_still": screen("เพื่อนฝึกแบบภาพนิ่ง", [
            ("quote", "คำใบ้จากเพื่อนฝึก", "platform คือ ชานชาลา", "ภาพนิ่งและข้อความอยู่กับที่จนกว่าคุณจะอ่านจบ"),
        ], [("ลองฝึกคำนี้", "fill_in_the_blanks_screen"), ("กลับไปปรับการอ่าน", ACCESS)]),
        "_plan_large": screen("อ่านตัวอักษรใหญ่", [
            ("hero", "คำศัพท์", "platform", "ชานชาลา"),
            ("quote", "ตัวอย่างประโยค", "Wait on platform two.", "รอที่ชานชาลาสอง"),
        ], [("กลับไปปรับการอ่าน", ACCESS)], family="reader"),
    })
    for days, date in [(7, "20 พฤศจิกายน"), (14, "27 พฤศจิกายน")]:
        screens[f"_plan_goal_{days}"] = screen("วันเป้าหมายของฉัน", [
            ("stat", f"{days} วัน", "ก่อนออกเดินทาง", date+" · นับจากวันที่ในตัวอย่าง"),
        ], [("แก้วันเป้าหมาย", GOAL), ("ปิดเป้าหมายนี้", "_plan_goal_off")])
    screens["_plan_goal_off"] = screen("ปิดเป้าหมายแล้ว", [
        ("note", "กลับมาฝึกได้ตามสะดวก", "ตั้งวันเป้าหมายใหม่ได้ทุกเมื่อ"),
    ], [("กลับไปแผนฝึก", PLAN)])
    for slug, when in [("am","เสาร์และอาทิตย์ 09:00 น."), ("pm","จันทร์ถึงศุกร์ 19:00 น.")]:
        screens[f"_plan_remind_{slug}"] = screen("ตัวอย่างการเตือน", [
            ("lines", when, "ถึงเวลาฝึกคำที่คุณเก็บไว้", "ตัวอย่างข้อความบนหน้าจอ"),
        ], [("แก้วันและเวลา", REMIND), ("ปิดการเตือน", REMIND)])
    for minutes in (5,10):
        running=f"_plan_timer_{minutes}"
        paused=f"_plan_paused_{minutes}"
        screens[running]=screen("ช่วงฝึกของฉัน", [
            ("stat", f"{minutes-1}:00", "นาทีที่เหลือ", f"ภาพตัวอย่างหลังฝึก 1 นาที จากช่วง {minutes} นาที"),
            ("quote", "นึกคำแปลก่อนพัก", "Wait on platform two.", "คำไหนในประโยคหมายถึงชานชาลา"),
        ], [("พักการจับเวลา", paused), ("จบรอบนี้", "_plan_time_first")], family="practice")
        screens[paused]=screen("พักการฝึก", [
            ("stat", f"{minutes-1}:00", "คงเหลือเท่าเดิม", "เวลาที่พักจะไม่นับรวมในเวลาฝึก"),
        ], [("ฝึกต่ออีกหนึ่งนาที", f"_plan_resume_{minutes}"), ("จบรอบนี้", "_plan_time_first")])
        screens[f"_plan_resume_{minutes}"]=screen("กลับมาฝึกต่อ", [
            ("stat", f"{minutes-2}:00", "นาทีที่เหลือ", "ภาพตัวอย่างหลังฝึกต่ออีก 1 นาที"),
            ("quote", "เฉลยคำในประโยค", "platform · ชานชาลา", "Wait on platform two."),
        ], [("จบรอบและดูเวลา", "_plan_time_log")], family="practice")
    screens["_plan_time_first"]=screen("เวลาที่ฝึกรอบนี้", [
        ("stat", "1 นาที", "เวลาที่ลงมือฝึก", "ข้อมูลตัวอย่าง · ไม่รวมเวลาที่พัก"),
    ], [("ดูสัปดาห์ของฉัน", "_plan_week"), ("เริ่มรอบใหม่", TIMER)])
    for suffix,info in [("with_date","12–13 พฤศจิกายน"),("without_date","")]:
        screens["_plan_share_"+suffix]=screen("ตรวจการ์ดของฉัน", [
            ("art", "medal", "กลับมาฝึก 2 วันติด"),
            ("note",info or "ซ่อนวันที่ฝึกแล้ว","การ์ดไม่มีชื่อผู้เรียนหรือประวัติคำตอบ"),
            ("row","เก็บรูปการ์ด","ดูขั้นตอนบันทึกภาพ","_plan_card_saved"),
        ], [("ดูตัวอย่างการแชร์","_plan_share_preview"),("ยกเลิก",MOTIVE)])
    for slug,verb,dest in [("read","อ่านเรื่องสั้น","cefr_article_reader_screen"),("speak","ฟังแล้วพูดตาม","shadowing_challenge_screen")]:
        screens["_plan_pref_"+slug]=screen("วิธีเรียนที่เลือก", [
            ("lines", "ฝึกเพื่อใช้ตอนเดินทาง", verb,"เริ่มจากประโยคที่ใช้ในสถานีรถไฟ"),
        ], [("ลองฝึกแบบนี้",dest),("เปลี่ยนวิธีฝึก","_plan_pref_method")])


def render(d):
    """Give the contextual companion and the shareable card their own compositions."""
    friend = d.key in ("_plan_friend", "_plan_still")
    if not friend and d.key not in (SHARE, "_plan_share_with_date", "_plan_share_without_date"):
        return False
    d.back()
    _, title, _, _, _, _ = d.screens[d.key]
    d.text(24, 100, title, 30, d.ink, True)
    panel = d.add(d.frame, "frame", "เพื่อนฝึก" if friend else "การ์ดของฉัน",
                  24, 176, 342, 238, "#283954" if friend else "#343C91", children=[],
                  corners={"radii":[16]*4,"smoothing":0})
    if friend:
        d.text(18, 15, "เพื่อนฝึก · นกฮูกน้อย", 16, "#FFFFFF", True, 296, panel)
        for cx in (47, 76):
            d.box(cx, 92, 42, 49, "#FFE09B", 19, panel, "ปีกนกฮูก")
        d.box(53, 69, 65, 75, "#F5CB7C", 25, panel, "ตัวนกฮูก")
        for cx in (57, 88):
            d.box(cx, 78, 25, 25, "#FFFFFF", 12, panel, "ตานกฮูก")
            d.box(cx+9, 84, 8, 11, "#283954", 4, panel, "ตาดำ")
        d.box(78, 103, 11, 7, "#835A38", 3, panel, "จะงอยปาก")
        d.text(143, 82, "สถานีมีหลาย", 23, "#FFFFFF", True, 185, panel)
        d.text(143, 119, "ชานชาลา", 28, "#FFE09B", True, 185, panel)
        d.text(19, 185, "ภาพนิ่ง" if d.key=="_plan_still" else "คำใบ้เมื่อเลือก station แทน platform", 16, "#FFFFFF", False, 303, panel)
        d.text(24, 460, "ลองนึกตอนรอรถไฟ", 22, d.ink, True)
        d.text(24, 507, "Wait on platform two.", 22, d.ink)
        d.text(24, 551, "รอที่ชานชาลาสอง", 17, d.sub)
        links=[("เติมคำในประโยค","fill_in_the_blanks_screen"),
               ("กลับไปปรับการอ่าน" if d.key=="_plan_still" else "ปรับการแสดงผล",ACCESS)]
    else:
        d.art(panel, 136, 22, "medal", 1.1, "#FFE09B", "#343C91")
        d.text(42, 107, "กลับมาฝึก 2 วันติด", 30, "#FFFFFF", True, 270, panel)
        show_date=d.key=="_plan_share_with_date"
        d.text(78, 172, "12–13 พฤศจิกายน" if show_date else "LexiQuest", 17, "#FFE09B", True, 206, panel)
        d.text(24, 458, "ข้อมูลที่เห็นบนการ์ด", 22, d.ink, True)
        d.text(24, 506, "แสดงวันที่ฝึก" if show_date else "ซ่อนวันที่ฝึก", 18, d.ink)
        d.text(24, 544, "ชื่อผู้เรียนและคำที่ตอบผิดจะถูกซ่อนไว้", 16, d.sub)
        links=[("แสดงวันที่ฝึก","_plan_share_with_date"),("ซ่อนวันที่ฝึก","_plan_share_without_date"),("ยกเลิก",MOTIVE)] if d.key==SHARE else [
            ("ดูตัวอย่างการแชร์","_share_with_date" if show_date else "_plan_share_preview"),("ตัวอย่างการเก็บรูปการ์ด","_plan_card_saved"),("ยกเลิก",MOTIVE)]
    for i,(label,dest) in enumerate(links):
        n=d.link(24,608+i*62,342,50,label,dest,"#3942AD" if i==0 else "#EBEDF9",10)
        d.text(16,10,label,18,"#FFFFFF" if i==0 else d.ink,True,310,n)
    return True
