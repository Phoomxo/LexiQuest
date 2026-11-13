"""Learner tasks for f31–f44. Each witness is visible in the presentation."""
from finish_routes_b import page
import focused_account
import learn_home

HOME = "choose_mode_screen"
PROGRESS = "mastery_dashboard_screen"
ACCOUNT = "profile_settings_screen"
SETTINGS = "setting_screen"
BADGES = "achievements_screen"
SHOP = "shop_page"
THEME = "appearance_settings_screen"
HISTORY = "_history"
QUEUE = "_local_status"
FILES = "_offline_manager"
SOURCE = "_plan_pref"
PROFILE = "_plan_profile"
ACCESS = "_plan_access"
PRACTICE = "select_category_for_quiz"
REVIEW = "srs_flashcards_screen"
PLAN = [PROGRESS, "_plan_studio"]
MOTIVE = PLAN + ["_motivation_studio"]
DISPLAY = [ACCOUNT, SETTINGS, THEME]
LOCAL = [ACCOUNT, SETTINGS, QUEUE]

TASKS = {
    31: ("ดูวันที่ได้รับตราและเงื่อนไขของตราถัดไป", [PROGRESS, BADGES, "_badge_detail", BADGES],
         "_badge_detail", "10 พฤศจิกายน · จบรอบแรก", "ใช้วันเวลาและประวัติฝึกตัวอย่าง วันที่จริงต้องมาจากเหตุการณ์ปลดล็อก"),
    32: ("ลองธีมมหาสมุทร ตรวจราคา แลกแล้วเปิดใช้", [ACCOUNT, BADGES, SHOP, "_ocean_try", "_ocean_buy", "_ocean_owned", "_ocean_used", "_shop_after", BADGES],
         "_shop_after", "ธีมมหาสมุทร · กำลังใช้", "ยอดเหรียญและการซื้อเป็นตัวอย่าง ต้องตรวจการเขียนซ้ำและการเปลี่ยนเจ้าของในแอป"),
    33: ("อ่านคำใบ้จากเพื่อนฝึกหลังจำคำไม่ได้ แล้วลองใหม่", [HOME, REVIEW, "_card_reveal", "_card_again", "_friend_recall", REVIEW, "_card_reveal", "_card_remembered", "_home_after_review"],
         "_friend_recall", "คุณเพิ่งเลือกว่ายังจำคำนี้ไม่ได้", "เพื่อนฝึกตอบเหตุการณ์ที่กำหนดไว้ รูปและคำใบ้หยุดนิ่งให้อ่านจนจบ"),
    34: ("ซ่อนวันที่บนการ์ด ดูภาพก่อนแชร์ แล้วกลับไปที่ภารกิจ", MOTIVE + ["_plan_share", "_plan_share_without_date", "_plan_share_preview", "_motivation_studio"],
         "_plan_share_preview", "ซ่อนวันที่ฝึกแล้ว", "แสดงภาพก่อนส่งและยกเลิกได้ การบันทึกไฟล์และเลือกแอปปลายทางต้องตรวจบนอุปกรณ์"),
    35: ("ตั้งเป้าหมายครั้งแรก เลือกอ่านเรื่องเดินทาง แล้วเริ่มบทเรียน", [ACCOUNT, "login_screen", "_account_signed_in", "_plan_preferences", "_plan_pref_time", "_plan_pref_method", "_plan_pref_read", "_article_from_method", "_plan_pref_read"],
         "_article_from_method", "Her friend is on platform two.", "ใช้บัญชีและเป้าหมายตัวอย่าง ผู้เรียนกดข้ามคำถามเพื่อเลือกชุดคำเองได้"),
    36: ("เปลี่ยนวิธีฝึกแล้วเปิดโปรไฟล์ซ้ำเพื่อตรวจค่า", PLAN + [SOURCE, PROFILE, "_plan_pref_method", "_plan_pref_speak", "_profile_speaking", "_preferences_speaking", "_profile_speaking", "_preferences_speaking"],
         "_profile_speaking", "วิธีที่เลือก · ฟังแล้วพูดตาม", "การเปลี่ยนแสดงในโปรไฟล์ตัวอย่าง ต้องตรวจการคงค่าหลังปิดแอป"),
    37: ("ใช้คำแนะนำหลังตอบผิดแล้วลองใช้คำเดิมในประโยคใหม่", [HOME, PRACTICE, "quiz_screen", "_quiz_station", "score_screen", "weakness_clinic_screen", "fill_in_the_blanks_screen", "_fill_right", HOME],
         "_fill_right", "The train is at platform two.", "แนะนำจากข้อผิดในสถานการณ์นี้ การจัดลำดับจากประวัติผู้เรียนหลายรอบต้องทดสอบกับข้อมูลในแอป"),
    38: ("อ่านบัตรตัวใหญ่แบบไม่จับเวลาแล้วเปิดความหมาย", DISPLAY + [ACCESS, "_plan_large", "_large_revealed", ACCESS, THEME],
         "_large_revealed", "ชานชาลา", "ตัวอย่างนี้ใช้ข้อความแทนสีและให้เปิดเฉลยเอง การขยายตามระบบ 200% กับ TalkBack ต้องตรวจบนอุปกรณ์"),
    39: ("เลือกสีตามเครื่องและลดการเคลื่อนไหว ดูบัตรก่อนกลับ", DISPLAY + ["_display_system", "_display_quiet", "_display_kept", SETTINGS],
         "_display_kept", "ตามอุปกรณ์ · ลดการเคลื่อนไหวแล้ว", "ภาพตัวอย่างใช้ค่าระบบแบบสว่าง ต้องตรวจการสลับสีตามเครื่องและการคงค่าจริง"),
    40: ("เปิดประวัติระหว่างออฟไลน์ แล้วตรวจรายการหลังส่งอีกครั้ง", LOCAL + ["_queue_offline", "_history_offline", "_queue_offline", "_queue_retry", "_queue_synced", SETTINGS],
         "_queue_synced", "0 รายการรอส่ง", "ตัวอย่างแสดงคิวและผลจัดการข้อมูลต่างเวอร์ชัน การส่งจากเครื่องจริงต้องตรวจแยก"),
    41: ("ดูว่าเครื่องมือนี้ใช้ได้แค่ไหน แล้วฝึกคำโดยไม่ใช้ไมค์", LOCAL + [FILES, "_availability", "_limited_voice", "_type_instead", "_typed_answer", "_availability", FILES],
         "_typed_answer", "station · สถานี", "ตัวอย่างเมนูตามสถานะ enabled/limited รายการ hidden ต้องตรวจการไม่แสดงผลตามรุ่นใน Flutter"),
    42: ("ทำงานที่ได้รับเสร็จแล้วเปิดดูอีกครั้งจากหน้าฝึกภาษา", [HOME, "_today_jobs", "_assigned_word", "_assigned_reveal", "_today_jobs_done", "_today_after_assignment", "_today_jobs_done", "_today_after_assignment"],
         "_today_jobs_done", "งานที่ได้รับ · เสร็จแล้ว", "งานที่ได้รับและคิวถึงกำหนดเป็นคนละรายการตัวอย่าง การจัดลำดับจริงขึ้นกับเจ้าของและกำหนดเวลา"),
    43: ("เปิดผลรอบเดิมแล้วฝึกข้อที่พลาดเป็นรอบใหม่", [PROGRESS, HISTORY, "_history_today", "_replay_word", "_replay_result", "_history_replayed", "_history_prior_attempt", "_history_replayed", PROGRESS],
         "_history_replayed", "รอบเดิม · 0 จาก 1 ข้อ", "ต้นแบบแยกรอบเดิมกับรอบฝึกซ้ำ ต้องตรวจ session ID และเวอร์ชันเนื้อหาที่ใช้จริงในแอป"),
    44: ("ตรวจและซ่อมชุดกล้อง ลบไฟล์ แล้วตรวจว่าประวัติยังอยู่", LOCAL + [FILES, "_file_status", "_file_issue", "_file_ready", "_file_remove", "_file_removed", "_file_history", "_file_removed", FILES],
         "_file_history", "ประวัติการฝึกยังอยู่บนเครื่อง", "ใช้ชื่อรุ่นและขนาดจาก manifest ต้นแบบจำลองการดาวน์โหลด ตรวจไฟล์ ซ่อมและลบ"),
}


def row(title, detail, dest):
    return ("row", title, detail, dest)


def extend(s, key, blocks=(), buttons=()):
    family, title, sub, old, actions, tab = s[key]
    s[key] = family, title, sub, [*old, *blocks], [*actions, *buttons], tab


def install(s):
    def screen(key, title, section, blocks, *actions):
        s[key] = page("list", title, section, blocks, *actions)

    screen("_badge_detail", "ตราจากการฝึก", "ของสะสม · ประวัติของฉัน", [
        ("stat", "1 ตรา", "ที่ได้รับจากการฝึก", "10 พฤศจิกายน · จบรอบแรก"),
        ("lines", "ตราแรก · ได้รับแล้ว", "เรียนจบรอบแรก", "ฝึกเลือกความหมายจบหนึ่งรอบ"),
        ("lines", "ตราถัดไป · ยังไม่ได้รับ", "ตอบถูกครบทั้งรอบ", "เลือกคำแปลถูกทุกข้อในรอบเดียว")], ("กลับไปดูของสะสม", "@back"))
    screen("_ocean_try", "ลองธีมมหาสมุทร", "ร้านของตกแต่ง · ยังไม่มีธีมนี้", [
        ("quote", "ตัวอย่างบัตรคำ", "ocean", "มหาสมุทร"), ("note", "ราคา 80 เหรียญ", "คุณมี 140 เหรียญ")],
        ("ดูยอดก่อนแลก", "_ocean_buy"), ("เก็บธีมเดิม", SHOP))
    screen("_ocean_buy", "แลกธีมมหาสมุทรไหม", "ตรวจยอดก่อนยืนยัน", [
        ("stat", "80 เหรียญ", "ที่ใช้แลก", "140 − 80 = 60 เหรียญ"),
        ("note", "ใช้แต่งหน้าฝึกได้หลังแลก", "เปลี่ยนกลับไปใช้ธีมเดิมได้")],
        ("ยืนยันแลก 80 เหรียญ", "_ocean_owned"), ("ยกเลิก", SHOP))
    screen("_ocean_owned", "ได้ธีมมหาสมุทรแล้ว", "ของสะสม · เหลือ 60 เหรียญ", [
        ("quote", "ธีมที่มีในคลัง", "ocean", "พร้อมใช้กับหน้าฝึก")], ("ใช้ธีมนี้", "_ocean_used"), ("เก็บไว้ก่อน", "_shop_owned"))
    for key, status in [("_shop_owned", "มีแล้ว"), ("_shop_after", "กำลังใช้")]:
        screen(key, "ร้านของตกแต่ง", "เหรียญที่มี · 60 เหรียญ", [
            row("ธีมมหาสมุทร · "+status, "อยู่ในของสะสมแล้ว", "_ocean_used"),
            row("ดาบนักไต่ระดับ", "120 เหรียญ · ยังไม่มี", "_shop_short")], ("กลับไปดูของสะสม", BADGES))
    screen("_shop_short", "เหรียญยังไม่พอ", "ดาบนักไต่ระดับ", [
        ("stat", "60 เหรียญ", "ที่ยังขาด", "ราคา 120 เหรียญ · คุณมี 60 เหรียญ")], ("กลับไปที่ร้าน", "@back"))
    screen("_ocean_used", "ใช้ธีมมหาสมุทรแล้ว", "ตัวอย่างหน้าฝึก", [
        ("quote", "บัตรคำในธีมมหาสมุทร", "ocean", "มหาสมุทร")], ("กลับไปที่ร้าน", "_shop_after"))
    extend(s, "_card_again", buttons=[("ดูคำใบ้จากเพื่อนฝึก", "_friend_recall")])
    screen("_friend_recall", "เพื่อนฝึกช่วยจำ", "คุณเพิ่งเลือกว่ายังจำคำนี้ไม่ได้", [
        ("quote", "ลองนึกภาพตอนรอรถไฟ", "สถานีหนึ่งมีหลายชานชาลา", "station คือสถานี ส่วน platform คือชานชาลา"),
        ("note", "คำใบ้จะอยู่ตรงนี้จนกว่าจะพร้อม", "กลับไปลองนึกคำเดิมได้อีกครั้ง")],
        ("ลองทบทวนคำนี้อีกครั้ง", REVIEW), ("กลับไปดูผล", "_card_again"))
    for key, date, origin in [("_plan_share_preview", "ซ่อนวันที่ฝึกแล้ว", "_plan_share_without_date"),
                              ("_share_with_date", "12–13 พฤศจิกายน", "_plan_share_with_date")]:
        screen(key, "ตรวจภาพก่อนแชร์", "กลับมาฝึก 2 วันติด", [
            ("art", "medal", "กลับมาฝึก 2 วันติด"), ("lines", "บนการ์ดใบนี้", date, "ซ่อนชื่อ บัญชี และคำตอบของผู้เรียน"),
            ("note", "ยังไม่ได้ส่งให้ใคร", "บนอุปกรณ์จะเลือกแอปที่จะส่งต่อได้")],
            ("กลับไปแก้การ์ด", origin), ("จบการดูตัวอย่าง", "_motivation_studio"))
    extend(s, "_account_signed_in", blocks=[row("ตั้งวิธีเรียนครั้งแรก", "เลือกเป้าหมาย เวลา และแบบฝึกที่สนใจ", "_plan_preferences")])
    extend(s, "_plan_pref_speak", buttons=[("ใช้วิธีนี้กับโปรไฟล์", "_profile_speaking")])
    screen("_profile_speaking", "โปรไฟล์การเรียน", "บันทึกวิธีฝึกแล้ว", [
        ("lines", "เป้าหมายและเวลา", "ใช้ภาษาอังกฤษเวลาเดินทาง", "ครั้งละ 5 นาที"),
        ("quote", "วิธีที่เลือก · ฟังแล้วพูดตาม", "The train is at platform two.", "ใช้คำจากการเดินทางแนะนำแบบฝึกฟัง")],
        ("กลับไปปรับวิธีเรียน", "_preferences_speaking"), ("เปลี่ยนวิธีฝึก", "_plan_pref_method"))
    screen("_preferences_speaking", "ปรับวิธีเรียน", "เลือกวิธีฝึกแล้ว", [
        row("โปรไฟล์การเรียน", "เดินทาง · 5 นาที · ฟังแล้วพูดตาม", "_profile_speaking"),
        row("การอ่านและการเคลื่อนไหว", "ปรับข้อความและการตอบ", ACCESS)], ("กลับไปดูแผนฝึก", "_plan_studio"))
    extend(s, THEME, blocks=[row("สีตามอุปกรณ์และภาพเคลื่อนไหว", "ลองสีตามเครื่องและเลือกใช้ภาพนิ่ง", "_display_system"),
                              row("ข้อความและวิธีตอบ", "ปรับการอ่านและฝึกแบบไม่ใช้เสียง", ACCESS)])
    extend(s, ACCESS, buttons=[("กลับไปที่การแสดงผล", THEME)])
    s["_plan_large"] = page("practice", "บัตรคำตัวใหญ่", "การเดินทาง · ไม่จับเวลา", [
        ("hero", "ลองนึกความหมาย", "platform", "คำนี้หมายถึงอะไร")],
        ("เปิดความหมาย", "_large_revealed"), ("กลับไปปรับการอ่าน", ACCESS))
    screen("_large_revealed", "ความหมายของคำ", "การเดินทาง · ไม่จับเวลา", [
        ("hero", "platform", "ชานชาลา", "Wait on platform two.")], ("กลับไปปรับการอ่าน", ACCESS))
    for key, title, status, actions in [
            ("_display_system", "สีตามอุปกรณ์", "โทรศัพท์ใช้โหมดสว่าง", [("ลดการเคลื่อนไหว", "_display_quiet"), ("ดูโหมดมืด", "_appearance_dark"), ("กลับไปเลือกสี", THEME)]),
            ("_display_quiet", "ลดการเคลื่อนไหว", "แสดงคำใบ้เป็นภาพนิ่งจนกว่าจะกดต่อ", [("ใช้การตั้งค่านี้", "_display_kept"), ("เปลี่ยนสีของหน้าจอ", "_display_system")]),
            ("_display_kept", "การแสดงผล", "ตามอุปกรณ์ · ลดการเคลื่อนไหวแล้ว", [("ปรับสีหรือการเคลื่อนไหว", "_display_system"), ("กลับไปที่ตั้งค่า", SETTINGS)])]:
        screen(key, title, status, [("quote", "ตัวอย่างบัตรคำ", "platform", "ชานชาลา")], *actions)
    extend(s, QUEUE, blocks=[row("ตรวจคิวที่รอส่ง", "2 รายการ · รอเชื่อมต่ออินเทอร์เน็ต", "_queue_offline")])
    screen("_queue_offline", "ยังไม่ได้เชื่อมต่อ", "บันทึกการเรียนไว้บนเครื่องแล้ว", [
        ("stat", "2 รายการ", "รอส่งเมื่อเชื่อมต่อ", "ผลเลือกความหมาย · คำศัพท์ในชุดการเดินทาง"),
        row("เปิดประวัติบนเครื่อง", "ดูผลรอบล่าสุดได้ทันที", "_history_offline")],
        ("ลองเชื่อมต่ออีกครั้ง", "_queue_retry"), ("กลับไปดูข้อมูลในเครื่อง", QUEUE))
    screen("_history_offline", "ประวัติบนเครื่อง", "ขณะออฟไลน์", [
        ("lines", "วันนี้ · เลือกความหมาย", "ตอบถูก 0 จาก 1 ข้อ", "platform · ครั้งก่อนเลือกสถานี")], ("กลับไปดูคิว", "_queue_offline"))
    screen("_queue_retry", "เชื่อมต่อแล้ว", "ตรวจรายการค้างส่ง", [
        ("lines", "ประวัติรอบฝึก", "ส่งสำเร็จ 1 รายการ", "ตรวจพบคำศัพท์ต่างเวอร์ชัน 1 รายการ"),
        ("note", "ประวัติการฝึกยังอยู่", "ตรวจผลหลังเทียบรุ่นของคำศัพท์")], ("ดูผลการซิงก์", "_queue_synced"))
    screen("_queue_synced", "ส่งรายการครบแล้ว", "ข้อมูลในเครื่อง", [
        ("stat", "0 รายการรอส่ง", "เชื่อมต่อแล้ว", "บันทึกผลความต่างของรุ่นคำศัพท์ไว้ 1 รายการ")], ("กลับไปที่ตั้งค่า", SETTINGS))
    extend(s, "_availability", blocks=[row("ฝึกเมื่อใช้ไมค์ไม่ได้", "เลือกตอบคำศัพท์แทนการอัดเสียง", "_limited_voice")],
           buttons=[("กลับไปดูเนื้อหาในเครื่อง", FILES)])
    screen("_limited_voice", "ฝึกได้โดยไม่ใช้ไมค์", "เครื่องมือที่ใช้ได้ในรุ่นนี้", [
        ("note", "การอัดเสียงต้องได้รับสิทธิ์ไมค์", "ยังตอบคำศัพท์โดยไม่ใช้เสียงได้")],
        ("ลองตอบโดยไม่ใช้เสียง", "_type_instead"), ("กลับไปดูเครื่องมือ", "_availability"))
    screen("_type_instead", "คำไหนหมายถึงสถานี", "เลือกคำตอบ · ไม่ใช้ไมค์", [
        ("choice", "station", "_typed_answer"), ("choice", "platform", "_silent_wrong")])
    screen("_silent_wrong", "ลองแยกสองคำนี้", "คำที่เลือก · platform", [
        ("quote", "platform คือ ชานชาลา", "สถานีหนึ่งมีหลายชานชาลา", "ลองเลือกคำที่หมายถึงสถานีอีกครั้ง")], ("กลับไปเลือกคำ", "_type_instead"))
    screen("_typed_answer", "เลือกคำได้ถูกต้อง", "ฝึกโดยไม่ใช้เสียง", [
        ("quote", "คำตอบของคุณ", "station · สถานี", "Meet me at the station.")], ("กลับไปดูเครื่องมือ", "_availability"))
    screen("_today_jobs", "งานที่ได้รับ", "รอทำ 1 งาน", [
        row("ทบทวนคำว่า ticket", "ชุดการเดินทาง · 1 คำ", "_assigned_word")], ("กลับหน้าฝึกภาษา", HOME))
    screen("_assigned_word", "นึกความหมาย", "งานที่ได้รับ · 1 จาก 1 คำ", [
        ("hero", "คำศัพท์", "ticket", "สิ่งที่ต้องซื้อก่อนขึ้นรถไฟ")], ("เปิดความหมาย", "_assigned_reveal"), ("พักแล้วกลับไปดูงาน", "_today_jobs"))
    screen("_assigned_reveal", "ตรวจความหมาย", "งานที่ได้รับ · 1 จาก 1 คำ", [
        ("quote", "ticket · ตั๋ว", "One ticket, please.", "ขอตั๋วหนึ่งใบ")], ("จบงานนี้", "_today_jobs_done"), ("ลองนึกอีกครั้ง", "_assigned_word"))
    screen("_today_jobs_done", "งานที่ได้รับ", "ทำเสร็จ 1 งาน", [
        ("lines", "งานที่ได้รับ · เสร็จแล้ว", "ทบทวนคำว่า ticket", "ชุดการเดินทาง · 1 คำ")], ("กลับหน้าฝึกภาษา", "_today_after_assignment"))
    for state in learn_home.STATES:
        s[state] = s[HOME]
    history_cards(s)
    offline_files(s)


def history_cards(s):
    family, title, sub, rows, actions, tab = s[HISTORY]
    old_rounds = [
        ("_history_today", "วันนี้", "0 จาก 1 ข้อ", "ครั้งก่อนเลือกสถานี"),
        ("_history_yesterday", "เมื่อวาน", "5 จาก 6 ข้อ", "สรุปรอบเลือกความหมาย"),
        ("_history_prior", "3 วันก่อน", "3 จาก 5 ข้อ", "สรุปรอบเลือกความหมาย")]
    rows = list(rows)
    for i, (key, when, score, detail) in enumerate(old_rounds):
        assert rows[i][0]=="row" and rows[i][1].startswith(when), rows[i]
        rows[i] = (*rows[i][:-1], key)
        buttons = [("กลับไปดูประวัติ", HISTORY)]
        if i==0:
            buttons.insert(0, ("ฝึกคำที่พลาดเป็นรอบใหม่", "_replay_word"))
        s[key] = page("result", "ผลจากรอบเดิม", when+" · เลือกความหมาย", [
            ("stat", score, "ข้อที่ตอบถูก", detail)], *buttons)
    s[HISTORY] = family, title, sub, rows, [*actions, ("กลับไปดูความก้าวหน้า", PROGRESS)], tab
    s["_replay_word"] = page("practice", "ลองคำนี้อีกครั้ง", "รอบใหม่ · เลือกความหมาย", [
        ("hero", "คำไหนตรงกับคำนี้", "platform", "ผลของรอบเดิมจะอยู่ในประวัติ"),
        ("choice", "ชานชาลา", "_replay_result"), ("choice", "สถานี", "_replay_wrong")])
    for key, right, target in [("_replay_result", True, "_history_replayed"), ("_replay_wrong", False, "_history_missed")]:
        score = "1 จาก 1 ข้อ" if right else "0 จาก 1 ข้อ"
        s[key] = page("result", "ผลรอบที่ลองใหม่", "เลือกความหมาย", [
            ("stat", score, "ข้อที่ตอบถูก", "platform แปลว่า ชานชาลา")], ("กลับไปดูทั้งสองรอบ", target))
        old = "_history_prior_attempt" if right else "_history_prior_miss"
        s[target] = page("list", "ประวัติการฝึก", "วันนี้ · ชุดการเดินทาง", [
            row("รอบที่ลองใหม่ · "+score, "ดูผลของรอบนี้", key),
            row("รอบเดิม · 0 จาก 1 ข้อ", "เปิดคำตอบเดิมได้", old)], ("กลับไปดูความก้าวหน้า", PROGRESS))
        s[old] = page("result", "ผลจากรอบเดิม", "วันนี้ · เลือกความหมาย", [
            ("stat", "0 จาก 1 ข้อ", "ผลก่อนฝึกซ้ำ", "ครั้งก่อนเลือกสถานี")], ("กลับไปดูทั้งสองรอบ", target))


def offline_files(s):
    version="1.0.224-quantized-metadata1"
    extend(s, FILES, blocks=[row("ชุดจำแนกภาพบนเครื่อง", "MobileNet · ตรวจรุ่น ซ่อม หรือลบไฟล์", "_file_status")])
    for key, title, note, commands in [
        ("_file_status", "ข้อมูลชุดจำแนกภาพ", "ตรวจว่าทุกไฟล์ตรงกับรุ่นที่ใช้",
         [("ตรวจไฟล์ในเครื่อง", "_file_issue"), ("กลับไปดูเนื้อหาออฟไลน์", FILES)]),
        ("_file_issue", "ไฟล์ตรวจสอบไม่ผ่าน", "ไฟล์ในเครื่องไม่ตรงกับรุ่นที่ระบุ",
         [("ดาวน์โหลดรุ่นเดิมมาซ่อม", "_file_ready"), ("กลับไปดูชุดข้อมูล", "_file_status")]),
        ("_file_ready", "พร้อมใช้กล้องออฟไลน์", "ตรวจไฟล์แล้ว · ใช้รุ่นนี้สำหรับสแกน",
         [("เอาไฟล์ออกจากเครื่อง", "_file_remove"), ("กลับไปดูเนื้อหาออฟไลน์", FILES)]),
        ("_file_remove", "เอาชุดกล้องออกไหม", "ต้องดาวน์โหลดใหม่ก่อนใช้กล้องออฟไลน์",
         [("เอาเฉพาะชุดกล้องออก", "_file_removed"), ("เก็บไว้บนเครื่อง", "_file_ready")]),
        ("_file_removed", "เอาไฟล์ชุดกล้องออกแล้ว", "คำที่เก็บและประวัติการฝึกยังอยู่",
         [("เปิดประวัติการฝึก", "_file_history"), ("ดาวน์โหลดชุดกล้องอีกครั้ง", "_file_ready"), ("กลับไปดูเนื้อหาออฟไลน์", FILES)])]:
        s[key] = page("settings", title, "ชุดจำแนกภาพ MobileNet", [
            ("lines", "รุ่นที่กำหนดสำหรับเครื่องนี้", version, "4.29 MB · ไฟล์ชุดจำแนกภาพ"),
            ("note", note, "เอาออกได้เฉพาะไฟล์ที่ใช้จำแนกภาพ" if key=="_file_remove" else "การฝึกคำในคลังเปิดได้ตามปกติ")], *commands)
    s["_file_history"] = page("list", "ประวัติหลังเอาไฟล์ออก", "อ่านจากเครื่องนี้", [
        ("lines", "ประวัติการฝึกยังอยู่บนเครื่อง", "วันนี้ · ตอบถูก 0 จาก 1 ข้อ", "ชุดการเดินทาง · เลือกความหมาย")],
        ("กลับไปดูชุดกล้อง", "_file_removed"))


def render(d):
    if d.key==BADGES:
        focused_account.render(d)
        focused_account.pill(d, 24, 433, 342, "ดูวันที่ได้รับและเงื่อนไข", "_badge_detail")
    elif d.key==SHOP:
        focused_account.render(d)
        focused_account.pill(d, 24, 540, 342, "ลองธีมมหาสมุทร · 80 เหรียญ", "_ocean_try")
    elif d.key in learn_home.STATES:
        learn_home.render(d, *learn_home.STATES[d.key])
    elif d.key in ("_plan_large", "_large_revealed"):
        d.back()
        d.text(24, 96, "การเดินทาง · ไม่จับเวลา", 17, d.sub)
        d.text(24, 188, "ลองนึกความหมาย" if d.key=="_plan_large" else "ตรวจคำที่นึกไว้", 26, d.ink, True)
        d.box(24, 266, 342, 221, "#EBEDF9", 14)
        d.text(43, 290, "platform", 48, d.ink, True, 295)
        d.text(43, 377, "คำนี้หมายถึงอะไร" if d.key=="_plan_large" else "ชานชาลา", 42, d.ink, True, 302)
        if d.key=="_plan_large":focused_account.pill(d, 24, 537, 342, "เปิดความหมาย", "_large_revealed", True)
        focused_account.pill(d, 24, 609, 342, "กลับไปปรับการอ่าน", ACCESS)
    elif d.key in ("_ocean_try", "_ocean_used"):
        d.back()
        _,title,sub,_,buttons,_=d.screens[d.key]
        d.text(24, 85, title, 30, d.ink, True)
        d.text(24, 147, sub, 17, d.sub)
        d.box(24, 215, 342, 205, "#143E65", 15)
        d.text(46, 239, "บัตรคำในธีมมหาสมุทร", 17, "#BCDBF1")
        d.text(44, 280, "ocean", 44, "#FFFFFF", True)
        d.text(46, 354, "มหาสมุทร", 22, "#FFFFFF")
        d.text(24, 467, "ราคา 80 เหรียญ · คุณมี 140 เหรียญ" if d.key=="_ocean_try" else "เปิดใช้แล้ว · คงเหลือ 60 เหรียญ", 18, d.ink, True)
        for i,(name,target) in enumerate(buttons):
            focused_account.pill(d, 24, 550+i*62, 342, name, target, not i)
    else:
        return False
    return True
