"""Task flows for the seven detached Flutter destinations from phonetics to import."""

TODAY = "choose_mode_screen"
MENU = "main_navigation_screen"
LIB = "categories_page"
SET = "vocab_list_screen"
WORD = "_word"
PROFILE = "profile_settings_screen"
PREF = "appearance_settings_screen"
GAMES = "_word_games"
IPA = "phonetic_explorer_screen"
RESULT = "result_screen"
WALL = "select_wallpaper_screen"
ARRANGE = "sentence_scramble_screen"
PLAY = "smart_audio_playlist_screen"
CHART = "thesis_chart_screen"
IMPORT = "wordbook_import_screen"

GAME_PATH = [TODAY, MENU, GAMES]
BOSS_PATH = GAME_PATH + ["boss_battle_screen", "_boss_second", "_boss_final", RESULT]
PREF_PATH = [PROFILE, "setting_screen", PREF, WALL]
IPA_PATH = [LIB, SET, WORD, IPA]
PLAY_PATH = [LIB, SET, PLAY, "_playlist_play"]
DATA_PATH = [PROFILE, "_account_data", CHART]
IMPORT_PATH = [LIB, IMPORT]

CASES = [
    ("เลือกเสียงต้นคำ she แล้วกลับไปอ่าน station", IPA_PATH + ["_phonetic_play", WORD]),
    ("อ่านวิธีออกเสียงแทนเมื่อเปิดเสียงไม่ได้", IPA_PATH + ["_phonetic_play", "_ipa_read", WORD]),
    ("ผ่านด่านแล้วทวนความหมายคำสุดท้าย", BOSS_PATH + ["_boss_word_review", GAMES]),
    ("ปิดผลด่านแล้วกลับหน้าฝึกภาษา", BOSS_PATH + [TODAY]),
    ("ใช้พื้นหลังที่มีแล้วตรวจพื้นหลังบนหน้าฝึก", PREF_PATH + ["_wall_focus_preview", "_wall_focus_applied", "_appearance_focus"]),
    ("ปิดตัวอย่างโดยเก็บพื้นหลังเดิม", PREF_PATH + ["_wall_focus_preview", WALL, PREF]),
    ("เรียงคำจนครบแล้วตรวจประโยค", GAME_PATH + [ARRANGE, "_arrange_a", "_sentence_check_ok", "_sentence_done", GAMES]),
    ("พบคำที่สลับกันแล้วกลับไปแก้ก่อนออก", GAME_PATH + [ARRANGE, "_arrange_ticket", "_sentence_check_swap", "_sentence_retry", ARRANGE, GAMES]),
    ("ฟังจนถึงคำสุดท้ายแล้วเปิดชุดเดิม", PLAY_PATH + ["_playlist_next", "_playlist_last", "_playlist_finished", SET]),
    ("หยุดชุดคำระหว่างฟังแล้วกลับเข้าชุด", PLAY_PATH + ["_playlist_next", "_playlist_stopped_2", SET]),
    ("อ่านผลก่อนและหลังฝึกแล้วกลับข้อมูลของฉัน", DATA_PATH + ["_chart_account_read", "_account_data"]),
    ("ดูขอบเขตข้อมูลตัวอย่างแล้วออกโดยไม่เข้าร่วม", DATA_PATH + ["_chart_account_scope", "_account_data"]),
    ("อ่านกราฟจากประวัติแล้วกลับไปยังประวัติ", ["mastery_dashboard_screen", "_history", "_chart_history", "_chart_history_read", "_history"]),
    ("นำเข้าคำมาฝึกแล้วเปิดคำแปลทั้งสองคำ", IMPORT_PATH + ["_import_json", "_import_deck", "_import_card_1", "_import_reveal_1", "_import_card_2", "_import_reveal_2", "_import_deck_done", LIB]),
    ("แก้ชุดคำที่อ่านไม่ได้แล้วกลับมาดูคำก่อนฝึก", IMPORT_PATH + ["_import_json_bad", "_import_json_error", "_import_json", "_import_deck", IMPORT, LIB]),
    ("ดูพื้นหลังที่มีจากร้านแล้วกลับไปร้านเดิม", [PROFILE, "achievements_screen", "shop_page", "_wallpaper_preview", "shop_page"]),
    ("ปิดการลองพื้นหลังแล้วกลับไปหน้าแต่งตัวละคร", [PROFILE, "achievements_screen", "avatar_equipment_screen", "_wall_avatar", "_wall_avatar_preview", "_wall_avatar", "avatar_equipment_screen"]),
    ("เลือกเสียงจากเมนูฝึกฟังแล้วกลับเมนูเดิม", [TODAY, MENU, "_listening", "_ipa_hub", "_ipa_think_hub", "_ipa_hub", "_listening"]),
]

EXPECT = {name: observation for (name, _), observation in zip(CASES, [
    ("_phonetic_play", "ห่อริมฝีปากเล็กน้อยแล้วปล่อยลม"),
    ("_ipa_read", "เสียง /ʃ/ อยู่หลังสระ /eɪ/"),
    ("_boss_word_review", "เราต้องการพลังงานที่ยั่งยืน"),
    (RESULT, "ephemeral · meticulous · sustainable"),
    ("_appearance_focus", "สมาธิ · กำลังใช้"),
    (WALL, "มาตรฐาน · กำลังใช้"),
    ("_sentence_done", "I have a ticket."),
    ("_sentence_retry", "I have ticket a."),
    ("_playlist_finished", "station · platform · ticket"),
    ("_playlist_stopped_2", "หยุดที่คำ 2 จาก 3"),
    ("_chart_account_read", "2.4 วินาที  →  1.6 วินาที"),
    ("_chart_account_scope", "ต้นแบบไม่มีการลงทะเบียนหรือส่งข้อมูลวิจัย"),
    ("_chart_history_read", "2 จาก 5  →  3 จาก 5"),
    ("_import_deck_done", "wallet · กระเป๋าสตางค์"),
    ("_import_json_error", "ขาดเครื่องหมาย ] ที่ท้ายรายการ"),
    ("_wallpaper_preview", "คุณมีพื้นหลังนี้แล้ว"),
    ("_wall_avatar", "มาตรฐาน · กำลังใช้"),
    ("_ipa_think_hub", "วางปลายลิ้นระหว่างฟันแล้วพ่นลมเบา ๆ"),
], strict=True)}

OWNERS = {name: owner for (name, _), owner in zip(CASES, [
    IPA, IPA, RESULT, RESULT, WALL, WALL, ARRANGE, ARRANGE, PLAY, PLAY,
    CHART, CHART, CHART, IMPORT, IMPORT, WALL, WALL, IPA,
], strict=True)}


def page(family, title, section, blocks, *buttons):
    return family, title, section, blocks, list(buttons), None


def buttons(screens, key, *actions):
    family, title, section, blocks, _, tab = screens[key]
    screens[key] = family, title, section, blocks, list(actions), tab


def redirect(screens, key, old, new):
    family, title, section, blocks, actions, tab = screens[key]
    blocks = [(*block[:-1], new) if block[0] in ("row", "choice") and block[-1] == old else block for block in blocks]
    actions = [(label, new if dest == old else dest) for label, dest in actions]
    screens[key] = family, title, section, blocks, actions, tab


def install(s):
    phonetics(s)
    spelling_result(s)
    wallpaper(s)
    arrange_sentence(s)
    playlist(s)
    sample_chart(s)
    wordbook(s)


def phonetics(s):
    sounds = [
        ("/æ/", "cat", "แมว", "อ้าปากแล้วออกเสียงสระสั้น", "_ipa_cat"),
        ("/θ/", "think", "คิด", "วางปลายลิ้นระหว่างฟันแล้วพ่นลมเบา ๆ", "_ipa_think"),
        ("/ʃ/", "she", "เธอ", "ห่อริมฝีปากเล็กน้อยแล้วปล่อยลม", "_phonetic_play"),
        ("/ʒ/", "vision", "การมองเห็น", "เสียงกลางคำคล้าย /ʃ/ แต่เส้นเสียงสั่น", "_ipa_vision"),
        ("/ŋ/", "sing", "ร้องเพลง", "ยกโคนลิ้นแล้วปล่อยเสียงออกทางจมูก", "_ipa_sing"),
        ("/iː/", "see", "เห็น", "เหยียดริมฝีปากแล้วลากเสียงสระยาว", "_ipa_see"),
    ]
    family, title, section, blocks, _, tab = s[IPA]
    s[IPA] = family, title, section, blocks, [("ลองเสียง /ʃ/ ในคำว่า she", "_phonetic_play"), ("เลือกเสียงอื่น", "_ipa_index")], tab
    s["_ipa_index"] = page("audio", "เลือกเสียงที่อยากฝึก", "การออกเสียงภาษาอังกฤษ",
        [("row", f"{ipa}    {word}", meaning, key) for ipa, word, meaning, _, key in sounds])
    for ipa, word, meaning, cue, key in sounds:
        s[key] = page("audio", f"เสียงในคำว่า {word}", "การออกเสียงภาษาอังกฤษ", [
            ("hero", "คำตัวอย่าง", word, meaning), ("quote", f"ลองออกเสียง  {ipa}", cue, "พูดช้า ๆ แล้วลองพูดทั้งคำอีกครั้ง"),
        ], ("เลือกเสียงอื่น", "_ipa_index"), ("กลับไปดูคำว่า station", WORD))
    ipa_blocks = s["_phonetic_play"][3]
    ipa_blocks.append(("row", "เมื่อเปิดเสียงไม่ได้", "อ่านวิธีวางปากและหาตำแหน่งเสียง", "_ipa_read"))
    s["_ipa_read"] = page("audio", "ฝึกจากตำแหน่งปาก", "แทนการฟังเสียงตัวอย่าง", [
        ("quote", "เสียงลม  /ʃ/", "ห่อปากเล็กน้อยแล้วพ่นลมยาว", "เสียงนี้อยู่ต้นคำว่า she"),
        ("lines", "ลองหาเสียงเดียวกัน", "station   /ˈsteɪʃən/", "เสียง /ʃ/ อยู่หลังสระ /eɪ/"),
    ], ("กลับไปอ่านคำว่า station", WORD), ("เลือกเสียงอื่น", "_ipa_index"))
    redirect(s, "_listening", IPA, "_ipa_hub")
    s["_ipa_hub"] = page("audio", "เลือกเสียงที่อยากฝึก", "ฟังและพูด", [
        ("row", f"{ipa}    {word}", meaning, key + "_hub") for ipa, word, meaning, _, key in sounds
    ], ("กลับไปเลือกแบบฝึกฟัง", "_listening"))
    for ipa, word, meaning, cue, key in sounds:
        s[key + "_hub"] = page("audio", f"เสียงในคำว่า {word}", "เลือกเสียงฝึก", [
            ("hero", ipa, word, meaning), ("note", "ลองออกเสียงดู", cue),
        ], ("กลับไปเลือกเสียง", "_ipa_hub"))
    redirect(s, "speak_to_text_screen", IPA, "_ipa_no_mic")
    s["_ipa_no_mic"] = page("audio", "ฝึกคำเดิมโดยไม่ใช้ไมค์", "ฝึกพูด · station", [
        ("quote", "ลองเทียบเสียง /ʃ/", "she  →  station", "ห่อริมฝีปากแล้วปล่อยลมผ่านช่องแคบ ๆ"),
        ("note", "ลองออกเสียง station ทั้งคำ", "สังเกตเสียง /ʃ/ หลังพยางค์แรก"),
    ], ("กลับไปฝึกพูด", "speak_to_text_screen"), ("อ่านคำศัพท์เดิม", WORD))


def spelling_result(s):
    s[RESULT] = page("result", "ผ่านด่านสะกดคำแล้ว", "เกมฝึกคำ · ผลรอบนี้", [
        ("stat", "3 คำ", "ที่สะกดผ่าน", "ephemeral · meticulous · sustainable"),
        ("row", "ทวนคำสุดท้าย", "ดูความหมายและตัวอย่างของ sustainable", "_boss_word_review"),
    ], ("เลือกเกมอื่น", GAMES), ("กลับหน้าฝึกภาษา", TODAY))
    s["_boss_word_review"] = page("reader", "ทวนคำสุดท้าย", "ด่านสะกดคำ", [
        ("hero", "คำคุณศัพท์", "sustainable", "ยั่งยืน"),
        ("quote", "ตัวอย่างการใช้", "We need sustainable energy.", "เราต้องการพลังงานที่ยั่งยืน"),
    ], ("เลือกเกมอื่น", GAMES), ("กลับไปดูผล", RESULT))


def wallpaper(s):
    s[WALL] = page("settings", "พื้นหลังหน้าฝึก", "การแสดงผล · ของที่มี", [
        ("quote", "มาตรฐาน · กำลังใช้", "borrow", "May I borrow your pen?"),
        ("row", "พื้นหลังสมาธิ", "มีอยู่แล้ว · ดูตัวอย่างก่อนใช้", "_wall_focus_preview"),
        ("row", "ร้านของตกแต่ง", "ดูของอื่นและเหรียญที่มี", "shop_page"),
    ], ("กลับไปที่การแสดงผล", PREF))
    s["_wall_focus_preview"] = page("settings", "ลองพื้นหลังสมาธิ", "ตัวอย่างก่อนใช้", [
        ("quote", "บัตรคำบนพื้นหลังสมาธิ", "borrow", "ขอยืม"),
        ("note", "พื้นหลังนี้อยู่ในของสะสมแล้ว", "ใช้ได้ทันทีโดยไม่เสียเหรียญเพิ่ม"),
    ], ("ใช้พื้นหลังนี้", "_wall_focus_applied"), ("เก็บพื้นหลังเดิม", WALL))
    s["_wall_focus_applied"] = page("settings", "ใช้พื้นหลังสมาธิแล้ว", "พื้นหลังหน้าฝึก", [
        ("quote", "พื้นหลังสมาธิ · กำลังใช้", "borrow", "May I borrow your pen?"),
        ("note", "พื้นหลังของบัตรคำเปลี่ยนแล้ว", "เปลี่ยนกลับเป็นพื้นหลังมาตรฐานได้"),
    ], ("กลับไปที่การแสดงผล", "_appearance_focus"), ("ใช้พื้นหลังมาตรฐาน", PREF))
    s["_appearance_focus"] = page("settings", "การแสดงผล", "ตั้งค่า", [
        ("quote", "ตัวอย่างหน้าฝึก · พื้นหลังสมาธิ", "borrow", "ยืมของมาใช้แล้วคืน"),
        ("row", "พื้นหลังหน้าฝึก", "สมาธิ · กำลังใช้", "_wall_focus_applied"),
    ], ("กลับไปที่ตั้งค่า", "setting_screen"))
    s["_wallpaper_preview"] = page("settings", "ตัวอย่างพื้นหลังสมาธิ", "ร้านของตกแต่ง · ราคาปกติ 60 เหรียญ", [
        ("quote", "บัตรคำบนพื้นหลังสมาธิ", "borrow", "ขอยืม"),
        ("note", "คุณมีพื้นหลังนี้แล้ว", "เลือกใช้ได้โดยไม่เสียเหรียญเพิ่ม"),
    ], ("ใช้พื้นหลังนี้", "_wall_shop_applied"), ("กลับไปที่ร้าน", "shop_page"))
    s["_wall_shop_applied"] = page("settings", "ใช้พื้นหลังสมาธิแล้ว", "ร้านของตกแต่ง", [
        ("quote", "สมาธิ · กำลังใช้", "borrow", "ขอยืม"),
    ], ("กลับไปที่ร้าน", "shop_page"))
    for source, key in [("avatar_equipment_screen", "_wall_avatar"), ("_hat_equipped", "_wall_hat"),
                        ("_equipment_from_shop", "_wall_outfit"), ("_hat_equipped_shop", "_wall_shop_hat")]:
        if source not in s:
            continue
        redirect(s, source, WALL, key)
        preview, applied = key + "_preview", key + "_applied"
        s[key] = page("settings", "พื้นหลังหน้าฝึก", "ของตกแต่งของฉัน", [
            ("quote", "มาตรฐาน · กำลังใช้", "borrow", "ขอยืม"),
            ("row", "พื้นหลังสมาธิ", "มีอยู่แล้ว · ดูตัวอย่างก่อนใช้", preview),
        ], ("กลับไปแต่งตัวละคร", source))
        s[preview] = page("settings", "ลองพื้นหลังสมาธิ", "ของตกแต่งของฉัน", [
            ("quote", "บัตรคำบนพื้นหลังสมาธิ", "borrow", "ขอยืม"),
        ], ("ใช้พื้นหลังนี้", applied), ("เก็บพื้นหลังเดิม", key))
        s[applied] = page("settings", "ใช้พื้นหลังสมาธิแล้ว", "ของตกแต่งของฉัน", [
            ("quote", "สมาธิ · กำลังใช้", "borrow", "ขอยืม"),
        ], ("กลับไปแต่งตัวละคร", source), ("ใช้พื้นหลังมาตรฐาน", key))


def arrange_sentence(s):
    for key, assembled, remaining in [
        (ARRANGE, "I have", [("ticket", "_arrange_ticket"), ("a", "_arrange_a")]),
        ("_arrange_a", "I have a", [("ticket", "_sentence_check_ok")]),
        ("_arrange_ticket", "I have ticket", [("a", "_sentence_check_swap")]),
    ]:
        actions = [("ออกจากแบบฝึก", GAMES)] if key == ARRANGE else [("เอาคำล่าสุดออก", ARRANGE)]
        s[key] = page("practice", "เรียงคำให้จบประโยค", "ที่สถานี · ฉันมีตั๋วหนึ่งใบ", [
            ("quote", "สองคำแรกมีให้แล้ว", assembled + " …", "แตะคำถัดไปจนครบ แล้วตรวจคำตอบ"),
            *[("choice", word, dest) for word, dest in remaining],
        ], *actions)
    for key, words, verdict, previous in [
        ("_sentence_check_ok", "I have a ticket.", "_sentence_done", "_arrange_a"),
        ("_sentence_check_swap", "I have ticket a.", "_sentence_retry", "_arrange_ticket"),
    ]:
        s[key] = page("practice", "ตรวจประโยคของคุณ", "ที่สถานี · ฉันมีตั๋วหนึ่งใบ", [
            ("quote", "เรียงครบแล้ว", words, "อ่านทวนก่อนตรวจคำตอบ"),
        ], ("ตรวจคำตอบ", verdict), ("เอาคำล่าสุดออก", previous))
    s["_sentence_retry"] = page("practice", "ลองสลับตำแหน่งคำ", "เรียงประโยค", [
        ("quote", "คำตอบเมื่อครู่", "I have ticket a.", "วาง a หน้าคำนามที่นับได้หนึ่งอย่าง"),
    ], ("กลับไปเรียงใหม่", ARRANGE), ("กลับไปที่เกมฝึกคำ", GAMES))
    # Feedback from the exercise that suggested this game remains the return point.
    exercise = [ARRANGE, "_arrange_a", "_arrange_ticket", "_sentence_check_ok", "_sentence_check_swap", "_sentence_retry", "_sentence_done"]
    for origin, suffix, label in [("_spell_done", "_spell", "กลับไปดูผลสะกดคำ"), ("_fill_right", "_fill", "กลับไปดูผลเติมคำ")]:
        keys = {key: ("_sentence_start" if key == ARRANGE else key) + suffix for key in exercise}
        redirect(s, origin, ARRANGE, keys[ARRANGE])
        for key in exercise:
            family, title, section, blocks, actions, tab = s[key]
            mapped = [(*block[:-1], keys.get(block[-1], block[-1])) if block[0] in ("row", "choice") else block for block in blocks]
            links = [(label, origin) if dest == GAMES else (name, keys.get(dest, dest)) for name, dest in actions]
            s[keys[key]] = family, title, section, mapped, links, tab


def playlist(s):
    redirect(s, "_listening", PLAY, "_listen_choose_set")
    s["_listen_choose_set"] = page("audio", "เลือกชุดที่จะฟัง", "ฟังและพูด", [
        ("row", "การเดินทาง", "เปิดชุด 3 คำ แล้วเลือกฟังจากชุดนี้", SET),
    ], ("กลับไปเลือกแบบฝึกฟัง", "_listening"))
    for position, playing, following, word in [
        (1, "_playlist_play", "_playlist_next", "station"),
        (2, "_playlist_next", "_playlist_last", "platform"),
    ]:
        stopped = f"_playlist_stopped_{position}"
        buttons(s, playing, ("ฟังคำถัดไป", following), ("หยุดฟัง", stopped))
        s[stopped] = page("audio", "หยุดฟังแล้ว", "ชุดการเดินทาง", [
            ("hero", f"หยุดที่คำ {position} จาก 3", word, "กลับมาเริ่มฟังชุดนี้ใหม่ได้"),
        ], ("กลับไปดูชุดการเดินทาง", SET), ("ฟังตั้งแต่คำแรก", "_playlist_play"))
    family, _, section, blocks, _, tab = s["_playlist_last"]
    s["_playlist_last"] = family, "ฟังคำสุดท้าย", section, blocks, [
        ("จบการฟังชุดนี้", "_playlist_finished"), ("ฟังตั้งแต่คำแรก", "_playlist_play")], tab
    s["_playlist_finished"] = page("audio", "ฟังจบชุดแล้ว", "ชุดการเดินทาง", [
        ("lines", "คำที่ฟังในชุดนี้", "station · platform · ticket", "สถานี · ชานชาลา · ตั๋ว"),
    ], ("กลับไปดูชุดการเดินทาง", SET), ("ฟังอีกครั้ง", "_playlist_play"))


def sample_chart(s):
    for source, key, prefix, label in [
        ("_account_data", CHART, "_chart_account", "ข้อมูลของฉัน"),
        ("_history", "_chart_history", "_chart_history", "ประวัติการฝึก"),
        ("_research_choice", "_chart_research", "_chart_research", "งานวิจัยและการเรียน"),
    ]:
        if key != CHART:
            redirect(s, source, CHART, key)
        s[key] = page("result", "อ่านกราฟตัวอย่าง", "ผู้เรียนสมมติหนึ่งคน · ชุดคำเดียวกัน", [
            ("meter", "ก่อนฝึก   2 จาก 5 ข้อ", .4), ("meter", "หลังฝึก   3 จาก 5 ข้อ", .6),
            ("row", "เวลาในการตอบ", "ดูผลรอบแรกและรอบหลัง", prefix + "_read"),
            ("row", "ข้อมูลนี้มาจากไหน", "ดูขอบเขตของตัวอย่าง", prefix + "_scope"),
        ], ("กลับไปที่" + label, source))
        s[prefix + "_read"] = page("result", "เปรียบเทียบสองรอบ", "ข้อมูลสมมติ · คำชุดเดิม 5 ข้อ", [
            ("lines", "ตอบถูกเพิ่มขึ้น 1 ข้อ", "2 จาก 5  →  3 จาก 5", "ข้อที่ตอบถูกคิดเป็น 40% และ 60%"),
            ("lines", "เวลาตอบเฉลี่ยต่อข้อ", "2.4 วินาที  →  1.6 วินาที", "ตัวอย่างนี้บอกเฉพาะสิ่งที่เกิดในสองรอบ"),
        ], ("กลับไปที่" + label, source), ("ดูกราฟอีกครั้ง", key))
        s[prefix + "_scope"] = page("settings", "ที่มาของตัวเลข", "ตัวอย่างสำหรับฝึกอ่านกราฟ", [
            ("note", "ตัวเลขทั้งหมดเป็นข้อมูลสมมติ", "ต้นแบบไม่มีการลงทะเบียนหรือส่งข้อมูลวิจัย"),
        ], ("กลับไปที่" + label, source), ("กลับไปดูกราฟ", key))


def wordbook(s):
    s[IMPORT] = page("form", "นำเข้าชุดคำ", "คลังคำ", [
        ("row", "เพิ่มคำจากตารางเข้าคลัง", "คำบนรถไฟ.csv · ตรวจคำซ้ำและคำแปล", "add_multiple_words_screen"),
        ("row", "วางคำจากตาราง", "วางคำและคำแปลก่อนเพิ่มเข้าคลัง", "_paste_words"),
        ("row", "ฝึกจากรายการ JSON", "ลองนำคำจากไฟล์ตัวอย่างมาฝึกทันที", "_import_json"),
        ("row", "ลองไฟล์ที่รูปแบบผิด", "ดูวิธีแก้เมื่ออ่านชุดคำไม่ได้", "_import_json_bad"),
    ], ("กลับคลังคำ", LIB))
    for key, correct in [("_import_json", True), ("_import_json_bad", False)]:
        s[key] = page("form", "ตรวจรายการจากไฟล์", "ของในกระเป๋า.json · ข้อมูลตัวอย่าง", [
            ("lines", "รายการในไฟล์", "pencil · ดินสอ", "wallet · กระเป๋าสตางค์"),
            ("field", "อักขระปิดท้ายรายการ", "]" if correct else "ยังไม่มี ]"),
        ], ("อ่านรายการคำ", "_import_deck" if correct else "_import_json_error"), ("ยกเลิก", IMPORT))
    s["_import_json_error"] = page("form", "ยังอ่านไฟล์นี้ไม่ได้", "ของในกระเป๋า.json", [
        ("note", "ขาดเครื่องหมาย ] ที่ท้ายรายการ", "แก้เครื่องหมายแล้วลองอ่านรายการอีกครั้ง"),
        ("lines", "คำที่ยังอยู่ในร่าง", "pencil · ดินสอ", "wallet · กระเป๋าสตางค์"),
    ], ("เติม ] ในร่าง", "_import_json"), ("ยกเลิกการนำเข้า", IMPORT))
    s["_import_deck"] = page("list", "พร้อมฝึก 2 คำ", "ของในกระเป๋า.json · ใช้ฝึกรอบนี้", [
        ("row", "pencil", "ดินสอ", None), ("row", "wallet", "กระเป๋าสตางค์", None),
        ("note", "เริ่มจากนึกคำแปลเอง", "แตะเปิดคำแปลเพื่อตรวจคำตอบ"),
    ], ("ฝึกสองคำนี้", "_import_card_1"), ("กลับไปเลือกไฟล์", IMPORT))
    for index, word, meaning, following in [(1, "pencil", "ดินสอ", "_import_card_2"), (2, "wallet", "กระเป๋าสตางค์", "_import_deck_done")]:
        key = f"_import_card_{index}"
        answer = f"_import_reveal_{index}"
        s[key] = page("practice", "นึกคำแปล", f"ของในกระเป๋า · คำที่ {index} จาก 2", [
            ("hero", "ภาษาอังกฤษ", word, "คำนี้แปลว่าอะไร"),
        ], ("เปิดคำแปล", answer), ("เลิกฝึกรอบนี้", "_import_deck"))
        s[answer] = page("practice", "ตรวจคำแปลของคุณ", f"ของในกระเป๋า · คำที่ {index} จาก 2", [
            ("hero", "ภาษาอังกฤษ", word, meaning),
        ], ("จำได้แล้ว", following), ("ลองนึกอีกครั้ง", key))
    s["_import_deck_done"] = page("result", "ฝึกครบทั้งสองคำแล้ว", "ของในกระเป๋า.json · ฝึกจากไฟล์", [
        ("lines", "คำที่เปิดทบทวน", "pencil · ดินสอ", "wallet · กระเป๋าสตางค์"),
        ("note", "ชุดนี้ใช้สำหรับรอบที่เพิ่งฝึก", "ไฟล์ต้นฉบับยังใช้ฝึกรอบใหม่ได้"),
    ], ("กลับคลังคำ", LIB), ("ทบทวนอีกครั้ง", "_import_deck"))


def render(d):
    """Draw the same card on each wallpaper preview so the actual fill is comparable."""
    preview = d.key in ("_wallpaper_preview", "_appearance_focus") or (
        d.key.startswith("_wall_") and d.key.endswith(("_applied", "_preview")))
    if not preview:
        return False
    _, title, section, blocks, actions, _ = d.screens[d.key]
    d.back()
    d.text(24, 78, title, 26, d.ink, True, 342)
    d.text(24, 128, section, 16, d.sub, False, 342)
    card = d.add(d.frame, "frame", "ตัวอย่างพื้นหลังสมาธิ", 24, 184, 342, 196,
                 "#EFF8FA", children=[], corners={"radii": [14] * 4, "smoothing": 0})
    d.text(20, 17, blocks[0][1], 15, "#425866", True, 301, card)
    d.text(18, 64, "borrow", 40, "#203540", True, 301, card)
    d.text(20, 139, blocks[0][3], 18, "#344854", False, 301, card)
    top = 410
    for kind, *content in blocks[1:]:
        if kind == "row":
            name, detail, dest = content
            item = d.link(24, top, 342, 58, name, dest)
            d.text(0, 2, name, 18, d.ink, True, 305, item)
            d.text(0, 32, detail, 15, d.sub, False, 305, item)
            d.text(319, 11, "›", 21, d.ink, True, 22, item)
        else:
            d.text(24, top, content[0], 18, d.ink, True, 342)
            d.text(24, top + 29, content[1], 15, d.sub, False, 342)
        top += 77
    for i, (label, target) in enumerate(actions):
        item = d.link(24, top + i * 62, 342, 51, label, target, "#3942AD" if i == 0 else "#EBEDF9", 8)
        d.text(16, 10, label, 18, "#FFFFFF" if i == 0 else d.ink, True, 307, item)
    return True
