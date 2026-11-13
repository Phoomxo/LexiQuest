"""Learner journeys for content, practice modes and recall (f01–f15)."""
from hashlib import sha256
from math import hypot

from exam_routes import add_round, example

HOME = "choose_mode_screen"
LIB = "categories_page"
MENU = "main_navigation_screen"
SETS = "select_category_for_quiz"
METHOD = "_exam_planned"
REVIEW = "srs_flashcards_screen"
W = "_word"
SHELF = [LIB, "_packs"]
LESSON = [HOME, SETS]
TYPES = LESSON + [METHOD]


def add(s, key, blocks=(), buttons=()):
    family, title, sub, old, actions, tab = s[key]
    s[key] = family, title, sub, [*old, *blocks], [*actions, *buttons], tab


def row(label, detail, dest=None):
    return "row", label, detail, dest


PACKS = [
    ("_pack", "การเดินทาง", "A2", "อ่านป้ายที่สถานี", "อ่าน", "เดินทางเอง",
     (("station", "สถานี"), ("platform", "ชานชาลา")), "_pack_train_proof"),
    ("_kitchen_pack", "ของใช้ในครัว", "A1", "เรียกชื่อของที่ใช้ทุกวัน", "นึกความหมาย", "ใช้คำในบ้าน",
     (("cup", "ถ้วย"), ("spoon", "ช้อน")), "_pack_kitchen_proof"),
]


def catalog(s):
    s["_packs"] = example("list", "เลือกชุดคำศัพท์", "มี 2 ชุดในคลังตัวอย่าง", [
        row("เลือกตามระดับหรือสิ่งที่อยากฝึก", "ระดับภาษา หัวข้อ ทักษะ หรือเป้าหมาย", "_pack_filter"),
        *[row(name, level + " · " + goal, key) for key, name, level, goal, *_ in PACKS],
    ], [("กลับคลังคำ", LIB)])
    filters = (
        ("ระดับภาษา", "A1 หรือ A2", "level", 2), ("หัวข้อ", "การเดินทางหรือของใช้ในครัว", "topic", 1),
        ("ทักษะ", "อ่านหรือนึกความหมาย", "skill", 4), ("เป้าหมาย", "เดินทางเองหรือใช้คำในบ้าน", "goal", 5),
    )
    s["_pack_filter"] = example("list", "ค้นชุดที่เหมาะกับฉัน", "เลือกสิ่งที่จะใช้หาชุดเรียน", [
        row(label, summary, "_filter_" + field) for label,summary,field,_ in filters
    ], [("ดูทุกชุด", "_packs")])
    for label, _, field, index in filters:
        choices = []
        for i, pack in enumerate(PACKS):
            key, name, level, aim = pack[:4]
            option = pack[index]
            target = f"_pack_match_{field}_{i}"
            choices.append(("choice", option, target))
            s[target] = example("list", "ชุดเรียนที่ตรงกัน", f"{label} · {option} · พบ 1 ชุด", [
                row(name, level + " · " + aim, key),
            ], [("เลือกตัวกรองใหม่", "_pack_filter"), ("ล้างตัวกรอง", "_packs")])
        s["_filter_" + field] = example("list", "เลือก" + label, "เลือกชุดคำศัพท์", choices)
    for key, name, level, aim, _, _, words, proof in PACKS:
        detail = [
            ("lines", "เมื่อฝึกจบ", aim, f"{level} · 2 คำ · ชุดตัวอย่างฉบับ 1"),
            row("คำศัพท์ในชุด", " · ".join(x for x, _ in words), key + "_words"),
            row("ความคืบหน้า", "ยังไม่ได้เริ่มฝึกทั้งสองคำ"),
            row("ที่มาของชุดเรียน", "ผู้จัดทำ รุ่นเนื้อหา และสถานะการเผยแพร่", "_provenance" if key == "_pack" else proof),
        ]
        s[key] = example("list", name, "ชุดเรียนในเครื่อง", detail, [
            ("เลือกวิธีฝึก", key + "_practice"), ("กลับไปยังรายการก่อนหน้า", "@back"),
            ("ดูชุดเรียนทั้งหมด", "_packs"),
        ])
        s[key + "_words"] = example("list", "คำศัพท์ในชุด", f"{name} · {level}", [
            row(word, meaning) for word, meaning in words
        ], [("กลับไปดูชุดเรียน", key)])
        s[key + "_practice"] = example("list", "เลือกวิธีฝึก", name + " · 2 คำ", [
            row("ทบทวนด้วยบัตรคำ", "นึกความหมายแล้วเปิดคำแปล", key + "_card0"),
            row("เลือกความหมาย", "ตอบสองข้อแล้วดูผลทีละคำ", key + "_q1"),
        ], [("กลับไปดูชุดเรียน", key)])
        add_round(s, key[1:], words, name, key)
        for i,(word, meaning) in enumerate(words):
            s[key + f"_card{i}"] = example("practice", "นึกความหมาย", f"{name} · คำที่ {i+1} จาก 2", [
                ("hero", "คำนี้แปลว่าอะไร", word, "ลองนึกความหมายด้วยตัวเอง"),
            ], [("เปิดคำแปล", key + f"_answer{i}")])
            s[key + f"_answer{i}"] = example("practice", "เทียบกับคำที่นึกไว้", name, [
                ("hero", word, meaning, f"คำที่ {i+1} จาก 2"),
            ], [("ทบทวนคำถัดไป" if i == 0 else "จบการทบทวน", key + ("_card1" if i == 0 else "_card_done")),
                ("ลองนึกอีกครั้ง", key + f"_card{i}")])
        s[key + "_card_done"] = example("result", "ทบทวนครบ 2 คำแล้ว", name, [
            row(w, m) for w, m in words
        ], [("กลับไปดูชุดที่เพิ่งฝึก", key + "_reviewed")])
        s[key + "_reviewed"] = example("list", name, "ผลจากรอบบัตรคำเมื่อสักครู่", [
            ("lines", "ทบทวนด้วยบัตรคำ", "เปิดทบทวนแล้ว 2 จาก 2 คำ", " · ".join(w for w,_ in words)),
            row("ดูคำที่เพิ่งทบทวน", "เปิดรายการคำและความหมาย", key + "_words_reviewed"),
        ], [("เลือกชุดอื่น", "_packs")])
        s[key + "_words_reviewed"] = example("list", "คำที่เพิ่งทบทวน", name, [
            row(word, meaning) for word, meaning in words
        ], [("กลับไปดูผลการทบทวน", key + "_reviewed")])
        revision = "LQ-TR-01" if key == "_pack" else "LQ-KT-01"
        digest = sha256("\n".join(f"{w}\t{m}" for w, m in words).encode()).hexdigest()
        s[proof] = example("reader", "ที่มาของชุดเรียน", f"{name} · {revision}", [
            row("ผู้จัดทำ", "ตัวอย่างประกอบการออกแบบของ LexiQuest"),
            row("สถานะการตรวจ", "ร่างตัวอย่าง ยังไม่เผยแพร่ให้ผู้เรียน"),
            ("lines", "รหัสตรวจสอบรายการคำ · SHA-256", digest[:32], digest[32:]),
        ], [("กลับไปดูชุดเรียน", key)])
    add(s, "_provenance", [row("ตรวจรุ่นของชุดการเดินทาง", "รหัสชุดและสถานะการเผยแพร่", "_pack_train_proof")])
    s["_station_details"] = example("reader", "รู้จักคำว่า station", "ชุดการเดินทาง · ระดับ A2 ของชุดนี้", [
        ("lines", "คำนาม", "station  /ˈsteɪʃən/", "สถานี เช่น สถานีรถไฟหรือสถานีขนส่ง"),
        ("quote", "คำที่ใช้ร่วมกัน", "railway station · สถานีรถไฟ", "bus station · สถานีขนส่ง"),
        ("lines", "คำใกล้เคียงตามบริบท", "stop · จุดจอด", "station ไม่มีคำตรงข้ามที่ใช้ทั่วไป"),
    ], [("กลับไปที่บัตรคำ", "@back")])


def exercises(s):
    family,title,section,blocks,buttons,tab = s[SETS]
    s[SETS] = (family,title,section,blocks,[
        ("เลือกรูปแบบโจทย์" if dest == METHOD else label, dest) for label,dest in buttons],tab)
    _, _, _, choices, buttons, _ = s[METHOD]
    s[METHOD] = example("list", "เลือกรูปแบบโจทย์", "ชุดการเดินทาง", choices, [("กลับไปเลือกชุดคำ", SETS)])
    for key in ("_travel_q20", "_travel_q21"):
        held = key + "_pause"
        add(s,key,buttons=[("พักรอบนี้", held)])
        s[held] = example("practice", "พักรอบฝึก", "ชุดการเดินทาง · ตอบไปแล้ว 1 จาก 2 ข้อ", [
            ("quote", "กลับมาฝึกต่อได้จากข้อเดิม", "platform", "คำตอบข้อแรกยังอยู่ในรอบนี้"),
        ], [("ทำข้อที่สองต่อ", key)])
    add(s,METHOD,[row("เลือกคำอังกฤษจากความหมายไทย", "สลับภาษาของคำถามและคำตอบ", "_reverse_word")])
    s["_reverse_word"] = example("practice", "เลือกคำภาษาอังกฤษ", "การเดินทาง · ข้อ 1 จาก 1", [
        ("hero", "คำไหนมีความหมายตรงกัน", "ชานชาลา", "เลือกคำภาษาอังกฤษ"),
        ("choice", "station", "_reverse_try"), ("choice", "platform", "_reverse_win"),
    ])
    s["_reverse_try"] = example("practice", "ลองอีกครั้ง", "การเดินทาง", [
        ("quote", "คุณเลือก station", "station คือสถานีทั้งแห่ง", "ชานชาลาคือบริเวณที่ยืนรอขึ้นรถไฟ"),
    ], [("กลับไปเลือกคำตอบ", "_reverse_word"), ("เลือกรูปแบบโจทย์อื่น", METHOD)])
    s["_reverse_win"] = example("result", "เลือกคำได้ถูกต้อง", "การเดินทาง · 1 จาก 1 ข้อ", [
        ("quote", "คำที่คุณเลือก", "platform · ชานชาลา", "Wait on platform two."),
    ], [("เลือกรูปแบบโจทย์อื่น", METHOD)])
    independent_recall(s)
    for key in ("_definition_quiz","_definition_yes","_definition_no","_matching","_matching_done",
                "_matching_pick0","_matching_pick1","_matching_error0","_matching_error1","_matching_left0","_matching_left1"):
        family,title,_,blocks,buttons,tab=s[key]
        s[key]=family,title,"ชุดการเดินทาง",blocks,buttons,tab
    s["_scratch_confirm"] = example("form", "เทียบกับคำเฉลย", "เขียนคำว่า ตั๋ว", [
        ("hero", "คำเฉลย", "ticket", "เทียบลำดับตัวอักษรกับคำของตัวเอง"),
    ], [("ฉันสะกดตรงกับเฉลย", "_scratch_done"), ("ลองเขียนอีกครั้ง", "_scratchpad"), ("แก้ด้วยการพิมพ์", "_scratch_type")])
    s["_scratch_done"] = example("result", "ตรวจคำของตัวเองแล้ว", "กระดานฝึกเขียน", [
        ("quote", "คุณประเมินว่าตรงกับเฉลย", "ticket · ตั๋ว", "รอยเขียนใช้เฉพาะการฝึกครั้งนี้"),
    ], [("เลือกรูปแบบโจทย์อื่น", METHOD)])
    for key in ("_scratchpad","_scratch_stroke","_scratch_word","_scratch_type"):
        family,title,_,blocks,buttons,tab=s[key]
        s[key]=family,title,"คำว่า ตั๋ว · ชุดการเดินทาง",blocks,buttons,tab
    s["_recall_ladder"] = example("list", "ฝึกให้นึกคำได้เอง", "ชุดการเดินทาง · station", [
        ("quote","เริ่มจากคำที่เคยเปิดทบทวน","station · สถานี","รอบนี้ลองเลือกคำแปลโดยไม่ดูคำใบ้"),
        row("ดูบัตรคำก่อน","กลับไปอ่านตัวอย่าง ถ้ายังนึกไม่ออก","_ladder_card"),
    ], [("ลองเลือกความหมาย", "_ladder_choose"), ("กลับไปเลือกสิ่งที่จะทบทวน", "_review_desk")])
    s["_ladder_card"] = example("reader", "บัตรคำที่ช่วยนึก", "การเดินทาง", [
        ("hero","station","สถานี","Meet me at the station."),
    ], [("ลองเลือกความหมาย", "_ladder_choose"), ("พักก่อน", "_recall_ladder")])
    s["_ladder_choose"] = example("practice", "เลือกความหมาย", "การเดินทาง · ฝึกให้นึกคำได้เอง", [
        ("hero","คำนี้หมายถึงอะไร","station","เลือกความหมายที่ตรงกับคำ"),
        ("choice","ชานชาลา","_ladder_hint"),("choice","สถานี","_ladder_advance"),
    ])
    s["_ladder_hint"] = example("practice", "ลองเทียบสองคำนี้", "คำที่เลือก · ชานชาลา", [
        ("lines","ชานชาลาเป็นส่วนหนึ่งของสถานี","station · สถานี","platform · ชานชาลา"),
    ], [("ลองเลือกความหมายอีกครั้ง","_ladder_choose"),("ดูบัตรคำก่อน","_ladder_card")])
    s["_ladder_advance"] = example("practice", "เลือกความหมายได้แล้ว", "station · สถานี", [
        ("note","ขั้นต่อไป ลองนึกคำเอง","คราวนี้จะเห็นแค่ประโยคกับคำแปล"),
    ], [("ลองนึกคำโดยไม่มีตัวเลือก","_ladder_write"),("ทบทวนขั้นเดิม","_ladder_choose")])
    s["_ladder_write"] = example("form","นึกคำที่หายไป","การเดินทาง · ไม่มีตัวเลือก",[
        ("quote","พรุ่งนี้ไปเจอกันที่สถานี","Meet me at the ____ tomorrow.","เติมคำอังกฤษที่หมายถึงสถานี"),
        ("field","คำที่พิมพ์ในตัวอย่าง","station"),
    ],[("ตรวจคำตอบ","_ladder_done"),("ขอคำใบ้","_ladder_card")])
    s["_ladder_done"] = example("result","นึกคำเองได้แล้ว","การเดินทาง",[
        ("quote","คำที่นึกได้","station · สถานี","Meet me at the station tomorrow."),
        ("note","รอบนี้ใช้ทั้งการเลือกและการนึกคำ","คุณเลือกความหมายได้ก่อนนึกคำจากประโยค"),
    ],[("กลับไปเลือกสิ่งที่จะทบทวน","_review_desk")])


def independent_recall(s):
    def draft(prefix):
        return "_source_recall" if not prefix else "_type_" + prefix

    word = "station"
    # The finite example permits either letter in the first position; all seven letters require input.
    for prefix in ("", *[word[:i] for i in range(1,8)], *["c"+word[1:i] for i in range(1,8)]):
        buttons = []
        if len(prefix) < len(word):
            choices = ["s", "c"] if not prefix else [word[len(prefix)]]
            buttons.extend(("เติมตัว " + letter, draft(prefix+letter)) for letter in choices)
        if prefix:
            buttons.append(("ลบตัวล่าสุด", draft(prefix[:-1])))
        if len(prefix)==len(word):
            buttons.insert(0, ("ตรวจคำตอบ", "_source_cue" if prefix==word else "_type_compare"))
        buttons.append(("พักการฝึก", "_type_leave" + (prefix or "_empty")))
        s[draft(prefix)] = example("form","นึกคำจากเรื่อง","ปิดบทอ่านแล้ว",[
            ("note","ทั้งสองคนนัดเจอกันที่ไหน","สะกดคำอังกฤษที่หมายถึงสถานี"),
            ("field","คำที่กำลังสะกด",prefix or "ยังไม่ได้ใส่ตัวอักษร"),
        ],buttons)
        s["_type_leave" + (prefix or "_empty")] = example("list","จะพักการฝึกไหม","ฝึกคำจากข้อความ",[
            ("field","คำตอบที่ยังเขียนไม่จบ",prefix or "ยังไม่ได้ใส่ตัวอักษร"),
        ],[("กลับมาเขียนต่อ",draft(prefix)),("ออกไปเลือกแบบฝึก","_source_choices")])
    s["_type_compare"] = example("reader","ตรวจตัวแรกอีกครั้ง","คำที่ส่ง · ctation",[
        ("quote","คำตอบที่ถูก","station","สังเกตตัว s ที่ต้นคำ"),
    ],[("แก้ตัวแรก","_type_tation"),("กลับไปดูคำที่ส่ง","_type_ctation")])
    s["_type_tation"] = example("form","เลือกตัวแรกใหม่","คำที่เหลือยังอยู่ครบ",[
        ("field","คำที่กำลังแก้","_tation"),
    ],[("เติม s หน้าคำ","_type_station"),("กลับไปดูคำที่ส่ง","_type_ctation")])
    for key in ("_source_recall_typo", "_source_cue_typo", "_source_write_typo", "_source_read_result_typo"):
        del s[key]


def install(s):
    catalog(s)
    exercises(s)


def render(d):
    # FigCraft supports click states. Each visible line is an editable segment of the example handwriting.
    if d.key not in {"_scratchpad","_scratch_stroke","_scratch_word"}:
        return False
    d.back()
    d.text(24,79,"เขียนคำว่า ตั๋ว",32,d.ink,True)
    d.text(24,132,"ลองเขียนเป็นภาษาอังกฤษ แล้วเทียบกับคำเฉลย",17,d.sub)
    d.box(24,203,342,205,"#F3F2ED",12,name="กระดานฝึกเขียน")
    d.box(45,333,299,1,"#AAA78F",name="เส้นบรรทัด")
    # The six letters are paths in a 25 × 49 letter space, with pen lifts between strokes.
    glyphs = {
        "t": [[(15,2),(12,34),(13,41),(19,42)],[(3,16),(25,15)]],
        "i": [[(13,20),(9,41),(17,41)],[(15,8),(15,10)]],
        "c": [[(24,22),(19,18),(11,19),(5,26),(4,35),(7,41),(15,42),(24,36)]],
        "k": [[(10,0),(5,41)],[(23,17),(8,31),(23,41)]],
        "e": [[(4,31),(15,29),(21,24),(19,19),(12,18),(5,25),(4,35),(8,41),(17,42),(23,38)]],
    }
    sample = {"_scratchpad":"","_scratch_stroke":"tick","_scratch_word":"ticket"}[d.key]
    for i,c in enumerate(sample):
        for path in glyphs[c]:
            for (x0,y0),(x1,y1) in zip(path,path[1:]):
                dx,dy=x1-x0,y1-y0
                length=hypot(dx,dy)
                nid=d.box(0,0,length,2.8,"#384384",1,name="รอยเขียน "+c)
                d.nodes[nid]["transform"]=[dx/length,dy/length,-dy/length,dx/length,75+i*37+x0,288+y0]
    d.text(26,434,"แตะเพื่อดูรอยเขียนตัวอย่าง",15,d.sub)
    from focused_learning import action
    if not sample:
        action(d,491,"ดูตัวอย่างการเขียน","_scratch_stroke")
        action(d,562,"ใช้ข้อความแทน","_scratch_type",False)
    else:
        label,target=("เขียนต่อให้จบคำ","_scratch_word") if sample=="tick" else ("เทียบกับคำเฉลย","_scratch_confirm")
        action(d,491,label,target)
        action(d,562,"ย้อนรอยเขียนล่าสุด","_scratchpad" if sample=="tick" else "_scratch_stroke",False)
        action(d,633,"ล้างกระดาน","_scratchpad",False)
    return True


TASKS = {
    1: ("เลือกระดับ A2 แล้วหาชุดคำที่ใช้เดินทาง", SHELF+["_pack_filter","_filter_level","_pack_match_level_0","_pack","_pack_match_level_0","_packs",LIB],
        "_pack_match_level_0","ระดับภาษา · A2 · พบ 1 ชุด","มีชุดตัวอย่างสองชุดและตัวกรองทีละเงื่อนไข"),
    2: ("ตรวจเนื้อหาชุดครัวแล้วทบทวนครบสองคำ", SHELF+["_kitchen_pack","_kitchen_pack_words","_kitchen_pack","_kitchen_pack_practice","_kitchen_pack_card0","_kitchen_pack_answer0","_kitchen_pack_card1","_kitchen_pack_answer1","_kitchen_pack_card_done","_kitchen_pack_reviewed","_packs",LIB],
        "_kitchen_pack_reviewed","เปิดทบทวนแล้ว 2 จาก 2 คำ","ความคืบหน้าเป็นผลของรอบตัวอย่างภายในต้นแบบ"),
    3: ("เปิดบัตร station แล้วเทียบกับคำว่า stop", [LIB,"vocab_list_screen",W,"_station_details",W,"vocab_list_screen",LIB],
        "_station_details","stop · จุดจอด","แสดงระดับของชุดและคำใกล้เคียงตามบริบท เสียงและระดับคำที่บรรณาธิการรับรองต้องตรวจในแอป"),
    4: ("ตรวจว่าเนื้อหาชุดครัวเป็นฉบับใด", SHELF+["_kitchen_pack","_pack_kitchen_proof","_kitchen_pack","_packs",LIB],
        "_pack_kitchen_proof","ร่างตัวอย่าง ยังไม่เผยแพร่ให้ผู้เรียน","รหัสตรวจสอบมาจากรายการคำตัวอย่าง การเผยแพร่และตรวจความถูกต้องของชุดจริงเป็นงานระบบ"),
    5: ("พักรอบสองคำแล้วทำข้อเดิมต่อจนเห็นผล", LESSON+["_travel_q1","_travel_f11","_travel_q21","_travel_q21_pause","_travel_q21","_travel_f211","_travel_done11",SETS],
        "_travel_done11","2 / 2","ตรวจจุดพักและผลรวมในรอบ การกู้รอบหลังปิดแอป เวลา และสัญญาเชื่อมแต่ละโหมดต้องตรวจใน Flutter"),
    6: ("นึกคำจากบัตรแล้วประเมินว่าจำได้", [HOME,REVIEW,"_card_reveal","_card_remembered","_home_after_review"],
        "_card_remembered","ที่คุณจำความหมายได้","ผลเป็นการประเมินของผู้เรียน การคำนวณกำหนดทบทวนถัดไปอยู่ใน SRS"),
    7: ("เลือกคำอังกฤษจากความหมายแล้วแก้คำที่สับสน", TYPES+["_reverse_word","_reverse_try","_reverse_word","_reverse_win",METHOD],
        "_reverse_win","platform · ชานชาลา","เส้นทางนี้ทดสอบไทยไปอังกฤษ อีกทิศใช้โจทย์เลือกคำแปลบนหน้าเลือกชุด"),
    8: ("อ่านนิยามแล้วแยก platform ออกจาก ticket", TYPES+["_definition_quiz","_definition_no","_definition_quiz","_definition_yes",METHOD],
        "_definition_yes","คุณเลือก platform","เป็นโจทย์นิยามหนึ่งข้อ การให้น้ำหนักหลักฐานยังต้องทดสอบกับระบบฝึก"),
    9: ("เติมคำในประโยคหลังสับสนระหว่างสถานีกับชานชาลา", LESSON+["quiz_screen","_quiz_station","score_screen","fill_in_the_blanks_screen","_fill_wrong","fill_in_the_blanks_screen","_fill_right",HOME],
        "_fill_right","The train is at platform two.","กรณีนี้เลือกคำเติมช่องว่าง การพิมพ์คำเองต้องใช้เกณฑ์ตรวจต่างกัน"),
    10: ("แก้คู่คำที่จับผิดแล้วจับให้ครบทั้งสองคู่", TYPES+["_matching","_matching_pick0","_matching_error0","_matching_pick0","_matching_left1","_matching_done",METHOD],
        "_matching_done","2 / 2","จำนวนคู่ที่ทำสำเร็จแสดงการจำได้จากตัวเลือก"),
    11: ("ปิดบทอ่าน สะกดคำแล้วนำไปใช้ในประโยคใหม่", [LIB,"source_practice_screen","_source_choices","_source_read","_source_fade","_source_recall",
        *["_type_"+"station"[:i] for i in range(1,8)],"_source_cue","_source_write","_source_read_result","_source_choices"],
        "_source_read_result","I live near the station.","แตะตัวอักษรบนกระดานจำลองได้ การพิมพ์อิสระและคงร่างหลังปิดแอปต้องลองกับแป้นพิมพ์จริง"),
    12: ("เขียน ticket ย้อนหนึ่งจังหวะ แล้วตรวจคำด้วยตัวเอง", TYPES+["_scratchpad","_scratch_stroke","_scratch_word","_scratch_stroke","_scratch_word","_scratch_confirm","_scratch_done",METHOD],
        "_scratch_done","คุณประเมินว่าตรงกับเฉลย","รอยปากกาเป็นตัวอย่างที่กดดูได้ แอปต้องรองรับลากเขียนจริงและล้างรอยหลังออก"),
    13: ("ฝึกเขียนตามเสียงจากชุดคำในข้อความแล้วกลับข้อความเดิม", [LIB,"source_practice_screen","_source_choices","_dict_start_source","_dict_play_source","_dict_slow_source","_dict_write_source","_dict_feedback_source","_source_choices"],
        "_dict_feedback_source","สะกดถูกแล้ว","ตัวอย่างการจบรอบเขียนตามเสียงหนึ่งโหมด การใช้ตัวบันทึกร่วมของทั้งหกโหมดต้องตรวจใน Flutter"),
    14: ("เลือกทบทวนคำที่ถึงกำหนดก่อนลองใช้ในประโยค", [HOME,REVIEW,"_card_reveal","_card_again","fill_in_the_blanks_screen","_fill_right",HOME],
        "_fill_right","รถไฟจอดอยู่ที่ชานชาลาสอง","ตัวอย่างมีคำถึงกำหนดหนึ่งคำ ผู้เรียนเลือกชุดหรือวิธีฝึกอื่นจากหน้าฝึกภาษาได้"),
    15: ("เลือกความหมายด้วยตัวเองแล้วก้าวไปนึกคำโดยไม่มีตัวเลือก", [LIB,"_review_desk","_recall_ladder","_ladder_choose","_ladder_hint","_ladder_choose","_ladder_advance","_ladder_write","_ladder_done","_review_desk"],
        "_ladder_done","คุณเลือกความหมายได้ก่อนนึกคำจากประโยค","แสดงสองขั้นที่เปลี่ยนตามคำตอบ การปรับครบเจ็ดโหมดต้องตรวจด้วยประวัติการเรียนจริง"),
}
