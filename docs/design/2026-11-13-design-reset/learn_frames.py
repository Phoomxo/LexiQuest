"""Thai screen content and native navigation for the learning prototype."""

TODAY = "choose_mode_screen"
PRACTICE = "main_navigation_screen"
REVIEW = "srs_flashcards_screen"
QUIZ = "quiz_screen"
REPAIR = "weakness_clinic_screen"
READ = "cefr_article_reader_screen"
LEVEL = "cefr_selection_screen"

SCREENS = {
    TODAY: ("today", "ฝึกภาษา", "แผนฝึกของฉัน", [
        ("hero", "ถึงเวลาทบทวน", "1 คำ", "ลองนึกคำแปลก่อนเปิดดูคำตอบ"),
        ("row", "ฝึกต่อจากชุดเดิม", "การเดินทาง · station, platform", "select_category_for_quiz"),
        ("row", "อ่านเรื่องสั้น", "นัดกันที่สถานี · ประมาณ 1 นาที", READ),
    ], [("เริ่มทบทวน", REVIEW), ("เลือกแบบฝึกอื่น", PRACTICE)], "ฝึกภาษา"),

    PRACTICE: ("list", "เลือกวิธีฝึก", "ฝึกกับคำในคลัง", [
        ("row", "คำและความหมาย", "เลือกชุดคำ แล้วลองตอบคำแปล", "select_category_for_quiz"),
        ("row", "อ่านและแต่งประโยค", "อ่านเรื่องสั้นแล้วลองใช้คำในเรื่อง", LEVEL),
        ("row", "ฟังและพูด", "ฟังคำศัพท์ เขียนตามเสียง หรือพูดตาม", "_listening"),
        ("row", "เกมฝึกคำ", "เรียงตัวอักษร สะกดคำ หรือท้าสถิติเดิม", "_word_games"),
        ("row", "ฝึกจากข้อความของฉัน", "นำคำจากเรื่องที่กำลังอ่านมาฝึก", "source_practice_screen"),
    ], [], None),

    "select_category_for_quiz": ("list", "เลือกชุดคำ", "ฝึกคำและความหมาย", [
        ("row", "การเดินทาง", "ลองฝึกคำว่า platform", QUIZ),
        ("row", "คำที่ยังสับสน", "ฝึกซ้ำจากคำที่เคยตอบผิด", REPAIR),
        ("row", "จัดชุดคำของฉัน", "เพิ่มคำหรือรวบรวมคำไว้ฝึกด้วยกัน", "categories_page"),
    ], [], None),

    QUIZ: ("practice", "เลือกความหมาย", "การเดินทาง", [
        ("meter", "ข้อ 1 จาก 1", 1),
        ("hero", "คำนี้หมายถึงอะไร", "platform", "เลือกคำแปลที่ใช้ในสถานีรถไฟ"),
        ("choice", "สถานี", "_quiz_station"),
        ("choice", "ชานชาลา", "_quiz_right"),
        ("choice", "ตั๋ว", "_quiz_ticket"),
    ], [], None),

    "_quiz_right": ("practice", "ตอบถูกแล้ว", "การเดินทาง · ข้อ 1", [
        ("hero", "คำตอบของคุณ", "ชานชาลา", "platform คือบริเวณที่ยืนรอขึ้นรถไฟ"),
        ("quote", "ลองอ่านประโยคนี้", "Wait on platform two.", "รอที่ชานชาลาสอง"),
    ], [("ดูผลการฝึก", "_score_right")], None),

    "score_screen": ("result", "ผลการฝึกครั้งนี้", "เลือกความหมาย · การเดินทาง", [
        ("stat", "0 / 1", "ข้อที่ตอบถูก", "มีคำให้กลับมาฝึกอีกครั้ง"),
        ("row", "platform", "ชานชาลา · คำที่ตอบผิดในรอบนี้", REPAIR),
    ], [("ฝึกคำนี้อีกครั้ง", "fill_in_the_blanks_screen"), ("กลับหน้าฝึกภาษา", TODAY)], None),

    "_score_right": ("result", "ผลการฝึกครั้งนี้", "เลือกความหมาย · การเดินทาง", [
        ("stat", "1 / 1", "ข้อที่ตอบถูก", "คุณเลือกความหมายของ platform ได้"),
        ("quote", "ลองใช้คำนี้ต่อ", "Meet me on the platform.", "มาเจอกันที่ชานชาลา"),
    ], [("ลองเติมคำในประโยค", "fill_in_the_blanks_screen"), ("กลับหน้าฝึกภาษา", TODAY)], None),

    REVIEW: ("practice", "ทบทวนคำ", "การเดินทาง", [
        ("meter", "คำที่ 1 จาก 1", 1),
        ("hero", "ลองนึกความหมาย", "platform", "ที่สถานีรถไฟ คำนี้หมายถึงอะไร"),
        ("quote", "คำใบ้จากประโยค", "The train is at platform two.", "ลองนึกภาพตอนรอรถไฟ"),
    ], [("ดูคำแปล", "_card_reveal")], None),

    "_card_reveal": ("practice", "จำความหมายได้ไหม", "ทบทวนคำ · การเดินทาง", [
        ("hero", "platform", "ชานชาลา", "บริเวณสำหรับรอขึ้นหรือลงรถไฟ"),
        ("quote", "ประโยคเดิม", "The train is at platform two.", "รถไฟจอดอยู่ที่ชานชาลาสอง"),
    ], [("จำได้แล้ว", "_card_remembered"), ("ยังจำไม่ได้", "_card_again")], None),

    "_card_remembered": ("result", "ทบทวนครบแล้ว", "การเดินทาง", [
        ("stat", "1 คำ", "ที่คุณจำความหมายได้", "platform · ชานชาลา"),
        ("row", "ลองใช้ในประโยค", "เลือกคำให้ตรงกับสถานการณ์", "fill_in_the_blanks_screen"),
    ], [("กลับหน้าฝึกภาษา", TODAY)], None),

    "_card_again": ("result", "ทบทวนครบแล้ว", "การเดินทาง", [
        ("hero", "คำที่อยากทบทวนอีก", "platform", "ชานชาลา"),
        ("quote", "ตัวช่วยจำ", "สถานีมีหลายชานชาลา", "station คือสถานี ส่วน platform คือชานชาลา"),
    ], [("ลองเติมคำนี้ในประโยค", "fill_in_the_blanks_screen"), ("กลับหน้าฝึกภาษา", TODAY)], None),

    REPAIR: ("list", "คำที่ยังสับสน", "จากประวัติการฝึก", [
        ("hero", "ครั้งล่าสุดที่เลือกความหมาย", "platform", "ครั้งก่อนเลือกคำแปลอื่นแทน ชานชาลา"),
        ("quote", "จำจากภาพของสถานที่", "We met at the station.", "เราเจอกันที่สถานี"),
        ("lines", "มองให้ใกล้ขึ้น", "We waited on the platform.", "เรารออยู่ที่ชานชาลา"),
    ], [("ลองเติมคำนี้ในประโยค", "fill_in_the_blanks_screen"), ("ถามผู้ช่วยเรื่องคำนี้", "ai_tutor_screen")], None),

    "mastery_dashboard_screen": ("result", "ความก้าวหน้า", "7 วันที่ผ่านมา", [
        ("stat", "8 / 12", "คำตอบที่ถูกต้อง", "จากการฝึกเลือกความหมาย 3 รอบ"),
        ("meter", "ตอบถูก 8 จาก 12 ข้อ", 8/12),
        ("row", "คำที่ยังสับสน", "platform · เคยเลือกคำแปลผิด", REPAIR),
        ("row", "ประวัติการฝึก", "ดูผลตามวันที่ฝึก", "_history"),
        ("row", "รางวัลของฉัน", "ดูสิ่งที่ได้รับจากการฝึก", "achievements_screen"),
    ], [], "ความก้าวหน้า"),

    "_history": ("list", "ประวัติการฝึก", "7 วันที่ผ่านมา · ตัวอย่าง", [
        ("row", "วันนี้ · เลือกความหมาย", "การเดินทาง · ตอบถูก 0 จาก 1 ข้อ", "score_screen"),
        ("row", "เมื่อวาน · เลือกความหมาย", "ตอบถูก 5 จาก 6 ข้อ", None),
        ("row", "3 วันก่อน · เลือกความหมาย", "ตอบถูก 3 จาก 5 ข้อ", None),
        ("row", "ดูตัวอย่างกราฟ", "อ่านคำอธิบายและที่มาของข้อมูล", "thesis_chart_screen"),
    ], [], None),

    LEVEL: ("list", "เลือกบทอ่าน", "อ่านตามความยากที่ต้องการ", [
        ("row", "A1 · คำใกล้ตัว", "ซื้อบัตรโดยสาร · ประโยคสั้น", "_easy_reading"),
        ("row", "A2 · การเดินทาง", "นัดกันที่สถานี · 1 นาที", READ),
        ("row", "ยังเลือกไม่ถูก", "ลองตอบคำถามช่วยเลือกบทอ่าน", "cefr_diagnostic_test_screen"),
        ("row", "เส้นทางการเรียน", "ดูว่ามีบทเรียนตามลำดับหรือยัง", "learning_world_map_screen"),
    ], [], None),

    "_easy_reading": ("reader", "ซื้อตั๋วรถไฟ", "บทอ่าน A1 · การเดินทาง", [
        ("lines", "ที่ช่องขายตั๋ว", "One ticket, please.", "I pay and take my ticket."),
        ("quote", "ประโยคที่ใช้ได้ทันที", "One ticket, please.", "ขอตั๋วหนึ่งใบครับ"),
        ("row", "ลองอ่านอีกเรื่อง", "นัดกันที่สถานี · A2", READ),
    ], [("เลือกบทอ่านอื่น", LEVEL)], None),

    READ: ("reader", "นัดกันที่สถานี", "บทอ่าน A2 · การเดินทาง", [
        ("lines", "ก่อนรถไฟมา", "Mina arrives at the station.", "Her friend is on platform two."),
        ("lines", "ทั้งสองคนเจอกันที่ไหน", "She follows the signs.", "They meet on the platform."),
        ("row", "อ่านแล้วลองนึกคำ", "จำคำที่ใช้เรียกจุดรอรถไฟได้ไหม", "associative_reading_session_screen"),
    ], [("ฝึกคำจากเรื่องนี้", "associative_reading_session_screen")], None),

    "associative_reading_session_screen": ("reader", "นึกคำจากเรื่อง", "นัดกันที่สถานี · หลังอ่าน", [
        ("quote", "นึกย้อนถึงตอนจบ", "They meet on the ____.", "ทั้งสองมาเจอกันที่ชานชาลา"),
        ("choice", "platform", "_reading_write"),
        ("choice", "ticket", "_reading_hint"),
    ], [], None),

    "_reading_hint": ("reader", "ลองนึกอีกครั้ง", "นัดกันที่สถานี", [
        ("quote", "ทบทวนเหตุการณ์", "Her friend is on platform two.", "เพื่อนรออยู่ที่ชานชาลาสอง"),
        ("note", "ticket หมายถึงตั๋ว", "คำที่ต้องเติมคือสถานที่ที่ทั้งสองคนเจอกัน"),
    ], [("กลับไปตอบ", "associative_reading_session_screen")], None),

    "_reading_write": ("reader", "ลองแต่งประโยค", "คำจากเรื่อง · platform", [
        ("quote", "จากบทอ่าน", "They meet on the platform.", "ลองเปลี่ยนสถานการณ์เป็นของตัวเอง"),
        ("field", "ประโยคตัวอย่างของฉัน", "I am on platform three."),
    ], [("ดูสรุปการอ่าน", "_reading_done")], None),

    "_reading_done": ("result", "ผลการฝึกครั้งนี้", "อ่านและใช้คำ · นัดกันที่สถานี", [
        ("stat", "1 คำ", "ที่นึกได้จากเรื่อง", "platform · ชานชาลา"),
        ("quote", "ประโยคที่ลองแต่ง", "I am on platform three.", "ฉันอยู่ที่ชานชาลาสาม"),
    ], [("อ่านเรื่องอื่น", LEVEL), ("กลับหน้าฝึกภาษา", TODAY)], None),

    "cefr_diagnostic_test_screen": ("practice", "ลองเลือกคำ", "ช่วยเลือกบทอ่าน", [
        ("hero", "คำไหนใกล้เคียงกับคำนี้", "journey", "ใช้คำตอบข้อนี้ช่วยเลือกเรื่องที่จะลองอ่าน"),
        ("choice", "trip", "_suggest_a2"),
        ("choice", "food", "_suggest_a1"),
    ], [], None),

    "_suggest_a2": ("reader", "ลองเริ่มจากเรื่องนี้", "คำแนะนำจากข้อที่ลองตอบ", [
        ("quote", "journey และ trip", "ทั้งสองคำหมายถึงการเดินทาง", "ลองอ่านเรื่องนัดกันที่สถานีต่อ"),
        ("row", "นัดกันที่สถานี", "บทอ่าน A2 · ประมาณ 1 นาที", READ),
    ], [("อ่านเรื่องนี้", READ), ("เลือกบทอื่นเอง", LEVEL)], None),

    "_suggest_a1": ("reader", "ลองเริ่มจากเรื่องสั้น", "คำแนะนำจากข้อที่ลองตอบ", [
        ("quote", "journey หมายถึงการเดินทาง", "ส่วน food หมายถึงอาหาร", "ลองอ่านบทสนทนาสั้นที่ช่องขายตั๋ว"),
    ], [("อ่านเรื่องซื้อตั๋วรถไฟ", "_easy_reading"), ("เลือกบทอื่นเอง", LEVEL)], None),

    "learning_world_map_screen": ("list", "เส้นทางการเรียน", "บทเรียนตามลำดับ", [
        ("art", "book", "ยังไม่มีเส้นทางการเรียนในเครื่องนี้"),
        ("note", "เลือกบทอ่านด้วยตัวเองได้", "เริ่มจากเนื้อหาที่สนใจ แล้วปรับความยากได้"),
    ], [("เลือกบทอ่าน", LEVEL)], None),

    "fill_in_the_blanks_screen": ("practice", "เติมคำในประโยค", "การเดินทาง · ฝึกใช้คำ", [
        ("quote", "เลือกคำที่หายไป", "The train is at ____ two.", "รถไฟจอดอยู่ที่ชานชาลาสอง"),
        ("choice", "platform", "_fill_right"),
        ("choice", "ticket", "_fill_wrong"),
    ], [], None),

    "_fill_right": ("result", "เติมคำได้ถูกต้อง", "การเดินทาง · ฝึกใช้คำ", [
        ("quote", "ประโยคที่เติมแล้ว", "The train is at platform two.", "รถไฟจอดอยู่ที่ชานชาลาสอง"),
        ("row", "เรียงประโยคด้วยตัวเอง", "ลองวางคำให้ได้ประโยคใหม่", "sentence_scramble_screen"),
    ], [("กลับหน้าฝึกภาษา", TODAY)], None),

    "_fill_wrong": ("practice", "ลองดูคำใบ้", "การเดินทาง · ฝึกใช้คำ", [
        ("hero", "คำที่เลือก", "ticket", "แปลว่า ตั๋ว"),
        ("quote", "นึกถึงที่ที่รถไฟจอด", "The train is at ____ two.", "คำที่ต้องใช้แปลว่า ชานชาลา"),
    ], [("ลองตอบอีกครั้ง", "fill_in_the_blanks_screen")], None),

    "_listening": ("audio", "ฟังและพูด", "ฝึกกับคำที่รู้จัก", [
        ("art", "wave", "ฟังเสียง แล้วลองพูดตาม"),
        ("row", "ฟังชุดคำ", "ฟังคำศัพท์ในชุดเดียวกันต่อเนื่อง", "smart_audio_playlist_screen"),
        ("row", "เขียนตามเสียง", "ฟังคำแล้วลองสะกด", "dictation_quiz_screen"),
        ("row", "พูดตามประโยค", "ฟังต้นแบบแล้วลองพูดตาม", "shadowing_challenge_screen"),
        ("row", "ฝึกเสียงทีละคำ", "ดูคำอ่านและฟังเสียงตัวอย่าง", "phonetic_explorer_screen"),
    ], [], None),

    "_word_games": ("list", "เกมฝึกคำ", "การเดินทางและคำในคลัง", [
        ("row", "เรียงตัวอักษร", "ประกอบคำจากตัวอักษรที่สลับกัน", "word_scramble_screen"),
        ("row", "เรียงประโยค", "วางคำให้สื่อความหมาย", "sentence_scramble_screen"),
        ("row", "ท้าสถิติของฉัน", "ลองคำที่เคยพลาดอีกครั้ง", "ghost_shadow_duel_screen"),
        ("row", "ด่านสะกดคำ", "สะกดคำตามความหมายเพื่อผ่านด่าน", "boss_battle_screen"),
    ], [], None),

    "word_scramble_screen": ("practice", "เรียงตัวอักษร", "การเดินทาง · สะกดคำ", [
        ("hero", "คำใบ้", "ตั๋ว", "เติมตัวอักษรตัวสุดท้ายให้เป็นคำ"),
        ("quote", "คำที่เรียงไว้", "t i c k e _", "เลือกตัวอักษรที่ยังขาด"),
        ("choice", "t", "_spell_done"), ("choice", "s", "_spell_retry"),
    ], [], None),

    "_spell_done": ("result", "สะกดถูกแล้ว", "เรียงตัวอักษร", [
        ("hero", "คำที่ได้", "ticket", "ตั๋ว"),
        ("quote", "ลองอ่านประโยค", "I have a ticket.", "ฉันมีตั๋วหนึ่งใบ"),
    ], [("ลองเรียงประโยค", "sentence_scramble_screen"), ("เลือกเกมอื่น", "_word_games")], None),
    "_spell_retry": ("practice", "ลองอีกตัวหนึ่ง", "เรียงตัวอักษร", [
        ("quote", "คำว่า ticket", "ขึ้นต้นและลงท้ายด้วยตัวเดียวกัน", "ตัวสุดท้ายที่ต้องเติมคือ t"),
    ], [("กลับไปเติมตัวอักษร", "word_scramble_screen")], None),

    "sentence_scramble_screen": ("practice", "เรียงประโยค", "การเดินทาง · ตั๋วรถไฟ", [
        ("quote", "เรียงให้แปลว่า ฉันมีตั๋วหนึ่งใบ", "I have ____ ____.", "เลือกสองคำสุดท้ายตามลำดับ"),
        ("choice", "a  ·  ticket", "_sentence_done"), ("choice", "ticket  ·  a", "_sentence_retry"),
    ], [], None),
    "_sentence_done": ("result", "เรียงได้ถูกต้อง", "เรียงประโยค", [
        ("quote", "ประโยคของคุณ", "I have a ticket.", "ฉันมีตั๋วหนึ่งใบ"),
    ], [("เลือกเกมอื่น", "_word_games"), ("กลับหน้าฝึกภาษา", TODAY)], None),
    "_sentence_retry": ("practice", "สลับสองคำสุดท้าย", "เรียงประโยค", [
        ("quote", "ลองพูดออกเสียง", "a ticket", "วาง a ไว้ข้างหน้า ticket"),
    ], [("กลับไปเรียงใหม่", "sentence_scramble_screen")], None),

    "ghost_shadow_duel_screen": ("practice", "ท้าสถิติของฉัน", "คำที่เคยฝึก · การเดินทาง", [
        ("meter", "รอบก่อนตอบถูก 0 จาก 1 ข้อ", 0),
        ("quote", "ลองตอบอีกครั้ง", "platform หมายถึงอะไร", "เลือกความหมายในบริบทของสถานีรถไฟ"),
        ("choice", "ชานชาลา", "_duel_win"), ("choice", "สถานี", "_duel_same"),
    ], [], None),
    "_duel_win": ("result", "ทำได้ดีกว่ารอบก่อน", "ท้าสถิติของฉัน", [
        ("stat", "1 / 1", "ข้อที่ตอบถูก", "ครั้งก่อน 0 จาก 1 ข้อ"),
        ("row", "platform", "ครั้งนี้เลือก ชานชาลา ได้ถูกต้อง", None),
    ], [("กลับหน้าฝึกภาษา", TODAY)], None),
    "_duel_same": ("result", "ผลเท่ากับครั้งก่อน", "ท้าสถิติของฉัน", [
        ("stat", "0 / 1", "ข้อที่ตอบถูก", "ครั้งก่อน 0 จาก 1 ข้อ"),
        ("quote", "ดูคำที่ยังสับสน", "platform คือชานชาลา", "ส่วน station คือสถานี"),
    ], [("ลองเติมคำในประโยค", "fill_in_the_blanks_screen")], None),

    "boss_battle_screen": ("practice", "ด่านสะกดคำ", "ด่านสุดท้าย · เกมฝึกคำ", [
        ("meter", "เหลืออีก 1 คำจึงจะผ่านด่าน", 2/3),
        ("hero", "เลือกคำที่สะกดถูก", "ยั่งยืน", "อ่านแต่ละคำให้ครบก่อนเลือก"),
        ("choice", "sustainable", "result_screen"), ("choice", "sustainble", "_boss_retry"),
    ], [], None),
    "_boss_retry": ("practice", "ขาดตัวอักษรไปหนึ่งตัว", "ด่านสะกดคำ", [
        ("quote", "ดูช่วงท้ายของคำ", "sustain + able", "เติม a ก่อน ble"),
    ], [("ลองสะกดใหม่", "boss_battle_screen")], None),
    "result_screen": ("result", "ผ่านด่านสะกดคำแล้ว", "เกมฝึกคำ · ผลการฝึกครั้งนี้", [
        ("art", "medal", "สะกดคำสุดท้ายได้แล้ว"),
        ("hero", "คำที่ใช้ผ่านด่าน", "sustainable", "ยั่งยืน"),
    ], [("เลือกเกมอื่น", "_word_games"), ("กลับหน้าฝึกภาษา", TODAY)], None),
}

for key, answer, meaning in [
    ("_quiz_station", "สถานี", "station"),
    ("_quiz_ticket", "ตั๋ว", "ticket"),
]:
    SCREENS[key] = ("practice", "ลองแยกสองคำนี้", "การเดินทาง · ข้อ 1", [
        ("hero", "คำที่เลือก", answer, f"{answer} ตรงกับคำว่า {meaning}"),
        ("quote", "คำที่โจทย์ถาม", "platform · ชานชาลา", "The train is at platform two."),
    ], [("ดูผลการฝึก", "score_screen")], None)
