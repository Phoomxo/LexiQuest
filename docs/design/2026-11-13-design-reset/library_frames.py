"""Library and speech flows for the native prototype; all learner data is fictional."""

SCREENS = {
    "categories_page": ("list", "คลังคำศัพท์", "คำที่เก็บไว้", [
        ("hero", "ชุดคำของฉัน", "การเดินทาง", "3 คำ  ·  ทบทวนได้วันนี้"),
        ("row", "เปิดชุดการเดินทาง", "station  ·  platform  ·  ticket", "vocab_list_screen"),
        ("row", "ฝึกจากข้อความ", "ใช้คำจากสิ่งที่กำลังอ่าน", "source_practice_screen"),
        ("row", "เก็บคำจากกล้อง", "ถ่ายสิ่งของแล้วเลือกคำที่จะเก็บ", "object_scanner_screen"),
    ], [("เพิ่มคำศัพท์", "add_vocab_screen"), ("นำเข้าชุดคำ", "wordbook_import_screen")], "คลังคำศัพท์"),
    "vocab_list_screen": ("list", "การเดินทาง", "คลังคำ  /  3 คำ", [
        ("row", "ค้นหาในชุดนี้", "ค้นด้วยคำอังกฤษหรือคำแปล", "_word_search"),
        ("row", "station", "สถานี  ·  ฝึกครั้งล่าสุดเมื่อวาน", "_word"),
        ("row", "platform", "ชานชาลา", "_platform"),
        ("row", "ticket", "ตั๋ว  ·  ตอบได้ครั้งล่าสุด", "_ticket"),
    ], [("ฟังคำในชุดนี้", "smart_audio_playlist_screen"), ("เพิ่มคำในชุด", "add_vocab_screen")], None),
    "_word_search": ("form", "ค้นคำในชุด", "การเดินทาง", [
        ("field", "คำที่ค้นหา", "sta"),
        ("row", "station", "สถานี  ·  พบ 1 คำ", "_word"),
    ], [("แสดงทั้งชุด", "vocab_list_screen")], None),
    "_word": ("reader", "station", "การเดินทาง  /  คำนาม", [
        ("hero", "ความหมาย", "สถานี", "ใช้เรียกสถานที่ เช่น สถานีรถไฟ"),
        ("quote", "ตัวอย่างประโยค", "Meet me at the station.", "มาเจอกันที่สถานีนะ"),
        ("row", "ฟังและฝึกพูด", "ออกเสียงคำนี้ หรือพูดตามทั้งประโยค", "phonetic_explorer_screen"),
        ("row", "ถามผู้ช่วยเรื่องคำนี้", "ลองเทียบ station กับ platform", "ai_tutor_screen"),
    ], [("ฝึกฟังแล้วเขียน", "dictation_quiz_screen")], None),
    "_platform": ("reader", "platform", "การเดินทาง  /  คำนาม", [
        ("hero", "ความหมายในประโยคนี้", "ชานชาลา", "บริเวณที่ผู้โดยสารรอขึ้นรถไฟ"),
        ("quote", "ตัวอย่างประโยค", "Wait on the platform.", "รออยู่บนชานชาลานะ"),
        ("row", "ดูคำที่มักสับสน", "station  ·  สถานี", "_word"),
    ], [("กลับไปดูชุดคำ", "vocab_list_screen")], None),
    "_ticket": ("reader", "ticket", "การเดินทาง  /  คำนาม", [
        ("hero", "ความหมาย", "ตั๋ว", "เอกสารหรือหลักฐานที่ใช้เดินทาง"),
        ("quote", "ตัวอย่างประโยค", "Here is my ticket.", "นี่คือตั๋วของฉัน"),
    ], [("กลับไปดูชุดคำ", "vocab_list_screen")], None),
    "add_vocab_screen": ("form", "เพิ่มคำศัพท์", "เก็บในชุดการเดินทาง", [
        ("field", "คำภาษาอังกฤษ", "suitcase"),
        ("field", "ความหมายภาษาไทย", "กระเป๋าเดินทาง"),
        ("field", "ชนิดของคำ", "คำนาม"),
        ("row", "มีหลายคำอยู่ในไฟล์เดียว", "ตรวจรายการก่อนเพิ่มเข้าคลัง", "add_multiple_words_screen"),
    ], [("เก็บคำนี้", "_suitcase")], None),
    "_suitcase": ("reader", "suitcase", "เก็บในชุดการเดินทางแล้ว", [
        ("hero", "คำนาม", "กระเป๋าเดินทาง", "เพิ่มเข้าคลังแล้ว 1 คำ"),
        ("quote", "ตัวอย่างประโยค", "I packed my suitcase.", "ฉันจัดกระเป๋าเดินทางแล้ว"),
    ], [("ดูชุดคำที่อัปเดต", "_library_added")], None),
    "_library_added": ("list", "การเดินทาง", "คลังคำ  /  4 คำ", [
        ("row", "suitcase", "กระเป๋าเดินทาง  ·  เพิ่งเพิ่ม", "_suitcase"),
        ("row", "station", "สถานี", "_word"),
        ("row", "platform", "ชานชาลา", "_platform"),
        ("row", "ticket", "ตั๋ว", "_ticket"),
    ], [], None),
    "wordbook_import_screen": ("form", "นำเข้าชุดคำ", "คลังคำ", [
        ("lines", "นำคำจากที่อื่นมาเก็บไว้ด้วยกัน", "ใช้ไฟล์ตาราง หรือวางรายการคำ", "ตรวจคำซ้ำและคำแปลได้ก่อนบันทึก"),
        ("row", "เปิดไฟล์ตัวอย่าง", "คำบนรถไฟ.csv  ·  3 แถว", "add_multiple_words_screen"),
        ("row", "วางรายการคำ", "ใช้ข้อความจากตารางที่คัดลอกมา", "_paste_words"),
    ], [], None),
    "_paste_words": ("form", "วางรายการคำ", "นำเข้าชุดคำ", [
        ("lines", "คำและความหมาย", "carriage,ตู้โดยสาร", "aisle,ทางเดินระหว่างที่นั่ง"),
        ("note", "ชุดที่จะเก็บ  ·  การเดินทาง", "คั่นคำกับคำแปลด้วยจุลภาค"),
    ], [("ตรวจ 2 รายการ", "_import_ready")], None),
    "add_multiple_words_screen": ("list", "ตรวจคำก่อนนำเข้า", "คำบนรถไฟ.csv  /  3 แถว", [
        ("row", "carriage", "ตู้โดยสาร  ·  พร้อมนำเข้า", None),
        ("row", "aisle", "ยังไม่มีคำแปล  ·  แตะเพื่อแก้ไข", "_import_edit"),
        ("row", "ticket", "มีคำนี้ในคลังแล้ว  ·  ข้ามรายการนี้", None),
        ("note", "เก็บในชุดการเดินทาง", "แก้คำแปลที่ขาดก่อนยืนยัน"),
    ], [("เติมคำแปลที่ขาด", "_import_edit")], None),
    "_import_edit": ("form", "แก้คำแปล", "คำบนรถไฟ.csv  /  แถวที่ 2", [
        ("field", "คำภาษาอังกฤษ", "aisle"),
        ("field", "ความหมายภาษาไทย", "ทางเดินระหว่างที่นั่ง"),
    ], [("ใช้คำแปลนี้", "_import_ready")], None),
    "_import_ready": ("list", "พร้อมนำเข้า", "ชุดการเดินทาง", [
        ("row", "carriage", "ตู้โดยสาร", None),
        ("row", "aisle", "ทางเดินระหว่างที่นั่ง", "_import_edit"),
    ], [("เพิ่ม 2 คำเข้าคลัง", "_import_done")], None),
    "_import_done": ("result", "เพิ่มคำเรียบร้อย", "ชุดการเดินทาง", [
        ("stat", "2", "คำที่เพิ่งเพิ่ม", "ตอนนี้มี 5 คำในชุดการเดินทาง"),
        ("row", "carriage", "ตู้โดยสาร", None),
        ("row", "aisle", "ทางเดินระหว่างที่นั่ง", None),
    ], [("ดูคำทั้ง 5 คำ", "_library_imported")], None),
    "_library_imported": ("list", "การเดินทาง", "คลังคำ  /  5 คำ", [
        ("row", "carriage", "ตู้โดยสาร  ·  เพิ่งนำเข้า", None),
        ("row", "aisle", "ทางเดินระหว่างที่นั่ง  ·  เพิ่งนำเข้า", None),
        ("row", "station", "สถานี", "_word"),
        ("row", "platform", "ชานชาลา", "_platform"),
        ("row", "ticket", "ตั๋ว", "_ticket"),
    ], [], None),
    "source_practice_screen": ("reader", "ฝึกจากข้อความ", "ข้อความในเครื่อง", [
        ("quote", "ข้อความที่เลือก", "Meet me at the station.", "Bring your ticket."),
        ("row", "station", "สถานี  ·  พบในคลัง", "_word"),
        ("row", "ticket", "ตั๋ว  ·  พบในคลัง", "_ticket"),
    ], [("ใช้ข้อความนี้ฝึก", "_source_choices")], None),
    "_source_choices": ("list", "ฝึกคำจากข้อความนี้", "station  /  ticket", [
        ("row", "ฟังแล้วเขียน", "ลองเขียนคำที่ได้ยิน", "dictation_quiz_screen"),
        ("row", "พูดคำศัพท์", "ดูว่าเครื่องได้ยินเป็นคำอะไร", "speak_to_text_screen"),
        ("row", "ถามเรื่องการใช้คำ", "ยกประโยคไปคุยกับผู้ช่วย", "ai_tutor_screen"),
    ], [], None),
    "object_scanner_screen": ("scan", "เก็บคำจากกล้อง", "คลังคำ", [
        ("art", "scan", "เล็งกล้องไปที่สิ่งของ"),
        ("note", "แอปต้องใช้กล้องเพื่อหาชื่อสิ่งของ", "คุณเลือกได้ว่าจะเก็บคำไหน"),
    ], [("ลองใช้ภาพตัวอย่าง", "_scan_result"), ("พิมพ์คำเอง", "add_vocab_screen")], None),
    "_scan_result": ("scan", "คำที่พบในภาพ", "ภาพตัวอย่าง  /  กระเป๋าเดินทาง", [
        ("hero", "คำที่แนะนำ", "suitcase", "คำนาม  ·  กระเป๋าเดินทาง"),
        ("note", "ตรวจให้ตรงกับสิ่งของในภาพ", "ยังไม่ได้เพิ่มคำนี้เข้าคลัง"),
    ], [("เก็บคำนี้", "_suitcase"), ("แก้ไขก่อนเก็บ", "add_vocab_screen")], None),
    "ai_tutor_screen": ("reader", "ถามเรื่องคำนี้", "station  /  การเดินทาง", [
        ("quote", "ประโยคที่กำลังฝึก", "Meet me at the station.", "มาเจอกันที่สถานีนะ"),
        ("field", "คำถามของฉัน", "station กับ platform ต่างกันยังไง"),
        ("note", "ผู้ช่วยจะได้รับคำ ประโยค และคำถามนี้", "ส่งเมื่อคุณกดยืนยัน"),
    ], [("ยืนยันและดูคำตอบตัวอย่าง", "_tutor_reply"), ("กลับไปดูคำศัพท์", "_word")], None),
    "_tutor_reply": ("reader", "คำตอบจากผู้ช่วย", "คำตอบตัวอย่าง", [
        ("quote", "สถานีทั้งแห่ง", "Meet me at the station.", "ใช้ station เมื่อพูดถึงสถานี"),
        ("quote", "จุดที่รอขึ้นรถไฟ", "Meet me on the platform.", "ใช้ platform เมื่อพูดถึงชานชาลา"),
        ("row", "เปิดคำว่า platform", "เก็บสองความหมายนี้แยกกัน", "_platform"),
    ], [("กลับไปดูคำว่า station", "_word")], None),
    "dictation_quiz_screen": ("audio", "ฟังแล้วเขียน", "การเดินทาง  /  คำที่ 1", [
        ("art", "wave", "เสียงคำศัพท์"),
        ("row", "ฟังไม่ได้ในตอนนี้", "เปิดคำใบ้แล้วฝึกสะกดแทน", "_dict_hint"),
        ("field", "คำที่ได้ยิน", "station"),
    ], [("ตรวจคำตอบ", "_dict_feedback"), ("ดูตัวอย่างการฟัง", "_dict_play")], None),
    "_dict_play": ("audio", "กำลังเล่นคำศัพท์", "ตัวอย่างการฟัง", [
        ("art", "wave", "ความเร็วปกติ"),
        ("field", "คำที่ได้ยิน", "station"),
    ], [("หยุดและตรวจคำตอบ", "_dict_feedback")], None),
    "_dict_hint": ("practice", "ลองสะกดจากคำใบ้", "การเดินทาง", [
        ("quote", "สถานที่ที่ไปขึ้นรถไฟ", "Meet me at the ____.", "คำนี้ขึ้นต้นด้วย s"),
        ("field", "คำที่นึกออก", "station"),
    ], [("ตรวจคำตอบ", "_dict_feedback")], None),
    "_dict_feedback": ("result", "สะกดถูกแล้ว", "ผลการฝึกครั้งนี้", [
        ("hero", "คำที่ตอบ", "station", "สถานี  ·  สะกดครบทั้ง 7 ตัวอักษร"),
        ("quote", "ลองใช้คำนี้", "Meet me at the station.", "มาเจอกันที่สถานีนะ"),
    ], [("ลองพูดตามประโยค", "shadowing_challenge_screen"), ("กลับไปดูคำศัพท์", "_word")], None),
    "phonetic_explorer_screen": ("audio", "แยกเสียงในคำ", "station  /  การออกเสียง", [
        ("hero", "ลองสังเกตเสียงกลางคำ", "/ʃ/", "เสียงเดียวกับต้นคำว่า she"),
        ("quote", "สองคำที่มีเสียงนี้", "she   /ʃiː/", "station   /ˈsteɪʃən/"),
        ("row", "ฝึกพูดเฉพาะคำ", "station", "speak_to_text_screen"),
        ("row", "ฝึกพูดทั้งประโยค", "Meet me at the station.", "shadowing_challenge_screen"),
    ], [("ดูตัวอย่างการฟังเสียง", "_phonetic_play")], None),
    "_phonetic_play": ("audio", "เสียงในคำว่า she", "ตัวอย่างการฟัง", [
        ("art", "wave", "เสียงต้นคำ  /ʃ/"),
        ("quote", "แล้วลองหาเสียงเดียวกัน", "she  →  station", "สังเกตเสียงหลังพยางค์แรกของ station"),
    ], [("ลองพูดคำว่า station", "speak_to_text_screen")], None),
    "smart_audio_playlist_screen": ("audio", "ฟังคำในชุด", "การเดินทาง  /  3 คำ", [
        ("hero", "คำแรกในชุด", "station", "สถานี"),
        ("row", "คำถัดไป", "platform  ·  ชานชาลา", None),
        ("row", "คำสุดท้าย", "ticket  ·  ตั๋ว", None),
    ], [("เริ่มฟังชุดคำ", "_playlist_play"), ("เปิดคำแรก", "_word")], None),
    "_playlist_play": ("audio", "กำลังเล่นชุดคำ", "ตัวอย่างการฟัง  /  1 จาก 3", [
        ("art", "wave", "station"),
        ("meter", "คำที่ 1 จาก 3", 1 / 3),
        ("row", "ฟังคำถัดไป", "platform  ·  ชานชาลา", "_playlist_next"),
    ], [("หยุดเล่น", "smart_audio_playlist_screen")], None),
    "_playlist_next": ("audio", "กำลังเล่นชุดคำ", "ตัวอย่างการฟัง  /  2 จาก 3", [
        ("art", "wave", "platform"),
        ("meter", "คำที่ 2 จาก 3", 2 / 3),
        ("row", "ฟังคำสุดท้าย", "ticket  ·  ตั๋ว", "_playlist_last"),
    ], [("หยุดเล่น", "smart_audio_playlist_screen")], None),
    "_playlist_last": ("audio", "ฟังครบชุดแล้ว", "การเดินทาง  /  3 จาก 3", [
        ("hero", "คำสุดท้าย", "ticket", "ตั๋ว"),
        ("meter", "ฟังครบ 3 คำ", 1),
    ], [("กลับไปดูชุดคำ", "vocab_list_screen"), ("ฟังอีกครั้ง", "_playlist_play")], None),
    "shadowing_challenge_screen": ("audio", "พูดตามประโยค", "การเดินทาง  /  ที่สถานี", [
        ("quote", "ประโยคต้นแบบ", "Meet me at the station.", "มาเจอกันที่สถานีนะ"),
        ("art", "wave", "เว้นจังหวะหลังคำว่า me"),
        ("note", "ใช้ไมโครโฟนตอนที่คุณเริ่มพูด", "ฝึกอ่านในใจต่อได้หากยังไม่สะดวก"),
    ], [("ลองพูดตาม", "_shadow_live"), ("ฝึกอ่านในใจ", "_word")], None),
    "_shadow_live": ("audio", "กำลังฟังประโยค", "ตัวอย่างการใช้ไมโครโฟน", [
        ("art", "wave", "กำลังฟัง"),
        ("quote", "พูดตามประโยค", "Meet me at the station.", "กดหยุดเมื่อพูดจบ"),
    ], [("หยุดและดูข้อความ", "_shadow_done")], None),
    "_shadow_done": ("result", "เทียบสิ่งที่พูด", "การเดินทาง", [
        ("quote", "ประโยคต้นแบบ", "Meet me at the station.", "มี the หน้าคำว่า station"),
        ("quote", "ข้อความที่เครื่องได้ยิน", "Meet me at station.", "ลองเว้นจังหวะให้ได้ยิน the"),
    ], [("ลองอีกครั้ง", "_shadow_live"), ("กลับไปดูคำศัพท์", "_word")], None),
    "speak_to_text_screen": ("audio", "ลองพูดคำนี้", "การเดินทาง  /  ฝึกออกเสียง", [
        ("hero", "คำเป้าหมาย", "station", "สถานี  ·  เน้นเสียงพยางค์แรก"),
        ("note", "ใช้ไมโครโฟนเพื่อแปลงเสียงเป็นข้อความ", "กดหยุดได้ทันทีที่พูดจบ"),
    ], [("เริ่มพูด", "_speech_live"), ("ฝึกโดยไม่ใช้ไมค์", "phonetic_explorer_screen")], None),
    "_speech_live": ("audio", "กำลังฟังคำที่พูด", "ตัวอย่างการใช้ไมโครโฟน", [
        ("art", "wave", "กำลังฟัง"),
        ("hero", "คำที่กำลังฝึก", "station", "กดหยุดเมื่อพูดจบ"),
    ], [("หยุดและดูข้อความ", "_speech_review")], None),
    "_speech_review": ("result", "ตรวจคำที่ได้ยิน", "การเดินทาง", [
        ("hero", "ข้อความที่เครื่องได้ยิน", "station", "ตรงกับคำเป้าหมาย"),
        ("note", "ตรงกับคำที่ตั้งใจพูดไหม", "ถ้าไม่ตรง ลองพูดอีกครั้งได้"),
    ], [("ตรงแล้ว กลับไปดูคำ", "_word"), ("ลองพูดอีกครั้ง", "_speech_live")], None),
}
