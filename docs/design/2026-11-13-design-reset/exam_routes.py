"""Clickable exercise examples. Text entry and evidence storage are simulated."""

from itertools import product


def example(family, title, subtitle, blocks, buttons=()):
    return family, title, subtitle, blocks, list(buttons), None


def add_round(screens, prefix, words, subtitle, exit_target):
    """Two prompts with every answer sequence, a real denominator and targeted retry links."""
    for index in range(2):
        word, meaning = words[index]
        for answers in product("01", repeat=index):
            trace = "".join(answers)
            target = f"_{prefix}_q{index+1}{trace}"
            choices = []
            for row in ((1, 0) if index == 0 else (0, 1)):
                correct = int(index == row)
                chosen = words[row][1]
                after = trace + str(correct)
                feedback = f"_{prefix}_f{index+1}{after}"
                choices.append(("choice", chosen, feedback))
                next_frame = f"_{prefix}_q2{after}" if index == 0 else f"_{prefix}_done{after}"
                details = [("quote", "คำตอบที่เลือก", chosen, f"{word} หมายถึง {meaning}")]
                if not correct:
                    details.append(("lines", "แยกสองคำนี้", f"{words[row][0]}  ·  {chosen}", f"{word}  ·  {meaning}"))
                screens[feedback] = example("practice", "ตอบถูกแล้ว" if correct else "ลองเทียบความหมาย",
                    subtitle, details, [("ไปข้อถัดไป" if index == 0 else "ดูผลการฝึก", next_frame)])
            screens[target] = example("practice", "เลือกความหมาย", subtitle, [
                ("meter",f"ข้อ {index+1} จาก 2",(index+1)/2),
                ("hero","คำนี้หมายถึงอะไร",word,"เลือกคำแปลจากชุดที่กำลังฝึก"), *choices])
    for bits in product("01", repeat=2):
        mistakes = [i for i,b in enumerate(bits) if b=="0"]
        rows = [("row",word,f"{meaning}  ·  "+("ลองอีกครั้ง" if i in mistakes else "ตอบถูก"),
                 f"_{prefix}_retry{i}" if i in mistakes else None) for i,(word,meaning) in enumerate(words)]
        screens[f"_{prefix}_done{''.join(bits)}"] = example("result","ผลการฝึกครั้งนี้",subtitle,[
            ("stat",f"{2-len(mistakes)} / 2","ข้อที่ตอบถูก","นับคำตอบแรกของแต่ละคำ"), *rows],
            [("กลับไปเลือกแบบฝึก",exit_target)])
    for i,(word,meaning) in enumerate(words):
        screens[f"_{prefix}_retry{i}"] = example("practice","ลองคำนี้อีกครั้ง","ฝึกคำที่เพิ่งตอบผิด",[
            ("hero","ลองนึกคำแปล",word,"นึกให้ได้ก่อนเปิดดูคำตอบ")],
            [("ดูคำแปล",f"_{prefix}_reveal{i}")])
        screens[f"_{prefix}_reveal{i}"] = example("practice","เทียบกับคำที่นึกไว้","ทบทวนหลังจบรอบ",[
            ("hero",word,meaning,"ผลของรอบที่เพิ่งจบยังคงเดิม")],
            [("กลับไปเลือกแบบฝึก",exit_target)])


def install(screens):
    category="select_category_for_quiz"
    family,title,sub,blocks,buttons,tab = screens[category]
    screens[category]=(family,title,sub,[blocks[0],
        ("row","ลองฝึกทั้งชุด","2 คำ · ดูผลแยกตามคำที่ตอบ","_travel_q1"),*blocks[1:]],buttons,tab)
    add_round(screens,"travel",[("station","สถานี"),("platform","ชานชาลา")],"ชุดการเดินทาง",category)
    source="_source_choices"
    family,title,sub,blocks,buttons,tab=screens[source]
    screens[source]=(family,title,sub,[
        ("row","เลือกความหมาย","ใช้สองคำที่พบในข้อความนี้","_source_q1"),
        ("row","อ่านแล้วลองนึกคำ","ฝึกใช้ station ในบริบทใหม่","_source_read"),*blocks],buttons,tab)
    add_round(screens,"source",[("station","สถานี"),("ticket","ตั๋ว")],"คำจากข้อความ",source)
    screens["_source_read"]=example("reader","อ่านเรื่องที่สถานี","อ่านพร้อมคำช่วย",[
        ("lines","บทอ่าน","Meet me at the station.","Bring your ticket."),
        ("quote","คำที่กำลังฝึก","station","สถานี")],[("ลองอ่านโดยไม่ดูคำแปล","_source_fade")])
    screens["_source_fade"]=example("reader","อ่านอีกครั้ง","อ่านโดยไม่ดูคำแปล",[
        ("lines","บทอ่าน","Meet me at the station.","Bring your ticket.")],
        [("ปิดบทอ่านแล้วลองนึกคำ","_source_recall")])
    for key,typed,next_step,other in [
        ("_source_recall","station","_source_cue","_source_recall_typo"),
        ("_source_recall_typo","staton","_source_cue_typo","_source_recall")]:
        screens[key]=example("form","นึกคำจากเรื่อง","ปิดบทอ่านแล้ว",[
            ("note","สถานที่ที่ทั้งสองคนนัดเจอกัน","เขียนคำอังกฤษที่จำได้"),
            ("field","คำตอบที่พิมพ์ในตัวอย่าง",typed)],
            [("ตรวจคำที่นึกได้",next_step),("สลับคำตอบตัวอย่าง",other)])
    for suffix,typed,correct in [("","station",True),("_typo","staton",False)]:
        screens["_source_cue"+suffix]=example("form","จดวิธีจำของฉัน","station  ·  สถานี",[
            ("note","นึกคำได้ถูกต้อง" if correct else "คำที่สะกดถูกคือ station",
             "คำที่พิมพ์  ·  "+typed),
            ("field","คำช่วยจำตัวอย่าง","นึกถึงป้ายสถานีหน้าบ้าน")],
            [("ลองใช้ในประโยค","_source_write"+suffix)])
        screens["_source_write"+suffix]=example("form","ลองใช้คำในประโยค","station  ·  สถานี",[
            ("field","ประโยคตัวอย่างของฉัน","I live near the station."),
            ("note","เปลี่ยนสถานการณ์จากเรื่องที่อ่าน","จากการนัดเจอเพื่อน เป็นการบอกที่อยู่")],
            [("ดูผลการฝึก","_source_read_result"+suffix)])
        screens["_source_read_result"+suffix]=example("result","ผลการฝึกครั้งนี้","อ่านแล้วนึกคำ",[
            ("stat","1 / 1" if correct else "0 / 1","คำที่นึกได้","คำที่พิมพ์  ·  "+typed),
            ("quote","ประโยคที่ลองใช้","I live near the station.","ฉันอยู่ใกล้สถานี")],
            [("ฝึกคำจากข้อความต่อ",source)])

    ghost="ghost_shadow_duel_screen"
    for key,spelling,verdict in [(ghost,"platform","_duel_win"),("_duel_spelling_typo","platfrom","_duel_same")]:
        other="_duel_spelling_typo" if key==ghost else ghost
        screens[key]=example("practice","ท้าสถิติของฉัน","ฝึกสะกดคำที่เคยพลาด",[
            ("hero","เขียนเป็นภาษาอังกฤษ","ชานชาลา","บริเวณที่ผู้โดยสารยืนรอรถไฟ"),
            ("field","คำตอบที่พิมพ์ในตัวอย่าง",spelling)],
            [("ตรวจคำสะกด",verdict),("สลับคำตอบตัวอย่าง",other)])
    screens["_duel_win"]=example("result","สะกดถูกแล้ว","ท้าสถิติของฉัน",[
        ("stat","1 / 1","คำที่สะกดถูก","ครั้งก่อน 0 จาก 1 คำ"),
        ("quote","คำที่พิมพ์","platform","ชานชาลา")],[("กลับหน้าฝึกภาษา","choose_mode_screen")])
    screens["_duel_same"]=example("result","ลองดูตัวอักษรสองตัวนี้","ท้าสถิติของฉัน",[
        ("quote","คำที่พิมพ์","platfrom","สังเกตลำดับตัว o กับ r"),
        ("hero","คำที่สะกดถูก","platform","ชานชาลา")],[("ลองสะกดอีกครั้ง",ghost)])

    sentence="sentence_scramble_screen"
    for frame,prefix,tiles in [(sentence,"I have",["ticket","a"]),
                               ("_arrange_a","I have a",["ticket"]),
                               ("_arrange_ticket","I have ticket",["a"])]:
        blocks=[("quote","เรียงให้แปลว่า ฉันมีตั๋วหนึ่งใบ",prefix+" …","แตะคำถัดไปเพื่อเติมในประโยค")]
        if frame==sentence:
            blocks.extend([("choice",word,"_arrange_"+word) for word in tiles])
        else:
            target="_sentence_done" if frame=="_arrange_a" else "_sentence_retry"
            blocks.append(("choice",tiles[0],target))
        screens[frame]=example("practice","เรียงคำเป็นประโยค","การเดินทาง",blocks,
            [] if frame==sentence else [("เอาคำล่าสุดออก",sentence)])

    for key,spelling,verdict in [("boss_battle_screen","sustainable","result_screen"),("_boss_typo","sustainble","_boss_retry")]:
        other="_boss_typo" if key=="boss_battle_screen" else "boss_battle_screen"
        screens[key]=example("practice","ด่านสะกดคำ","คำสุดท้ายของรอบ",[
            ("meter","สะกดผ่านแล้ว 2 จาก 3 คำ",2/3),
            ("hero","เขียนเป็นภาษาอังกฤษ","ยั่งยืน","ตรวจตัวสะกดก่อนส่ง"),
            ("field","คำตอบที่พิมพ์ในตัวอย่าง",spelling)],
            [("ตรวจคำสะกด",verdict),("สลับคำตอบตัวอย่าง",other)])

    planned="แบบที่เสนอ · ยังไม่เปิดในแอป"
    family,title,sub,blocks,buttons,tab=screens[category]
    screens[category]=(family,title,sub,blocks,[*buttons,("ดูแบบฝึกที่อยู่ระหว่างออกแบบ","_exam_planned")],tab)
    screens["_exam_planned"]=example("list","แบบฝึกที่กำลังออกแบบ",planned,[
        ("row","อ่านนิยามแล้วหาคำ","อ่านคำอธิบายภาษาอังกฤษ","_definition_quiz"),
        ("row","จับคู่คำกับความหมาย","เลือกคำ แล้วแตะคำแปลที่ตรงกัน","_matching"),
        ("row","กระดานฝึกเขียน","ลองดูรอยเขียน หรือใช้ข้อความแทน","_scratchpad")])
    screens["_definition_quiz"]=example("practice","อ่านนิยามแล้วหาคำ",planned,[
        ("lines","คำไหนตรงกับนิยามนี้","The place at a train station","where you wait to get on a train."),
        ("choice","platform","_definition_yes"),("choice","ticket","_definition_no")])
    for key,verdict,response in [("_definition_yes","เลือกคำตรงกับนิยาม","คุณเลือก platform"),("_definition_no","ลองแยกสองคำนี้","คุณเลือก ticket")]:
        screens[key]=example("result",verdict,planned,[
            ("quote",response,"platform  ·  ชานชาลา","บริเวณที่ผู้โดยสารยืนรอขึ้นรถไฟ"),
            ("lines","เทียบกับอีกคำ","ticket  ·  ตั๋ว","หลักฐานที่ใช้โดยสาร")],
            [("เลือกแบบฝึกอื่น","_exam_planned"),("ลองข้อเดิม","_definition_quiz")])
    pairs=(("station","สถานี"),("ticket","ตั๋ว"))
    screens["_matching"]=example("practice","จับคู่คำกับความหมาย",planned,[
        ("meter","จับคู่แล้ว 0 จาก 2",0),("note","แตะคำอังกฤษหนึ่งคำ","แล้วเลือกคำแปลที่ตรงกัน"),
        *(("choice",w,f"_matching_pick{i}") for i,(w,_) in enumerate(pairs))])
    for i,(w,m) in enumerate(pairs):
        j=1-i
        screens[f"_matching_pick{i}"]=example("practice","เลือกคำแปล",planned,[
            ("hero","คำที่เลือก",w,"แตะคำแปลให้ตรงกับคำนี้"),
            ("choice",pairs[j][1],f"_matching_error{i}"),("choice",m,f"_matching_left{j}")],
            [("เลือกคำอังกฤษใหม่","_matching")])
        screens[f"_matching_error{i}"]=example("practice","คู่นี้ยังไม่ตรงกัน",planned,[
            ("quote","คู่ที่ลอง",f"{w}  ·  {pairs[j][1]}",f"{pairs[j][1]} ตรงกับคำว่า {pairs[j][0]}")],
            [("ลองเลือกคำแปลอีกครั้ง",f"_matching_pick{i}")])
        screens[f"_matching_left{j}"]=example("practice","จับคู่คำที่เหลือ",planned,[
            ("meter","จับคู่แล้ว 1 จาก 2",0.5),("row",w,m,None),
            ("hero","คำที่เหลือ",pairs[j][0],"เลือกคำแปลของคำสุดท้าย"),
            ("choice",pairs[j][1],"_matching_done")])
    screens["_matching_done"]=example("result","จับคู่ครบแล้ว",planned,[
        ("stat","2 / 2","คู่ที่จับสำเร็จ","ทบทวนคู่คำได้อีกครั้ง"),
        ("row","station","สถานี",None),("row","ticket","ตั๋ว",None)],
        [("เลือกแบบฝึกอื่น","_exam_planned")])

    screens["_scratchpad"]=example("practice","กระดานฝึกเขียน",planned,[
        ("lines","ลองเขียนคำว่า ตั๋ว","ใช้พื้นที่ว่างฝึกเขียนคำอังกฤษ","ต้นแบบแสดงรอยตัวอย่างเมื่อแตะปุ่ม"),
        ("field","พื้นที่ฝึกเขียน"," ")],[("ดูตัวอย่างการเขียน","_scratch_stroke"),("ใช้ข้อความแทน","_scratch_type")])
    for key,written,previous,next_step,label in [
        ("_scratch_stroke","tick","_scratchpad","_scratch_word","เขียนต่อให้จบคำ"),
        ("_scratch_word","ticket","_scratch_stroke","_scratch_confirm","ตรวจคำก่อนส่ง")]:
        screens[key]=example("practice","กระดานฝึกเขียน",planned,[
            ("hero","รอยเขียนตัวอย่าง",written,"โจทย์  ·  ตั๋ว"),
            ("row","ล้างกระดาน","เริ่มเขียนใหม่ทั้งหมด","_scratchpad")],
            [(label,next_step),("ย้อนการเขียนครั้งล่าสุด",previous)])
    screens["_scratch_type"]=example("form","ใช้ข้อความแทนลายมือ",planned,[
        ("field","คำตอบตัวอย่าง","ticket")],[("ตรวจคำก่อนส่ง","_scratch_confirm")])
    screens["_scratch_confirm"]=example("form","ตรวจคำก่อนส่ง",planned,[
        ("field","คำที่จะใช้ตรวจ","ticket"),("note","ตรวจการสะกดด้วยตัวเอง","ถ้าคำยังไม่ตรง ให้กลับไปแก้ไข")],
        [("ส่งคำตอบตัวอย่าง","_scratch_done"),("กลับไปแก้คำ","_scratch_type")])
    screens["_scratch_done"]=example("result","สะกดถูกแล้ว",planned,[
        ("hero","คำที่ตรวจ","ticket","ตั๋ว")],[("เลือกแบบฝึกอื่น","_exam_planned")])
