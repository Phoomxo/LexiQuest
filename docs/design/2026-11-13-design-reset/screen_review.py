"""Observable work on the 34 source screens reachable from Flutter's static entry graph."""
from exam_routes import example

TODAY="choose_mode_screen"
SHELF="categories_page"
PROGRESS="mastery_dashboard_screen"
PROFILE="profile_settings_screen"

def install(s):
    def buttons(key,*actions):
        family,title,sub,blocks,_,tab=s[key];s[key]=(family,title,sub,blocks,list(actions),tab)
    def add_button(key,label,dest):
        buttons(key,*s[key][4],(label,dest))
    buttons("_password_link",("ขอลิงก์ใหม่ในตัวอย่าง","_mail_reset_sent"),("กลับไปเข้าสู่ระบบ","login_screen"))
    s["_mail_reset_sent"]=example("reader","ตรวจอีเมลของคุณ","ตัวอย่างการกู้บัญชี",[
        ("quote","ที่อยู่อีเมล","reader@example.com","เปิดจดหมายฉบับล่าสุดเพื่อตั้งรหัสผ่าน"),
        ("note","ในต้นแบบไม่มีการส่งอีเมล","ถ้าลิงก์หมดอายุ คุณขอฉบับใหม่ได้")],
        [("ลิงก์หมดอายุ","email_action_screen"),("กลับไปเข้าสู่ระบบ","login_screen")])
    add_button("otp_screen","ลองเปิดลิงก์ยืนยัน","_mail_verified")
    s["_mail_verified"]=example("result","ยืนยันอีเมลแล้ว","ตัวอย่างการสมัคร",[
        ("quote","บัญชีตัวอย่าง","reader@example.com","ใช้อีเมลนี้เข้าสู่ระบบเพื่อเริ่มเรียน")],
        [("กลับไปเข้าสู่ระบบ","login_screen")])
    for key,label,rows in [("_export_words","เฉพาะคลังคำ","คำศัพท์และคำแปล"),("_export_history","คลังคำและประวัติ","คำศัพท์ คำแปล และประวัติการฝึก")]:
        review=s[key]
        confirm=key+"_ready"
        buttons(key,("ดูตัวอย่างสำเนา",confirm),*review[4])
        s[confirm]=example("list","สำเนาที่เลือก","ตัวอย่างไฟล์ CSV",[
            ("lines","รายการในสำเนา",label,rows),
            ("quote","ตัวอย่างรายการ","station,สถานี","ไม่มีไฟล์ถูกเขียนลงเครื่อง")],
            [("กลับไปข้อมูลของฉัน","_account_data"),("เลือกข้อมูลใหม่","export_center_screen")])
    for key in ("_library_imported","_library_added"):
        add_button(key,"กลับคลังคำ",SHELF)
    add_button("_shadow_done","กลับไปเลือกแบบฝึกฟัง","_listening")
    add_button("_duel_win","กลับไปเลือกเกม","_word_games")
    add_button("_word_games","กลับไปเลือกวิธีฝึก","main_navigation_screen")
    add_button("vocab_list_screen","กลับคลังคำ",SHELF)
    add_button("appearance_settings_screen","กลับไปตั้งค่า","setting_screen")
    family,title,sub,blocks,buttons0,tab=s["select_category_for_quiz"]
    s["select_category_for_quiz"]=(family,title,sub,blocks,
        [(label,k) for label,k in buttons0 if k!="_exam_planned"]+[("ลองวิธีตอบแบบอื่น","_exam_planned")],tab)

# Tail starts at its source screen. The inspector finds its short arrival path from the named tab.
# A hand-picked tail keeps the task and return independent of shortcuts added by other features.
ROWS={}
def row(key,tab,job,trail,witness,text,decision):
    ROWS[key]=(tab,job,trail.split(),witness,text,decision)
row("account_deletion_screen",PROFILE,"อ่านผลกระทบก่อนตัดสินใจเก็บบัญชี","_delete_review _account_data","_delete_review","ลบบัญชี","แยกการเก็บบัญชีจากการส่งคำขอลบและคงทางสำรองข้อมูล")
row("achievements_screen",PROFILE,"ลองสวมของที่มีแล้วกลับมาดูของสะสม","avatar_equipment_screen _hat_preview _hat_equipped achievements_screen","_hat_equipped","ใช้งานอยู่","แยกของที่มีอยู่กับของในร้านด้วยคำบอกสถานะ")
row("add_multiple_words_screen",SHELF,"เติมคำแปลที่ขาด นำเข้า แล้วกลับคลัง","_import_edit _import_ready _import_done _library_imported categories_page","_library_imported","ทางเดินระหว่างที่นั่ง","เพิ่มทางกลับคลังหลังตรวจรายการที่เพิ่มจริง")
row("add_vocab_screen",SHELF,"เพิ่ม suitcase และตรวจในชุดเดิม","_suitcase _library_added categories_page","_library_added","เพิ่งเพิ่ม","แยกคำอังกฤษ คำแปล และชุดปลายทางก่อนปุ่มเก็บ")
row("ai_tutor_screen",SHELF,"ถามความต่างของสองคำแล้วเปิดชุดเดิม","_tutor_reply _platform vocab_list_screen","_tutor_reply","platform","คงคำและประโยคต้นทางไว้เหนือคำถาม")
row("appearance_settings_screen",PROFILE,"เปรียบเทียบคำเดียวกันในโหมดมืดและสว่าง","_appearance_dark appearance_settings_screen","_appearance_dark","borrow","คงคำตัวอย่างเดิมเพื่อให้เทียบความชัดได้")
row("associative_reading_session_screen",TODAY,"นึกคำแล้วใช้ในประโยคหลังอ่านจบ","_reading_write _reading_done choose_mode_screen","_reading_done","I am on platform three.","แยกช่วงอ่านเรื่อง นึกคำ และนำไปใช้")
row("categories_page",SHELF,"ค้น station แล้วอ่านคำคู่ก่อนกลับคลัง","vocab_list_screen _word_search _word _word_search vocab_list_screen categories_page","_word","Meet me at the station.","ค้นข้ามชุดได้จากช่องค้นหาหลัก ส่วนการเพิ่มคำทั้งสามวิธีอยู่ที่ปุ่มเดียว")
row("choose_mode_screen",TODAY,"เปิดงานที่ถึงกำหนดแล้วกลับหน้าฝึกภาษา","srs_flashcards_screen _card_reveal _card_remembered _home_after_review","_card_remembered","ทบทวนครบแล้ว","คำถึงกำหนดเป็นปุ่มหลักเดียวเหนือบทเรียนที่ทำต่อได้")
row("device_permission_center_screen",PROFILE,"อ่านวิธีใช้ไมค์แล้วกลับศูนย์สิทธิ์","_mic_permission device_permission_center_screen","_mic_permission","ไมโครโฟน","อธิบายว่าใช้สิทธิ์ทำอะไรและฝึกอะไรได้หากไม่เปิด")
row("email_action_screen",PROFILE,"ขอลิงก์ใหม่หลังลิงก์ตั้งรหัสหมดอายุ","_password_link _mail_reset_sent login_screen","_mail_reset_sent","เปิดจดหมายฉบับล่าสุด","เพิ่มผลหลังขอลิงก์ใหม่และบอกว่าไม่มีการส่งอีเมลจริง")
row("export_center_screen",PROFILE,"ตรวจตัวอย่างสำเนาคลังคำโดยไม่รวมประวัติ","_export_words _export_words_ready _account_data","_export_words_ready","station,สถานี","แยกเลือกขอบเขต ตรวจตัวอย่าง และกลับไปจัดการข้อมูล")
row("fill_in_the_blanks_screen",PROGRESS,"ซ่อมคำที่สับสนด้วยประโยคใหม่","_fill_right choose_mode_screen","_fill_right","The train is at platform two.","คงบริบทประโยคให้ตรวจได้หลังเติมคำ")
row("gemini_settings_screen",PROFILE,"ตรวจว่าข้อมูลใดส่งให้ผู้ช่วยแล้วกลับ","_assistant_data gemini_settings_screen","_assistant_data","ผู้ช่วย","ระบุข้อมูลที่เกี่ยวข้องก่อนเข้าสนทนา")
row("ghost_shadow_duel_screen",TODAY,"เทียบการสะกดกับรอบก่อนแล้วเลือกเกม","_duel_win _word_games","_duel_win","ครั้งก่อน 0 จาก 1 คำ","เพิ่มทางกลับเกมหลังเทียบผลกับตัวเอง")
row("login_screen",PROFILE,"เข้าบัญชีตัวอย่างแล้วไปเรียน","_account_signed_in choose_mode_screen","_account_signed_in","reader@example.com","แยกเข้าสู่ระบบจากการเรียนแบบไม่ใช้บัญชี")
row("main_navigation_screen",TODAY,"เลือกวิธีฝึกจากงานแล้วกลับไปเลือกวิธีอื่น","_word_games word_scramble_screen _spell_done _word_games main_navigation_screen","_spell_done","ticket","แยกฝึกเสียง อ่าน และเล่นเกม แทนรายชื่อโมดูล")
row("mastery_dashboard_screen",PROGRESS,"ดูคำที่พลาดแล้วฝึกต่อให้ถูก","weakness_clinic_screen fill_in_the_blanks_screen _fill_right choose_mode_screen","_fill_right","The train is at platform two.","ก้าวต่อจากคะแนนรวมลงไปจนถึงคำที่ต้องแก้")
row("object_scanner_screen",SHELF,"เก็บคำว่า cup สลับแท็บ แล้วกลับมาหาคำจากชุดและการค้นหา","_scan_permission _scan_ready _scan_result _scan_saved _scan_collection categories_page choose_mode_screen categories_page _scan_collection _scan_cup_detail categories_page _search_library _scan_cup_detail categories_page","_scan_cup_detail","เก็บจากกล้อง · ชุดของใช้ในครัว","คำที่เก็บอยู่ในชุดของฉันและค้นได้หลังออกจากหน้ากล้องในรอบนำเสนอเดียวกัน")
row("otp_screen",PROFILE,"เปิดลิงก์ยืนยันแล้วกลับไปเข้าสู่ระบบ","_mail_verified login_screen","_mail_verified","ยืนยันอีเมลแล้ว","เรียกเมนูตามการยืนยันด้วยอีเมล ไม่ใช้ชื่อไฟล์ OTP")
row("profile_settings_screen",PROFILE,"เปิดข้อมูลของฉันแล้วกลับบัญชี","_account_data profile_settings_screen","_account_data","บันทึกสำเนาข้อมูล","แยกข้อมูลส่วนตัว ตั้งค่า และของสะสมเป็นคนละแถว")
row("quiz_screen",TODAY,"เลือกคำตอบแล้วตรวจผลรอบ","_quiz_right _score_right choose_mode_screen","_quiz_right","คำตอบที่ถูก","เก็บตัวเลือกไว้ตอนเฉลยและบอกสถานะบันทึก")
row("register_screen",PROFILE,"อ่านเงื่อนไข สมัคร และยืนยันอีเมล","_register_terms otp_screen _mail_verified login_screen","_mail_verified","reader@example.com","ให้การสมัครจบด้วยผลยืนยัน แยกจากการสมัครวิจัย")
row("score_screen",TODAY,"ดูคำที่ผิดแล้วซ่อมด้วยโจทย์ใหม่","fill_in_the_blanks_screen _fill_right choose_mode_screen","_fill_right","The train is at platform two.","ปุ่มหลักพาไปใช้คำที่เพิ่งตอบผิดจริง")
row("select_category_for_quiz",TODAY,"เลือกชุดการเดินทางแล้วฝึกจนจบ","quiz_screen _quiz_right _score_right choose_mode_screen","_score_right","1 / 1","ให้ชุดคำ/การตั้งค่ารอบมาก่อนวิธีตอบแบบอื่น")
row("setting_screen",PROFILE,"เปรียบเทียบโหมดมืดแล้วกลับตั้งค่า","appearance_settings_screen _appearance_dark appearance_settings_screen setting_screen","_appearance_dark","โหมดมืด","แยกการใช้งานบนอุปกรณ์จากบริการและข้อมูล")
row("shadowing_challenge_screen",TODAY,"เทียบประโยคที่พูดแล้วกลับไปเลือกแบบฝึกฟัง","_shadow_live _shadow_done _listening","_shadow_done","Meet me at station.","ให้เห็น the ที่ขาดและมีปุ่มกลับหมวดเสียง")
row("shop_page",PROFILE,"ดูพื้นหลังที่มีแล้วกลับร้านโดยไม่เสียเหรียญ","_wallpaper_preview shop_page","_wallpaper_preview","คุณมีพื้นหลังนี้แล้ว","แยกของที่มีแล้วจากชิ้นที่ใช้เหรียญแลก")
row("source_practice_screen",TODAY,"อ่านคำจากข้อความแล้วกลับข้อความเดิม","_ticket source_practice_screen","_ticket","ticket","ให้ประโยคที่นำคำมาอยู่ก่อนเมนูแบบฝึก")
row("speak_to_text_screen",TODAY,"ลองพูด ตรวจคำที่ได้ยิน แล้วเปิดคำเดิม","_speech_live _speech_review _word","_speech_review","ตรงกับคำเป้าหมาย","แสดงคำที่เครื่องได้ยินให้ผู้เรียนยอมรับหรือพูดใหม่")
row("srs_flashcards_screen",TODAY,"นึกก่อนพลิกบัตรแล้วจบรอบ","_card_reveal _card_remembered _home_after_review","_card_remembered","ทบทวนครบแล้ว","แยกการเห็นคำเฉลยออกจากการประเมินว่าจำได้")
row("vocab_list_screen",SHELF,"อ่านคำที่สับสนแล้วกลับชุดการเดินทาง","_platform vocab_list_screen","_platform","ชานชาลา","ตกลงชื่อชุดและจำนวนคำก่อนแสดงรายการกับคำสั่ง")
row("weakness_clinic_screen",PROGRESS,"แก้ platform ที่จำสลับกับ station","fill_in_the_blanks_screen _fill_right choose_mode_screen","_fill_right","The train is at platform two.","ใช้คำตอบจากรอบก่อนอธิบายเหตุผลที่ต้องฝึกซ้ำ")
row("word_scramble_screen",TODAY,"เติมตัวอักษรตัวสุดท้ายแล้วกลับไปเลือกเกม","_spell_done _word_games","_spell_done","ticket","แสดงตัวอักษรที่ประกอบแล้วก่อนให้เลือกชิ้นถัดไป")
