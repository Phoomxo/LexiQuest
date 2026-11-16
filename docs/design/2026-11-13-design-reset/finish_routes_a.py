"""Detached learning and equipment routes in the FigCraft prototype."""

from exam_routes import example


TODAY = "choose_mode_screen"
PRACTICE = "main_navigation_screen"
LEVEL = "cefr_selection_screen"
WORLD = "learning_world_map_screen"
DIAG = "cefr_diagnostic_test_screen"
READ = "cefr_article_reader_screen"
BOSS = "boss_battle_screen"
AVATAR = "avatar_equipment_screen"
DICT = "dictation_quiz_screen"
SHOP = "shop_page"
COLLECTION = "achievements_screen"
PROFILE = "profile_settings_screen"


def replace_target(screens, key, old, new):
    family, title, sub, blocks, buttons, tab = screens[key]
    blocks = [(*row[:-1], new) if row[-1] == old else row for row in blocks]
    buttons = [(name, new if target == old else target) for name, target in buttons]
    screens[key] = family, title, sub, blocks, buttons, tab


def equipment(screens):
    replace_target(screens, SHOP, AVATAR, "_equipment_from_shop")
    for origin, start, suffix, exit_label in (
        (COLLECTION, AVATAR, "", "กลับไปดูของสะสม"),
        (SHOP, "_equipment_from_shop", "_shop", "กลับไปที่ร้าน"),
    ):
        preview, equipped = "_hat_preview" + suffix, "_hat_equipped" + suffix
        screens[start] = example("profile", "แต่งตัวละคร", "ของตกแต่งที่มี", [
            ("art", "medal", "หมวกของฉัน"),
            ("row", "หมวกนักออกเสียง", "มีแล้ว · แตะเพื่อลองสวม", preview),
            ("row", "พื้นหลังหน้าฝึก", "ดูพื้นหลังที่มี", "select_wallpaper_screen"),
        ], [(exit_label, origin)])
        screens[preview] = example("profile", "ลองสวมหมวก", "ตัวอย่างก่อนใช้", [
            ("art", "medal", "หมวกนักออกเสียง"),
            ("note", "ของชิ้นนี้อยู่ในคลังแล้ว", "ยืนยันเพื่อใช้เป็นหมวกของตัวละคร"),
        ], [("ใช้หมวกใบนี้", equipped), ("ยกเลิก", start)])
        screens[equipped] = example("profile", "สวมหมวกแล้ว", "ตัวละครของฉัน", [
            ("art", "medal", "หมวกนักออกเสียง"),
            ("row", "หมวกที่สวมอยู่", "หมวกนักออกเสียง · ใช้งานอยู่", None),
            ("row", "พื้นหลังหน้าฝึก", "ดูพื้นหลังที่มี", "select_wallpaper_screen"),
        ], [(exit_label, origin)])


def boss(screens):
    for i, (stage, next_stage, word, meaning, typo, hint) in enumerate([
        (BOSS, "_boss_second", "ephemeral", "ชั่วคราว", "ephemral", "หลังตัว m ยังมีตัว e"),
        ("_boss_second", "_boss_final", "meticulous", "พิถีพิถัน", "meticulus", "ช่วงท้ายสะกดว่า -lous"),
        ("_boss_final", "result_screen", "sustainable", "ยั่งยืน", "sustainble", "สะกดส่วนท้ายว่า -able"),
    ]):
        typed = ["_boss_first_typo", "_boss_second_typo", "_boss_typo"][i]
        retry = ["_boss_first_retry", "_boss_second_retry", "_boss_retry"][i]
        leave = "_boss_leave_" + str(i + 1)
        for key, spelling, dest, alternate in [(stage, word, next_stage, typed), (typed, typo, retry, stage)]:
            screens[key] = example("practice", "ด่านสะกดคำ", f"คำที่ {i + 1} จาก 3", [
                ("meter", f"ผ่านแล้ว {i} คำ · พลังคู่ต่อสู้ {max(0, 100-i*35)}", i / 3),
                ("hero", "เขียนเป็นภาษาอังกฤษ", meaning, "ตรวจตัวสะกดก่อนส่ง"),
                ("field", "คำตอบตัวอย่าง", spelling),
                ("row", "เปลี่ยนคำตอบตัวอย่าง", "ลองตรวจการสะกดอีกแบบ", alternate),
            ], [("ส่งคำตอบ", dest), ("ออกจากด่าน", leave)])
        screens[retry] = example("practice", "ลองตรวจตัวสะกด", f"ยังอยู่ที่คำที่ {i+1}", [
            ("quote", "คำที่ส่ง", typo, hint),
            ("note", "คำที่ผ่านแล้วยังอยู่ครบ", f"ผ่านแล้ว {i} จาก 3 คำ"),
        ], [("แก้คำตอบ", stage), ("ออกจากด่าน", leave)])
        screens[leave] = example("practice", "จะออกจากด่านไหม", f"คำที่ {i+1} จาก 3", [
            ("note", "รอบนี้ยังเล่นไม่จบ", "ถ้าออกตอนนี้ ครั้งหน้าจะเริ่มที่คำแรก"),
        ], [("เล่นคำเดิมต่อ", stage), ("ออกไปเลือกเกม", "_word_games")])


# Entries drawn from CefrService.defaultCefrDatabase. Each level shows the
# actual word used by its card, including the empty A2 filter recovery.
WORDS = [
    ("A1", "คำในชีวิตประจำวัน", "hello", "สวัสดี", "Hello, how are you?"),
    ("A2", "การเดินทาง", "journey", "การเดินทาง", "Have a safe journey."),
    ("B1", "การทำงาน", "achieve", "บรรลุเป้าหมาย", "He achieved his dream."),
    ("B2", "วิทยาศาสตร์", "sustainable", "ยั่งยืน", "We need sustainable energy sources."),
    ("C1", "การทำงาน", "meticulous", "พิถีพิถัน", "She is meticulous about her work."),
    ("C2", "ปรัชญา", "ephemeral", "ชั่วคราว", "Fame is often ephemeral."),
]


def levels(screens):
    screens[LEVEL] = example("list", "คำศัพท์และบทอ่าน", "เลือกจุดเริ่มที่เหมาะกับตัวเอง", [
        ("row", "เลือกคำตามระดับ", "A1 ถึง C2 · พลิกบัตรแล้วลองนึกความหมาย", WORLD),
        ("row", "ลองตอบก่อนเลือกระดับ", "5 ข้อ · ดูผลแล้วเลือกเรื่องอ่าน", DIAG),
        ("row", "ซื้อตั๋วรถไฟ", "บทอ่าน A1 · ประโยคสั้นที่ช่องขายตั๋ว", "_easy_reading"),
        ("row", "นัดกันที่สถานี", "บทอ่าน A2 · อ่านเรื่องแล้วฝึกใช้คำ", READ),
    ], [("กลับไปเลือกวิธีฝึก", PRACTICE)])
    screens[WORLD] = example("list", "เลือกคำตามระดับ", "แตะระดับที่อยากลองฝึก", [
        ("row", level + " · " + topic, word + " · บัตรคำตัวอย่าง", "_cefr_" + level.lower())
        for level, topic, word, _, _ in WORDS
    ], [("กลับไปเลือกบทเรียน", LEVEL)])
    for level, topic, word, meaning, sentence in WORDS:
        deck = "_cefr_" + level.lower()
        card, answer = deck + "_card", deck + "_answer"
        blocks = [("quote", "คำในชุดตัวอย่าง", word, topic)]
        if level == "A2":
            blocks.append(("row", "ค้นคำในชุดนี้", "ลองค้นคำที่ไม่มีอยู่ในชุด", "_cefr_empty"))
        screens[deck] = example("list", "คำศัพท์ระดับ " + level, topic + " · 1 คำ", blocks, [
            ("เริ่มทบทวนคำนี้", card), ("เลือกระดับอื่น", WORLD)])
        screens[card] = example("practice", "นึกความหมาย", level + " · บัตร 1 จาก 1", [
            ("hero", "คำนี้หมายถึงอะไร", word, "นึกคำแปลก่อนพลิกบัตร"),
            ("lines", "ลองอ่านในประโยค", sentence, "ใช้ประโยคช่วยนึกความหมาย"),
        ], [("พลิกดูความหมาย", answer), ("พักแล้วกลับชุดคำ", deck)])
        screens[answer] = example("reader", "เทียบกับคำที่นึกไว้", level + " · บัตร 1 จาก 1", [
            ("hero", "คำแปล", word, meaning),
            ("quote", "ตัวอย่างการใช้", sentence, topic),
        ], [("จำได้แล้ว", deck + "_done"), ("ยังนึกไม่ออก · ลองอีกครั้ง", card)])
        screens[deck + "_done"] = example("result", "ทบทวนจบแล้ว", level + " · " + topic, [
            ("stat", "1 / 1", "คำที่เลือกว่าจำได้", word + " · " + meaning),
        ], [("กลับไปดูชุดเดิม", deck), ("เลือกระดับอื่น", WORLD)])
    screens["_cefr_empty"] = example("list", "ไม่พบคำในชุดนี้", "A2 · การเดินทาง", [
        ("field", "คำค้นตัวอย่าง", "meticulous"),
        ("note", "ลองเอาคำค้นออก", "จะแสดงคำในชุดการเดินทางระดับ A2 อีกครั้ง"),
    ], [("ล้างคำค้น", "_cefr_a2"), ("เลือกระดับอื่น", WORLD)])


QUESTIONS = [
    ("apple", "คำนี้หมายถึงอะไร", "แอปเปิล", ("กล้วย", "แอปเปิล", "ส้ม", "มะม่วง")),
    ("journey", "คำไหนมีความหมายใกล้กัน", "Trip", ("Food", "House", "Trip", "Book")),
    ("achieve", "คำนี้หมายถึงอะไร", "บรรลุเป้าหมาย", ("บรรลุเป้าหมาย", "ล้มเหลว", "ปฏิเสธ", "ละทิ้ง")),
    ("innovative", "คำไหนใกล้เคียงที่สุด", "ที่นำเสนอสิ่งใหม่", ("โบราณ", "ธรรมดา", "น่าเบื่อ", "ที่นำเสนอสิ่งใหม่")),
    ("ubiquitous", "เลือกความหมายภาษาอังกฤษ", "Present everywhere", ("Rare", "Present everywhere", "Hidden", "Ancient")),
]


def question_at(index, score):
    if index == 0:
        return DIAG
    if index == len(QUESTIONS):
        return f"_diag_score_{score}"
    return f"_diag_q{index + 1}_{score}"


def diagnostic(screens):
    for i, (word, prompt, correct, options) in enumerate(QUESTIONS):
        for score in range(i + 1):
            screens[question_at(i, score)] = example("practice", "ลองตอบก่อนเลือกระดับ", f"ข้อ {i+1} จาก 5", [
                ("hero", prompt, word, "เลือกหนึ่งคำตอบเพื่อไปข้อต่อไป"),
                *(("choice", option, question_at(i + 1, score + int(option == correct))) for option in options),
            ], [("พักแล้วกลับไปเลือกบทเรียน", LEVEL)])
    for score in range(6):
        reading = "_suggest_a2" if score >= 2 else "_suggest_a1"
        band = ["A1", "A1", "A2", "B1", "B2", "C1"][score]
        band_label = "C1 หรือ C2" if score == 5 else band
        result = question_at(5, score)
        deck = "_cefr_" + band.lower()
        mapped = {deck + step: f"_diag{score}_{band.lower()}" + step for step in ("", "_card", "_answer", "_done")}
        for src, dest in mapped.items():
            family,title,sub,blocks,buttons,tab=screens[src]
            blocks = [b for b in blocks if b[-1] != "_cefr_empty"]
            buttons = [("กลับไปดูผลเดิม", result) if target == WORLD else (label, mapped.get(target, target))
                       for label, target in buttons]
            screens[dest]=family,title,sub,blocks,buttons,tab
        screens[result] = example("result", "ผลที่ลองตอบ", "แบบสำรวจคำศัพท์ 5 ข้อ", [
            ("stat", f"{score} / 5", "ข้อที่ตอบถูก", "ใช้ผลชุดสั้นนี้เลือกบทเรียนถัดไป"),
            ("row", "ระดับคำที่แนะนำ · " + band_label, "ลองเปิดชุดคำศัพท์ระดับ " + band, mapped[deck]),
            ("note", "อยากลองอ่านเรื่องสั้นก็ได้", "มีบทอ่านตัวอย่าง A1 และ A2 ให้เลือก"),
        ], [("ดูบทอ่านที่แนะนำ", reading), ("เลือกบทเรียนเอง", LEVEL)])
    for dest, level, title, detail, reader in [
        ("_suggest_a1", "A1", "ซื้อตั๋วรถไฟ", "ประโยคสั้นที่ช่องขายตั๋ว", "_easy_reading"),
        ("_suggest_a2", "A2", "นัดกันที่สถานี", "ใช้บริบทช่วยนึกคำศัพท์", READ),
    ]:
        screens[dest] = example("reader", "บทอ่านที่แนะนำ", "เลือกอ่านได้ตามความสนใจ", [
            ("quote", "บทอ่าน " + level, title, detail),
        ], [("เริ่มอ่านเรื่องนี้", reader), ("เลือกบทเรียนเอง", LEVEL)])


def reader(screens):
    screens["_article_term"] = example("reader", "คำในบทอ่าน", "นัดกันที่สถานี · ย่อหน้าสุดท้าย", [
        ("hero", "คำนาม", "platform", "ชานชาลา"),
        ("quote", "ประโยคในเรื่อง", "They meet on the platform.", "ทั้งสองคนเจอกันที่ชานชาลา"),
    ], [("ดูตัวอย่างการฟังเสียง", "_article_sound"), ("อ่านต่อที่เดิม", READ)])
    screens["_article_sound"] = example("audio", "ฟังคำในประโยค", "ตัวอย่างหน้าฟังเสียง", [
        ("art", "wave", "platform"),
        ("quote", "อ่านตามได้", "They meet on the platform.", "ทั้งสองคนเจอกันที่ชานชาลา"),
        ("row", "ตอนนี้ฟังเสียงไม่ได้", "ดูคำอ่านแล้วกลับไปอ่านต่อ", "_article_quiet"),
    ], [("กลับไปอ่านต่อ", READ)])
    screens["_article_quiet"] = example("reader", "อ่านแบบไม่เปิดเสียง", "คำที่เลือกจากบทอ่าน", [
        ("hero", "platform", "แพลตฟอร์ม", "เน้นพยางค์แรก · ชานชาลา"),
        ("quote", "ประโยคเดิม", "They meet on the platform.", "กลับไปอ่านได้จากย่อหน้าเดิม"),
    ], [("กลับไปอ่านต่อ", READ)])
    for origin, suffix, exit_label in READER_ORIGINS:
        mapping = {key: article_key(key, suffix) for key in READER_STEPS}
        replace_target(screens, origin, READ, mapping[READ])
        for key, variant in mapping.items():
            family, title, sub, blocks, buttons, tab = screens[key]
            blocks = [(*row[:-1], mapping.get(row[-1], row[-1])) if row[0] in ("row", "choice") else row for row in blocks]
            buttons = [(name, mapping.get(target, target)) for name, target in buttons]
            if key == "_reading_done":
                buttons = [(exit_label, origin), ("กลับหน้าฝึกภาษา", TODAY)]
            screens[variant] = family, title, sub, blocks, buttons, tab


READER_ORIGINS = [
    (LEVEL, "lesson", "กลับไปเลือกบทเรียน"),
    ("_easy_reading", "easy", "กลับไปเรื่องซื้อตั๋วรถไฟ"),
    ("_suggest_a2", "suggest", "กลับไปที่บทอ่านแนะนำ"),
    ("_plan_profile", "profile", "กลับโปรไฟล์การเรียน"),
    ("_plan_pref_read", "method", "กลับไปดูวิธีเรียนที่เลือก"),
]
RECALL = "associative_reading_session_screen"
READER_STEPS = [READ, RECALL, "_reading_hint", "_reading_write", "_reading_done", "_article_term", "_article_sound", "_article_quiet"]


def article_key(key, suffix):
    base = {READ: "_article_from", RECALL: "_recall_from"}.get(key, key)
    return base + "_" + suffix


def render(d):
    from focused_learning import reading
    for _, suffix, _ in READER_ORIGINS:
        if d.key == article_key(READ, suffix):
            reading(d, article_key("_article_term", suffix), article_key(RECALL, suffix))
            return True
    return False


def dictation(screens):
    origins = [
        ("_word", "", "กลับไปดูคำเดิม"),
        ("_listening", "_listen", "กลับไปเลือกแบบฝึกฟัง"),
        ("_source_choices", "_source", "กลับไปฝึกคำจากข้อความ"),
        ("_mic_permission", "_mic", "กลับไปดูสิทธิ์ไมค์"),
    ]
    for origin, suffix, back in origins:
        start = "_dict_start" + suffix if suffix else DICT
        if suffix:
            replace_target(screens, origin, DICT, start)
        play, slow, hint, write, typo, miss, feedback = [
            "_dict_" + mode + suffix for mode in ("play", "slow", "hint", "write", "typo", "miss", "feedback")]
        screens[start] = example("audio", "ฟังแล้วเขียน", "การเดินทาง · 1 คำ", [
            ("art", "wave", "ฟังคำศัพท์หนึ่งคำ"),
            ("note", "ลองฟังก่อนดูตัวสะกด", "เลือกฟังช้าลงหรือใช้คำใบ้แทนได้"),
            ("row", "ตอนนี้ฟังเสียงไม่ได้", "เปิดคำใบ้แล้วลองเขียน", hint),
        ], [("ดูตัวอย่างการฟัง", play), (back, origin)])
        for key, label, next_audio, action in [
            (play, "ความเร็วปกติ", slow, "ฟังช้าลง"),
            (slow, "ความเร็ว 0.75 เท่า", play, "ฟังด้วยความเร็วปกติ"),
        ]:
            screens[key] = example("audio", "ฟังคำศัพท์", "ตัวอย่างหน้าฟังเสียง", [
                ("art", "wave", label),
                ("row", action, "เปลี่ยนความเร็วของคำเดิม", next_audio),
                ("row", "เปิดคำใบ้แทน", "ใช้ความหมายช่วยนึกคำ", hint),
            ], [("ลองเขียนคำที่ได้ยิน", write), (back, origin)])
        screens[hint] = example("practice", "เขียนจากคำใบ้", "ฝึกต่อโดยไม่เปิดเสียง", [
            ("hero", "คำนี้หมายถึง", "สถานี", "คำนาม · ขึ้นต้นด้วย st"),
            ("lines", "ลองนึกจากประโยค", "Meet me at the ____.", "มาเจอกันที่สถานีนะ"),
        ], [("ลองเขียนคำ", write), (back, origin)])
        for key, spelling, verdict, alternate in [(write, "station", feedback, typo), (typo, "staton", miss, write)]:
            screens[key] = example("form", "เขียนคำตอบ", "การเดินทาง · 1 คำ", [
                ("field", "คำตอบตัวอย่าง", spelling),
                ("row", "เปลี่ยนคำตอบตัวอย่าง", "ลองตรวจการสะกดอีกแบบ", alternate),
                ("row", "ฟังอีกครั้ง", "กลับไปฟังคำเดิม", play),
            ], [("ตรวจคำตอบ", verdict), (back, origin)])
        screens[miss] = example("practice", "ยังขาดตัว i", "ผลการตรวจคำตอบ", [
            ("quote", "คำที่ส่ง", "staton", "เทียบกับ station · สถานี"),
            ("note", "สังเกตส่วนท้ายของคำ", "คำว่า station ลงท้ายด้วย -tion"),
        ], [("แก้คำตอบ", write), (back, origin)])
        screens[feedback] = example("result", "สะกดถูกแล้ว", "ผลการตรวจคำตอบ", [
            ("hero", "คำที่ส่ง", "station", "สถานี"),
            ("quote", "ลองใช้คำนี้", "Meet me at the station.", "มาเจอกันที่สถานีนะ"),
        ], [(back, origin), ("ลองฟังคำนี้อีกครั้ง", start)])


def install(screens):
    equipment(screens)
    boss(screens)
    levels(screens)
    diagnostic(screens)
    reader(screens)
    dictation(screens)


LESSONS = [TODAY, PRACTICE, LEVEL]
GAME = [TODAY, PRACTICE, "_word_games", BOSS]
WARDROBE = [PROFILE, COLLECTION, AVATAR]
WORD = ["categories_page", "vocab_list_screen", "_word", DICT]
CASES = []
EXPECT = {}
OWNERS = {}


def case(owner, name, path, frame, expected_text):
    CASES.append((name, path))
    EXPECT[name] = (frame, expected_text)
    OWNERS[name] = owner


case(AVATAR, "สวมหมวกที่มีแล้วและกลับไปดูของสะสม",
     WARDROBE + ["_hat_preview", "_hat_equipped", COLLECTION], "_hat_equipped", "หมวกนักออกเสียง · ใช้งานอยู่")
case(AVATAR, "ยกเลิกการสวมหมวกก่อนใช้",
     WARDROBE + ["_hat_preview", AVATAR, COLLECTION], AVATAR, "มีแล้ว · แตะเพื่อลองสวม")
case(AVATAR, "ลองหมวกจากร้านแล้วกลับร้านเดิม",
     [PROFILE, COLLECTION, SHOP, "_equipment_from_shop", "_hat_preview_shop", "_hat_equipped_shop", SHOP],
     "_hat_equipped_shop", "หมวกนักออกเสียง · ใช้งานอยู่")
case(BOSS, "สะกดครบสามคำแล้วเลือกเกมใหม่",
     GAME + ["_boss_second", "_boss_final", "result_screen", "_word_games"], "result_screen", "ผ่านด่านสะกดคำแล้ว")
case(BOSS, "แก้คำสุดท้ายโดยเก็บสองคำแรกไว้",
     GAME + ["_boss_second", "_boss_final", "_boss_typo", "_boss_retry", "_boss_final", "result_screen", "_word_games"],
     "_boss_retry", "ผ่านแล้ว 2 จาก 3 คำ")
case(BOSS, "ออกจากด่านกลางรอบ",
     GAME + ["_boss_second", "_boss_leave_2", "_word_games"], "_boss_leave_2", "รอบนี้ยังเล่นไม่จบ")
case(READ, "เปิดคำจากบทอ่านแล้วกลับไปอ่านจนจบรอบ",
     [TODAY, READ, "_article_term", "_article_sound", READ, "associative_reading_session_screen",
      "_reading_write", "_reading_done", TODAY], "_reading_done", "I am on platform three.")
case(READ, "ฟังคำในบทอ่านไม่ได้และกลับไปย่อหน้าเดิม",
     [TODAY, READ, "_article_term", "_article_sound", "_article_quiet", READ],
     "_article_quiet", "เน้นพยางค์แรก · ชานชาลา")
case(DIAG, "ตอบถูกห้าข้อแล้วเปิดเรื่องที่แนะนำ",
     LESSONS + [question_at(i, i) for i in range(6)] + ["_suggest_a2", "_article_from_suggest"],
     "_diag_score_5", "5 / 5")
case(DIAG, "ตอบผิดห้าข้อแล้วอ่านเรื่องที่ง่ายขึ้น",
     LESSONS + [question_at(i, 0) for i in range(6)] + ["_suggest_a1", "_easy_reading", LEVEL],
     "_diag_score_0", "0 / 5")
case(DIAG, "พักก่อนทำแบบสำรวจครบและเลือกบทเรียนเอง",
     LESSONS + [DIAG, "_diag_q2_1", LEVEL], "_diag_q2_1", "ข้อ 2 จาก 5")
case(LEVEL, "เลือกชุดคำระดับ A2 แล้วทบทวนคำเดิม",
     LESSONS + [WORLD, "_cefr_a2", "_cefr_a2_card", "_cefr_a2_answer", "_cefr_a2_done", "_cefr_a2", WORLD, LEVEL],
     "_cefr_a2_done", "journey · การเดินทาง")
case(LEVEL, "ค้นไม่พบคำในชุดแล้วล้างคำค้น",
     LESSONS + [WORLD, "_cefr_a2", "_cefr_empty", "_cefr_a2", WORLD, LEVEL],
     "_cefr_empty", "ไม่พบคำในชุดนี้")
case(LEVEL, "เลือกบทอ่าน A1 เองแล้วกลับมาเลือกเรื่องอื่น",
     LESSONS + ["_easy_reading", LEVEL], "_easy_reading", "One ticket, please.")
case(WORLD, "เลือกคำระดับ C2 และกลับสู่รายการระดับ",
     LESSONS + [WORLD, "_cefr_c2", "_cefr_c2_card", "_cefr_c2_answer", "_cefr_c2_done", "_cefr_c2", WORLD],
     "_cefr_c2_done", "ephemeral · ชั่วคราว")
case(WORLD, "พักบัตรคำระดับ B1 แล้วเลือกระดับใหม่",
     LESSONS + [WORLD, "_cefr_b1", "_cefr_b1_card", "_cefr_b1", WORLD],
     "_cefr_b1_card", "achieve")
case(DICT, "เขียนตามเสียงช้าแล้วกลับคำเดิม",
     WORD + ["_dict_play", "_dict_slow", "_dict_write", "_dict_feedback", "_word"],
     "_dict_feedback", "สะกดถูกแล้ว")
case(DICT, "ใช้คำใบ้และแก้คำที่สะกดผิด",
     WORD + ["_dict_hint", "_dict_write", "_dict_typo", "_dict_miss", "_dict_write", "_dict_feedback", "_word"],
     "_dict_miss", "เทียบกับ station · สถานี")
case(DICT, "ออกจากแบบฝึกฟังกลับหมวดฟังและพูด",
     [TODAY, PRACTICE, "_listening", "_dict_start_listen", "_dict_play_listen", "_listening"],
     "_dict_play_listen", "ความเร็วปกติ")
case(DICT, "ฝึกฟังคำจากข้อความแล้วกลับข้อความเดิม",
     ["categories_page", "source_practice_screen", "_source_choices", "_dict_start_source", "_dict_hint_source",
      "_dict_write_source", "_dict_feedback_source", "_source_choices"], "_dict_feedback_source", "station")
case(DICT, "ฝึกด้วยคำใบ้จากหน้าสิทธิ์แล้วกลับไปดูสิทธิ์ไมค์",
     [PROFILE, "setting_screen", "device_permission_center_screen", "_mic_permission", "_dict_start_mic",
      "_dict_hint_mic", "_dict_write_mic", "_dict_feedback_mic", "_mic_permission"],
     "_dict_hint_mic", "ฝึกต่อโดยไม่เปิดเสียง")

PLAN_PROFILE = ["mastery_dashboard_screen", "_plan_studio", "_plan_pref", "_plan_profile"]
for (origin, suffix, exit_label), prefix in zip(READER_ORIGINS, [
    LESSONS,
    LESSONS + ["_easy_reading"],
    LESSONS + [question_at(i, i) for i in range(6)] + ["_suggest_a2"],
    PLAN_PROFILE,
    PLAN_PROFILE + ["_plan_pref_method", "_plan_pref_read"],
]):
    sequence = [READ, "_article_term", "_article_sound", READ, RECALL, "_reading_hint", RECALL, "_reading_write", "_reading_done"]
    case(READ, "นึกคำจากเรื่องจบแล้ว" + exit_label,
         prefix + [article_key(step, suffix) for step in sequence] + [origin],
         article_key("_reading_done", suffix), "I am on platform three.")
case(DIAG, "ฝึกชุดคำที่แนะนำแล้วกลับไปดูคะแนนเดิม",
     LESSONS + [question_at(i, i) for i in range(6)] + ["_diag5_c1", "_diag5_c1_card", "_diag5_c1_answer",
      "_diag5_c1_done", "_diag_score_5"], "_diag_score_5", "ระดับคำที่แนะนำ · C1 หรือ C2")
