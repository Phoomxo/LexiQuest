// Exercise links on the exported native frames without starting a server.
import {createRequire} from 'node:module';
import {join,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const require=createRequire(join(process.env.APPDATA,'npm','render.cjs'));
const browser=await require('puppeteer-core').launch({executablePath:join(process.env.ProgramFiles,'Google/Chrome/Application/chrome.exe'),headless:true});
try {
  const page=await browser.newPage();
  await page.setViewport({width:390,height:844});
  const prototype=pathToFileURL(join(dirname(fileURLToPath(import.meta.url)),'ลองใช้งาน.html')).href;
  await page.goto(prototype);
  const now=()=>page.$eval('section:not([hidden])',el=>el.id);
  const go=async (landing,link=landing)=>{
    const source=await now();
    const a=await page.$('section:not([hidden]) a[href="#'+link+'"]');
    assert.ok(a,'missing link '+link+' from '+source);
    await a.click();
    await page.waitForFunction(k=>document.querySelector('section:not([hidden])').id!==k,{},source);
    assert.equal(await now(),landing,'click '+link+' from '+source);
  };
  const library='categories_page', add='_add_to_library', scan='object_scanner_screen';
  const menu=async()=>{
    const controls=await page.$$eval('section:not([hidden]) a',links=>
      links.map(a=>[a.getAttribute('aria-label'),a.getAttribute('href').slice(1)]));
    const text=await page.$eval('section:not([hidden]) .sr',el=>el.textContent.split(' · '));
    return {controls,text};
  };
  const assertControl=(controls,label,target)=>{
    assert.deepEqual(controls.filter(link=>link[0]===label),[[label,target]],label);
  };
  const checkHome=async(jobLabel,jobTarget,remembered=false)=>{
    const {controls,text}=await menu();
    assert.ok(text.includes('ฝึกภาษา'));
    for(const old of ['วันนี้','คำ','อ่าน','ฝึก','เลือกสิ่งที่จะฝึก'])assert.ok(!text.includes(old),old);
    for(const [label,target] of [
      ['ฝึกภาษา','choose_mode_screen'],['คลังคำศัพท์',library],['ความก้าวหน้า','mastery_dashboard_screen'],
      ['บัญชี','profile_settings_screen'],remembered?['ใช้คำในประโยค','fill_in_the_blanks_screen']:['ทบทวนคำนี้','srs_flashcards_screen'],
      ['ฝึกจากชุดคำ','select_category_for_quiz'],['อ่านเรื่องนัดกันที่สถานี','cefr_article_reader_screen'],
      ['ดูแบบฝึกทั้งหมด','main_navigation_screen'],[jobLabel,jobTarget],
    ])assertControl(controls,label,target);
    assert.ok(!text.includes(jobLabel==='งานที่ได้รับ'?'งานที่ทำเสร็จ':'งานที่ได้รับ'));
    if(remembered){
      assert.ok(text.includes('ทบทวนครบแล้ว'));
      assert.ok(!text.includes('ถึงเวลาทบทวน 1 คำ'));
      assert.ok(!controls.some(([,target])=>target==='srs_flashcards_screen'));
    }
  };
  await checkHome('งานที่ได้รับ','_today_jobs');
  await go('select_category_for_quiz');await go('quiz_screen');await go('_quiz_station');await go('score_screen');
  await go('fill_in_the_blanks_screen');await go('_fill_right');await go('choose_mode_screen');
  await go('select_category_for_quiz');await go('quiz_screen');await go('_quiz_right');await go('_score_right');await go('choose_mode_screen');
  await go(library);await go(add);await go('wordbook_import_screen');await go('add_multiple_words_screen');
  await go('_import_edit');await go('_import_ready');await go('_import_done');
  await page.click('section:not([hidden]) a[href="#@back"]');await page.waitForFunction(()=>document.querySelector('section:not([hidden])').id==='_import_ready');
  const home=async()=>{
    await page.goto('about:blank');
    await page.goto(prototype);
    assert.equal(await now(),'choose_mode_screen');
  };
  await home();await go('_today_jobs');await go('_assigned_word');await go('_assigned_reveal');
  await go('_today_jobs_done');await go('_today_after_assignment');await checkHome('งานที่ทำเสร็จ','_today_jobs_done');
  await go('_today_jobs_done');await go('_today_after_assignment');await go(library);
  await go('_today_after_assignment','choose_mode_screen');await checkHome('งานที่ทำเสร็จ','_today_jobs_done');
  await go('srs_flashcards_screen');await go('_card_reveal');await go('_card_remembered');
  await go('_home_after_both','choose_mode_screen');await go(library);await go('_home_after_both','choose_mode_screen');
  await checkHome('งานที่ทำเสร็จ','_today_jobs_done',true);
  await home();await go('srs_flashcards_screen');await go('_card_reveal');await go('_card_remembered');
  await go('_home_after_review','choose_mode_screen');await go(library);await go('_home_after_review','choose_mode_screen');
  await checkHome('งานที่ได้รับ','_today_jobs',true);
  await go('_today_jobs');await go('_assigned_word');await go('_assigned_reveal');await go('_today_jobs_done');
  await go('_home_after_both','_today_after_assignment');await checkHome('งานที่ทำเสร็จ','_today_jobs_done',true);
  await go('fill_in_the_blanks_screen');await go('_fill_right');await go('_home_after_both','choose_mode_screen');
  await go(library);await page.goBack();assert.equal(await now(),'_home_after_both');
  await page.goForward();assert.equal(await now(),library);
  await home();await go(library);
  const shelf=await menu();
  assert.ok(shelf.text.includes('คลังคำศัพท์')&&shelf.text.includes('ชุดคำของฉัน'));
  for(const [label,target] of [
    ['เพิ่มคำ',add],['ค้นหาคำในคลัง','_search_library'],['เปิดชุดการเดินทาง','vocab_list_screen'],
    ['เปิดชุดของใช้ในครัว','_kitchen_empty'],['เลือกชุดคำศัพท์','_packs'],['ทบทวนคำศัพท์','_review_desk'],
  ])assertControl(shelf.controls,label,target);
  const hiddenMethods=['add_vocab_screen',scan,'wordbook_import_screen','source_practice_screen'];
  assert.equal(shelf.controls.filter(([,target])=>target===add).length,1);
  assert.ok(!shelf.controls.some(([,target])=>hiddenMethods.includes(target)));
  await go(add);
  const choices=await menu();
  assert.ok(choices.text.includes('เพิ่มคำศัพท์'));
  for(const [name,target] of [['พิมพ์คำศัพท์','add_vocab_screen'],['ถ่ายภาพสิ่งของ',scan],
    ['นำเข้าจากไฟล์','wordbook_import_screen'],['ยกเลิก',library]])assertControl(choices.controls,name,target);
  assert.ok(!choices.controls.some(([,target])=>target==='source_practice_screen'));
  await go(library);await go(add);await go('add_vocab_screen');await go(add,'@back');await go(library);
  await go('_search_library');await go('_station_in_library');await go('_word');await go('_station_in_library','@back');await go(library);
  await go('vocab_list_screen');await go('_word_search');await go('_word');await go('_word_search','@back');await go('vocab_list_screen');await go(library);
  await go('choose_mode_screen');await go('main_navigation_screen');await go('source_practice_screen');
  await go('_ticket');await go('source_practice_screen','@back');await go('main_navigation_screen','@back');await go('choose_mode_screen','@back');
  await home();await go('categories_page');await go('vocab_list_screen');await go('_word');await go('ai_tutor_screen');await go('_tutor_reply');await go('_platform');
  await home();await go('mastery_dashboard_screen');await go('_history');
  await home();await go('profile_settings_screen');await go('setting_screen');await go('appearance_settings_screen');await go('_appearance_dark');
  const emptyKitchen='_kitchen_empty', kitchen='_scan_collection', noCup='_cup_not_found', cup='_scan_cup_detail', search='_search_library';
  const checkNoCup=async ()=>{
    await go(emptyKitchen);await go(library);
    await go(search);await go(noCup);await go(search,'@back');await go(library,'@back');
  };
  const cameraSearch=async ()=>{
    await go(search);await go(cup,noCup);
    const text=await page.$eval('section:not([hidden]) .sr',el=>el.textContent);
    assert.ok(text.includes('cup')&&text.includes('ถ้วย'));
  };
  await home();await go(library);await checkNoCup();
  await go(add);await go(scan);await go('_scan_permission');await go('_scan_denied');
  await go('_scan_permission','@back');await go(scan,'@back');await go(add,'@back');await go(library);await checkNoCup();
  await go(add);await go(scan);await go('_scan_examples');await go('_scan_save_failed');
  await go('_scan_examples','@back');await go(scan,'@back');await go(add,'@back');await go(library);await checkNoCup();
  await go(add);await go(scan);await go('_scan_permission');await go('_scan_ready');await go('_scan_result');await go('_scan_saved');await go(kitchen);await go('_scan_recall');await go('_scan_revealed');await go(kitchen);await go(library);
  await go('choose_mode_screen');await go(library);await go(kitchen,emptyKitchen);await go(cup);await go(kitchen);await go(library);await cameraSearch();
  await page.reload();await go(library);await checkNoCup();
  await go(add);await go(scan);await go('_scan_examples');await go('_scan_save_failed');await go('_scan_saved');await go(kitchen);await go(library);await cameraSearch();
  await home();await go('select_category_for_quiz');await go('_travel_q1');await go('_travel_f11');await go('_travel_q21');await go('_travel_f210');await go('_travel_done10');await go('_travel_retry1');
  await home();await go('select_category_for_quiz');await go('_exam_planned');await go('_scratchpad');await go('_scratch_type');await go('_scratch_confirm');await go('_scratch_done');
  await home();await go('categories_page');await go('_packs');await go('_pack');await go('_provenance');await go('_report');await go('_report_queue');
  await home();await go('profile_settings_screen');await go('setting_screen');await go('_local_status');await go('_local_guest');await go('categories_page');
  await home();await go('mastery_dashboard_screen');await go('_plan_studio');await go('_plan_timer');await go('_plan_timer_5');await go('_plan_paused_5');await go('_plan_resume_5');await go('_plan_time_log');
  await home();await go('categories_page');await go('vocab_list_screen');await go('smart_audio_playlist_screen');await go('_playlist_play');await go('_playlist_next');await go('_playlist_last');
  await home();await go('cefr_article_reader_screen');await go('associative_reading_session_screen');await go('_reading_write');
  assert.equal(await page.$$eval('section img',imgs=>imgs.filter(i=>!i.complete||i.naturalWidth!==390||i.naturalHeight!==844).length),0);
  console.log('Passed: Thai practice menus before and after assignment, library add methods and cancel, search within and across sets, source practice and return, quiz and repair, import and back, tutor, progress, appearance, camera denial, failed save, successful retry, listening, reading and recall. All native images loaded.');
}finally{await browser.close()}
