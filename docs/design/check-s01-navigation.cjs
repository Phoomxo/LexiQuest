// Host execution of source functions with minimal DOM boundary doubles.
// This does not launch or automate a browser and does not prove layout/a11y/native UX.
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const {test}=require('node:test');
// Read only rendered button markup; disabled controls must never receive focus.
test('S01-T typed answers survive help and audio rerenders with exact text and field selection',()=>{
  for(const mode of ['typed-recall','dictation','handwriting-scratchpad']){
    const h=setup({audio:true});h.click('data-mode',mode);h.click('data-action','begin-mode');
    assert.match(h.screen.innerHTML,/id="mode-input"/);
    h.input('mode-input','  b<&"ook  ');const field=h.document.getElementById('mode-input');h.document.activeElement=field;
    h.click('data-action','hint');assert.match(h.screen.innerHTML,/id="mode-input"[^>]*value="  b&lt;&amp;&quot;ook  "/);
    assert.equal(h.focused(),'mode-input');assert.deepEqual(field.restoredSelection,[1,3,'backward']);
    h.click('data-action','play-audio');h.spoken.at(-1)?.onend();
    assert.match(h.screen.innerHTML,/id="mode-input"[^>]*value="  b&lt;&amp;&quot;ook  "/);
    assert.match(h.screen.innerHTML,/ร่าง.*เฉพาะ.*หน้านี้.*โหลดใหม่.*หาย/);
  }
});
test('S01-T drafts remain separate across typed modes, navigation and owners',()=>{
  const h=setup();
  for(const [mode,text] of [['typed-recall','  typed  '],['dictation',' heard '],['handwriting-scratchpad',' copied ']]){
    h.click('data-mode',mode);h.click('data-action','begin-mode');h.input('mode-input',text);
  }
  h.click('data-demo-owner','demo-b');h.click('data-mode','dictation');h.click('data-action','begin-mode');
  assert.match(h.screen.innerHTML,/id="mode-input"[^>]*value=""/);h.input('mode-input','B only');
  h.click('data-demo-owner','demo-a');
  for(const [mode,text] of [['typed-recall','  typed  '],['dictation',' heard '],['handwriting-scratchpad',' copied ']]){
    h.click('data-mode',mode);h.click('data-action','begin-mode');assert.ok(h.screen.innerHTML.includes('value="'+text+'"'));
  }
  h.click('data-route','home');h.click('data-mode','dictation');h.click('data-action','begin-mode');assert.ok(h.screen.innerHTML.includes('value=" heard "'));
});
test('S01-T checking keeps exact draft, typing clears feedback, explicit retry clears only this draft',()=>{
  const h=setup();h.click('data-mode','dictation');h.click('data-action','begin-mode');h.input('mode-input','other');
  h.click('data-mode','typed-recall');h.click('data-action','begin-mode');h.input('mode-input',' book ');h.click('data-action','check-input');
  assert.equal(h.run('state.feedback.good'),true);assert.match(h.screen.innerHTML,/value=" book "/);
  h.input('mode-input','boo');assert.equal(h.run('state.feedback'),null);h.click('data-action','hint');h.click('data-action','retry-mode');
  assert.match(h.screen.innerHTML,/id="mode-input"[^>]*value=""/);
  h.click('data-mode','dictation');h.click('data-action','begin-mode');assert.match(h.screen.innerHTML,/value="other"/);
});
test('S01-T stale typed inputs and checks cannot modify another activity or owner',()=>{
  const h=setup();h.click('data-mode','typed-recall');
  const ignored=()=>{const before=h.run('JSON.stringify(state)');h.input('mode-input','late');h.click('data-action','check-input');assert.equal(h.run('JSON.stringify(state)'),before);};
  ignored();h.click('data-action','begin-mode');h.input('mode-input','kept');h.click('data-route','home');ignored();
  h.click('data-mode','word-scramble');h.click('data-action','begin-mode');ignored();h.click('data-demo-owner','demo-b');ignored();
  h.click('data-demo-owner','demo-a');h.click('data-mode','typed-recall');h.click('data-action','begin-mode');assert.match(h.screen.innerHTML,/value="kept"/);
});
test('S01-T handwriting typed alternative has a linked label and precise draft lifetime copy',()=>{
  const h=setup();h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');
  assert.match(h.screen.innerHTML,/<label[^>]*for="mode-input"[^>]*>[^<]+<\/label>/);
  assert.match(h.screen.innerHTML,/ร่างคำตอบที่พิมพ์.*หน้านี้/);
});
test('S01-T removed retry control focuses the cleared typed field without scrolling',()=>{
  const h=setup();h.click('data-mode','typed-recall');h.click('data-action','begin-mode');h.input('mode-input','old');h.click('data-action','hint');
  h.document.activeElement={getAttribute:a=>a==='data-action'?'retry-mode':null};h.screen.querySelectorAll=()=>[];h.screen.scrollTop=88;
  h.click('data-action','retry-mode');assert.equal(h.focused(),'mode-input');assert.equal(h.screen.scrollTop,88);
  assert.doesNotMatch(h.screen.innerHTML,/data-action="retry-mode"/);
  h.input('mode-input','kept');h.click('data-route','home');const before=h.run('JSON.stringify(state)');h.click('data-action','retry-mode');assert.equal(h.run('JSON.stringify(state)'),before);
});
function tileFocusHarness(h){
  const calls=[];
  h.screen.querySelectorAll=selector=>{
    const attribute=selector.match(/^\[([^\]]+)\]$/)?.[1];
    return (h.screen.innerHTML.match(/<button\b[^>]*>/g)||[]).filter(tag=>attribute&&tag.includes(attribute+'=')).map(tag=>({
      disabled:/\sdisabled(?:\s|>)/.test(tag),
      getAttribute:a=>tag.match(new RegExp(a+'="([^"]*)"'))?.[1]??null,
      focus:options=>{assert.doesNotMatch(tag,/\sdisabled(?:\s|>)/);calls.push([attribute,tag.match(new RegExp(attribute+'="([^"]*)"'))[1],options?.preventScroll]);}
    }));
  };
  return {calls,activate:(attribute,value)=>{h.document.activeElement={getAttribute:a=>a===attribute?value:null};h.click(attribute,value);}};
}
test('S01-S matching exposes selection, toggles a repeated tile and retains focus',()=>{
  const h=setup();h.click('data-mode','matching');h.click('data-action','begin-mode');const f=tileFocusHarness(h);
  f.activate('data-pair','book');
  const buttons=()=>h.screen.innerHTML.match(/<button[^>]*data-pair="[^"]*"[^>]*>/g);
  assert.equal(buttons().filter(tag=>tag.includes('aria-pressed="true"')).length,1);
  assert.ok(buttons().every(tag=>/aria-pressed="(?:true|false)"/.test(tag)));
  assert.deepEqual(f.calls.at(-1),['data-pair','book',true]);
  f.activate('data-pair','book');assert.equal(h.run('state.selectedPair.length'),0);assert.equal(h.run('state.feedback'),null);
  f.activate('data-pair','book');f.activate('data-pair','หนังสือ');assert.equal(h.run('state.feedback.good'),true);
  assert.equal(buttons().filter(tag=>tag.includes('aria-pressed="true"')).length,0);
  f.activate('data-pair','window');f.activate('data-pair','หนังสือ');assert.equal(h.run('state.feedback.good'),false);
});
test('S01-S scramble uses distinct indexes for repeated letters and ignores duplicate or invalid tiles',()=>{
  const h=setup();h.click('data-mode','word-scramble');h.click('data-action','begin-mode');
  h.click('data-token','2');h.click('data-token','0');
  for(const value of ['0','-1','4','1.5','NaN','','01','1x'])h.click('data-token',value);
  assert.equal(h.run('JSON.stringify(state.selectedTokens)'),'[2,0]');
  h.click('data-token','3');h.click('data-token','1');h.click('data-action','check-tokens');
  assert.equal(h.run('JSON.stringify(state.selectedTokens)'),'[2,0,3,1]');assert.equal(h.run('state.feedback.good'),true);
  h.click('data-action','clear-tokens');assert.equal(h.run('state.selectedTokens.length'),0);assert.equal(h.run('state.feedback'),null);
});
test('S01-S token focus moves forward then wraps to an enabled tile and finally check answer',()=>{
  const h=setup();h.click('data-mode','word-scramble');h.click('data-action','begin-mode');const f=tileFocusHarness(h);h.screen.scrollTop=123;
  for(const [index,next] of [['2','3'],['3','0'],['0','1'],['1',null]]){
    f.activate('data-token',index);
    assert.deepEqual(f.calls.at(-1),next?['data-token',next,true]:['data-action','check-tokens',true]);
    assert.equal(h.screen.scrollTop,123);
  }
  f.activate('data-action','clear-tokens');assert.deepEqual(f.calls.at(-1),['data-action','clear-tokens',true]);
  assert.equal((h.screen.innerHTML.match(/<button[^>]*data-token[^>]*disabled/g)||[]).length,0);
});
for(const kind of ['matching','word-scramble']){
  test(`S01-S ${kind} ignores tile controls before begin and after route, mode or owner changes`,()=>{
    const h=setup();h.click('data-mode',kind);
    const attribute=kind==='matching'?'data-pair':'data-token',value=kind==='matching'?'book':'0';
    const ignored=()=>{for(const [a,v] of [[attribute,value],...(kind==='matching'?[]:[['data-action','clear-tokens'],['data-action','check-tokens']])]){const before=h.run('JSON.stringify(state)');h.click(a,v);assert.equal(h.run('JSON.stringify(state)'),before);}};
    ignored();h.click('data-action','begin-mode');h.click(attribute,value);
    h.click('data-route','home');ignored();h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');ignored();
    h.click('data-demo-owner','demo-b');ignored();
  });
}
test('S01-S matching ignores values that are not rendered tiles',()=>{
  const h=setup();h.click('data-mode','matching');h.click('data-action','begin-mode');h.click('data-pair','book');
  const before=h.run('JSON.stringify(state)');h.click('data-pair','unknown');assert.equal(h.run('JSON.stringify(state)'),before);
});
test('camera cancellation and exit release local image and ignore stale file events',()=>{
  for(const boundary of ['cancel','route','back','owner','pagehide']){
    const h=setup();h.click('data-route','camera');h.photo();
    assert.ok(h.run('state.photoUrl'));assert.match(h.screen.innerHTML,/data-action="camera-cancel"/);
    if(boundary==='cancel')h.click('data-action','camera-cancel');
    if(boundary==='route')h.click('data-route','home');
    if(boundary==='back')h.click('data-action','back');
    if(boundary==='owner')h.click('data-demo-owner','demo-b');
    if(boundary==='pagehide')h.pagehide();
    assert.equal(h.run('state.photoUrl'),null);assert.equal(h.revoked.length,1);
    if(boundary!=='pagehide'){h.photo();assert.equal(h.run('state.photoUrl'),null);}
  }
});
test('camera unknown model and failed states provide manual alternative without readiness claims',()=>{
  const h=setup();h.click('data-route','camera');h.photo();
  assert.equal(h.run('state.cameraStage'),'missing');assert.doesNotMatch(h.screen.innerHTML,/กล้องพร้อมถ่าย/);
  for(const stage of ['denied','missing','failed','result','ready']){
    h.click('data-camera-stage',stage);assert.match(h.screen.innerHTML,/data-route="add-word"/);
    assert.match(h.screen.innerHTML,/ตัวอย่าง|จำลอง/);
    assert.doesNotMatch(h.screen.innerHTML,/ต้องเชื่อมต่ออินเทอร์เน็ตเพื่อเตรียมโมเดล/);
  }
  h.click('data-route','home');h.click('data-camera-stage','result');assert.equal(h.run('state.cameraStage'),'start');
});
test('AI readiness is explicitly unverified and cancellation rejects stale sample answers',()=>{
  const h=setup();h.click('data-route','ai-connect');
  assert.match(h.screen.innerHTML,/ผู้ให้บริการ.*งบ.*อายุ.*ยังไม่ผ่าน/);
  h.click('data-ai','on');h.input('ai-question','help');
  assert.match(h.screen.innerHTML,/data-action="ai-cancel"/);
  h.click('data-action','ai-cancel');h.click('data-action','ai-send');
  assert.equal(h.run('state.ai'),'off');assert.doesNotMatch(h.screen.innerHTML,/นี่เป็นคำตอบตัวอย่างเท่านั้น/);
  h.click('data-route','ai');h.click('data-ai','failed');h.click('data-action','ai-send');
  assert.match(h.screen.innerHTML,/data-route="practice"/);assert.doesNotMatch(h.screen.innerHTML,/นี่เป็นคำตอบตัวอย่างเท่านั้น/);
});
test('UX08 sample progress distinguishes effort from evidence and never calls samples actual results',()=>{
  const h=setup();h.run("state.scenario='returning'");h.click('data-route','progress');
  assert.match(h.screen.innerHTML,/ยังไม่มีหลักฐานยืนยันว่าจำได้/);
  assert.match(h.screen.innerHTML,/เวลา.*ไม่ใช่.*ความสามารถ/);
  assert.doesNotMatch(h.screen.innerHTML,/ดูผลจากการฝึกจริงของคุณ|คำที่เริ่มจำได้|แสดงเฉพาะกิจกรรมที่เกิดขึ้นจริง/);
});
test('UX08 empty history stays empty after sample activity and zero is not a failing learner score',async()=>{
  const h=setup();h.click('data-route','history');assert.match(h.screen.innerHTML,/ยังไม่มีประวัติ/);
  h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');h.click('data-answer','หนังสือ');
  h.click('data-route','progress');assert.match(h.screen.innerHTML,/ยังไม่มีหลักฐาน.*ไม่ได้หมายความว่าทำไม่ได้/);
  h.click('data-route','history');assert.match(h.screen.innerHTML,/ยังไม่มีประวัติ/);
  h.click('data-route','export');h.change('export-words',false);h.click('data-action','export-sample');
  const csv=await h.downloads[0].text();assert.equal(csv.trim().split('\n').length,1);
});
test('UX08 displayed sample history and exported sample history agree without inventing records',async()=>{
  const h=setup();h.run("state.scenario='returning'");h.click('data-route','history');
  const titles=['ทบทวนคำศัพท์','เลือกความหมาย','อ่านเรื่องสั้น'];
  for(const title of titles)assert.ok(h.screen.innerHTML.includes(title));
  h.click('data-route','export');h.change('export-words',false);h.click('data-action','export-sample');
  const csv=await h.downloads[0].text();assert.equal(csv.trim().split('\n').length,4);
  for(const title of titles)assert.ok(csv.includes(title));
  assert.match(h.screen.innerHTML,/ประวัติจำลอง 3 รายการ/);
});
test('import preview retains exact draft but typing invalidates candidates before confirmation',()=>{
  const h=setup();h.click('data-route','import');h.input('import-text','  apple, แอปเปิล  ');h.click('data-action','import-preview');
  assert.match(h.screen.innerHTML,/>  apple, แอปเปิล  <\/textarea>/);
  h.input('import-text','pear, ลูกแพร์');
  assert.equal(h.run('state.importCandidates.length'),0);
  h.click('data-action','import-confirm');assert.equal(h.run('state.words.length'),3);
  h.click('data-action','import-preview');h.click('data-action','import-confirm');
  assert.equal(h.run('state.words.at(-1).word'),'pear');
});
test('import cancellation and route or owner changes invalidate pending confirmation',()=>{
  for(const boundary of ['cancel','route','owner']){
    const h=setup();h.click('data-route','import');h.input('import-text','apple, แอปเปิล');h.click('data-action','import-preview');
    assert.match(h.screen.innerHTML,/data-action="import-cancel"/);
    if(boundary==='cancel')h.click('data-action','import-cancel');
    if(boundary==='route'){h.click('data-route','home');h.click('data-route','import');}
    if(boundary==='owner'){h.click('data-demo-owner','demo-b');h.click('data-demo-owner','demo-a');h.click('data-route','import');}
    h.click('data-action','import-confirm');assert.equal(h.run('state.words.length'),3);
  }
});
test('missing word routes never substitute another word and remain safe with empty lists',()=>{
  for(const empty of [false,true])for(const route of ['word-detail','edit-word','delete-word']){
    const h=setup();h.run(`state.currentWord='missing';${empty?'state.words=[];':''}`);
    h.click('data-route',route);assert.match(h.screen.innerHTML,/ไม่พบคำที่เลือก/);
    assert.doesNotMatch(h.screen.innerHTML,/data-action="(?:save-edit-word|confirm-delete-word)"/);
    h.input('edit-meaning','changed');h.click('data-action','save-edit-word');h.click('data-action','confirm-delete-word');
    assert.equal(h.run('state.words.length'),empty?0:3);
    assert.doesNotMatch(h.screen.innerHTML,/แก้ความหมายในต้นแบบแล้ว|ลบคำตัวอย่างแล้ว/);
  }
});
test('edit and delete cancel preserve words and stale actions cannot mutate after leaving',()=>{
  for(const route of ['edit-word','delete-word']){
    const h=setup();h.click('data-word','book');h.click('data-route',route);
    if(route==='edit-word'){assert.match(h.screen.innerHTML,/ยกเลิก/);h.input('edit-meaning','changed');}
    h.click('data-action','back');h.click('data-action',route==='edit-word'?'save-edit-word':'confirm-delete-word');
    assert.equal(h.run('state.words.length'),3);assert.equal(h.run('state.words[0].meaning'),'หนังสือ');
    h.click('data-route',route);
    if(route==='edit-word')h.input('edit-meaning','updated');
    h.click('data-action',route==='edit-word'?'save-edit-word':'confirm-delete-word');
    assert.equal(h.run('state.words.length'),route==='edit-word'?3:2);
    if(route==='edit-word')assert.equal(h.run('state.words[0].meaning'),'updated');
  }
});
// Draft regression cases exercise input/click boundaries, not a browser.
function setup({audio=false}={}){
  const listeners={};
  const downloads=[];const revoked=[];let blob;
  let focused=null;
  const heading={focus:()=>{focused='heading';}};
  const replacement={getAttribute:()=> 'pilot-help',focus:()=>{focused='pilot-help';}};
  const screen={contains:node=>Object.values(nodes).includes(node),innerHTML:'',scrollTop:0,querySelectorAll:selector=>selector==='[data-action]'?[replacement]:[],querySelector:()=>heading};
  const nodes={'app-screen':screen,'workflow-map':{},'mode-map':{},'lab-map':{}};
  const document={body:{append:()=>{}},createElement:()=>({click:()=>downloads.push(blob),remove:()=>{}}),getElementById:id=>nodes[id]||null,querySelectorAll:()=>[],addEventListener:(type,fn)=>listeners[type]=fn};
  const windowListeners={},spoken=[];let cancelled=0;
  const window={addEventListener:(type,fn)=>windowListeners[type]=fn};
  if(audio)window.speechSynthesis={cancel:()=>{cancelled++;},speak:utterance=>spoken.push(utterance)};
  const context=vm.createContext({document,location:{search:''},Blob,URL:{createObjectURL:value=>{blob=value;return 'blob:host-double';},revokeObjectURL:value=>revoked.push(value)},setTimeout:fn=>fn(),URLSearchParams,console,window,SpeechSynthesisUtterance:class{constructor(text){this.text=text;}}});
  vm.runInContext(fs.readFileSync(path.join(__dirname,'lexiquest-full-ux.js'),'utf8'),context);
  const run=code=>vm.runInContext(code,context);
  const click=(attribute,value)=>listeners.click({target:{closest:selector=>selector===`[${attribute}]`?{dataset:{[attribute.replace(/^data-/,'').replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]:value},closest:()=>null}:null}});
  return {screen,run,click,document,spoken,downloads,revoked,photo:()=>listeners.change({target:{id:'photo-input',files:[new Blob(['sample'],{type:'image/png'})]}}),change:(id,checked)=>listeners.change({target:{id,checked}}),cancelled:()=>cancelled,hide:()=>{document.hidden=true;listeners.visibilitychange?.();},pagehide:()=>windowListeners.pagehide?.(),focused:()=>focused,input:(id,value)=>{nodes[id]={id,value,selectionStart:1,selectionEnd:3,selectionDirection:'backward',getAttribute:()=>null,focus:()=>{focused=id;},setSelectionRange:(start,end,direction)=>{nodes[id].restoredSelection=[start,end,direction];}};listeners.input({target:nodes[id]});}};
}
test('export cancel rejects stale download and selection controls exact sample CSV payload',async()=>{
  const h=setup();h.click('data-route','export');h.click('data-action','back');h.click('data-action','export-sample');
  assert.equal(h.downloads.length,0);
  h.click('data-route','export');h.change('export-words',false);h.change('export-history',false);h.click('data-action','export-sample');
  assert.equal(h.downloads.length,0);assert.match(h.screen.innerHTML,/เลือกข้อมูลอย่างน้อยหนึ่งอย่าง/);
  h.change('export-words',true);h.click('data-action','export-sample');
  assert.equal(h.downloads.length,1);const csv=await h.downloads[0].text();
  assert.match(csv,/book/);assert.doesNotMatch(csv,/"ประวัติ"/);assert.equal(h.revoked.length,1);
  assert.match(h.screen.innerHTML,/คำศัพท์ตัวอย่าง 3 รายการ/);
});
test('UX-D01 new entry offers both independent teaching routes without quiz or login',()=>{
  const h=setup();
  assert.match(h.screen.innerHTML,/data-pilot-track="phonics"/);
  assert.match(h.screen.innerHTML,/data-pilot-track="story"/);
  assert.doesNotMatch(h.screen.innerHTML,/data-mode="meaning-quiz"/);
  h.click('data-pilot-track','story');
  assert.equal(h.run('state.route'),'pilot');
  assert.match(h.screen.innerHTML,/ดูตัวอย่าง|ฟังหรืออ่านเรื่องสั้น/);
});
test('pilot pause/resume preserves each track step and support, never fabricates answers',()=>{
  const h=setup(); h.click('data-pilot-track','phonics');
  h.click('data-action','pilot-next'); h.click('data-action','pilot-help');
  assert.match(h.screen.innerHTML,/คำช่วย/);
  h.click('data-action','pilot-pause');
  h.click('data-pilot-track','story'); h.click('data-action','pilot-next');
  h.click('data-action','pilot-pause'); h.click('data-pilot-track','phonics');
  assert.match(h.screen.innerHTML,/รูปตัวเขียนกับเสียง/);
  assert.match(h.screen.innerHTML,/คำช่วย/);
  h.click('data-action','pilot-pause'); h.click('data-action','pilot-resume');
  assert.equal(h.run('state.route'),'pilot');
  assert.match(h.screen.innerHTML,/รูปตัวเขียนกับเสียง/);
  assert.doesNotMatch(h.screen.innerHTML,/ได้รับ XP|อ่านคล่องแล้ว|ผ่านระดับ/);
});
test('pilot missing audio is explicit, skip/finish allow other track without microphone',()=>{
  const h=setup();h.click('data-pilot-track','phonics');h.click('data-action','pilot-next');
  h.click('data-action','pilot-audio');assert.match(h.screen.innerHTML,/ยังไม่มีเสียงที่ผ่านตรวจ/);
  h.click('data-action','pilot-skip');
  assert.equal(h.run('state.pilotProgress.phonics.outcomes[1]'),'skipped');
  for(let i=0;i<12;i++)h.click('data-action','pilot-next');
  assert.match(h.screen.innerHTML,/ยังไม่ได้ตรวจ/);
  h.click('data-pilot-track','story');assert.equal(h.run('state.pilotTrack'),'story');
});
test('UX-D02 reading selector changes passage and question content through mode entry',()=>{
  const h=setup();h.click('data-route','reading');
  const passages=[];
  for(const level of ['เริ่มต้น','กำลังฝึก','อ่านคล่อง']){
    h.click('data-level',level);h.click('data-mode','cefr-reading');h.click('data-action','begin-mode');
    passages.push(h.run('currentMode().sample'));
    assert.ok(h.screen.innerHTML.includes(h.run('currentMode().sample')));
    assert.ok(h.screen.innerHTML.includes(h.run('currentMode().question')));
    h.click('data-answer',h.run('currentMode().answer'));
    assert.equal(h.run('state.feedback.good'),true);
    h.click('data-route','reading');
  }
  assert.equal(new Set(passages).size,3);
});
test('UX-D03 typing draft survives leaving before review and re-entering writing',()=>{
  const h=setup();h.click('data-lab-module','writing');h.input('lab-writing','I will be ten minutes late. <ok>');
  h.click('data-route','home');h.click('data-lab-module','picture');h.click('data-lab-module','writing');
  assert.match(h.screen.innerHTML,/I will be ten minutes late\. &lt;ok&gt;/);
  assert.match(h.screen.innerHTML,/ปิดหรือโหลดหน้าใหม่/);
});
test('UX-D04 feedback retains scroll while navigating to another screen resets it',()=>{
  const h=setup();h.click('data-lab-module','sentence');h.screen.scrollTop=340;
  h.click('data-lab-answer','wrong');assert.equal(h.screen.scrollTop,340);
  h.click('data-lab-answer','right');assert.equal(h.screen.scrollTop,340);
  h.click('data-route','home');assert.equal(h.screen.scrollTop,0);
});
test('pilot content is a pinned teaching subset with assessment answers excluded',()=>{
  const h=setup();const pack=JSON.parse(fs.readFileSync(path.join(__dirname,'../development/ux-delivery/pilot-content-r1.json'),'utf8'));
  assert.equal(h.run('typeof pilotContent'),'object');
  assert.equal(h.run('pilotContent.revision'),pack.revision);
  assert.deepEqual(JSON.parse(h.run('JSON.stringify(pilotContent.tracks)')),pack.tracks.map(({id,title,steps})=>({id,title,steps})));
  assert.equal(h.run('JSON.stringify(pilotContent).includes("ph-post-tap")'),false);
});
test('pilot repeat returns only the selected track to demonstration without wiping other progress',()=>{
  const h=setup();h.click('data-pilot-track','story');h.click('data-action','pilot-next');
  h.click('data-pilot-track','phonics');for(let i=0;i<6;i++)h.click('data-action','pilot-next');
  assert.match(h.screen.innerHTML,/data-action="pilot-restart"/);
  h.click('data-action','pilot-restart');
  assert.match(h.screen.innerHTML,/ดูตัวอย่างก่อน/);
  h.click('data-pilot-track','story');assert.match(h.screen.innerHTML,/น้ำหนึ่งแก้ว/);
});
test('keyboard focus remains on help toggle after render and moves to heading on navigation',()=>{
  const h=setup();h.click('data-pilot-track','phonics');
  assert.equal(h.focused(),'heading');
  h.document.activeElement={getAttribute:attr=>attr==='data-action'?'pilot-help':null};
  h.click('data-action','pilot-help');assert.equal(h.focused(),'pilot-help');
  h.click('data-route','home');assert.equal(h.focused(),'heading');
});
test('feedback after a hint does not invent independent learner evidence',()=>{
  const h=setup();h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');
  h.click('data-action','hint');h.click('data-answer','หนังสือ');
  assert.equal(h.run('state.feedback.good'),true);
  assert.doesNotMatch(h.screen.innerHTML,/ตอบด้วยตัวเองแล้ว/);
  assert.match(h.screen.innerHTML,/ไม่บันทึกผลการเรียน/);
});
test('S01-F changing demo owner isolates drafts, words and resume; returning restores only that owner',()=>{
  const h=setup();h.click('data-lab-module','writing');h.input('lab-writing','Draft for A');
  h.click('data-pilot-track','phonics');h.click('data-action','pilot-next');
  h.run("state.words.push({word:'private-example',meaning:'A',category:'demo'});state.pendingDelete=true");
  h.click('data-route','account');assert.match(h.screen.innerHTML,/data-demo-owner="demo-b"/);
  h.click('data-demo-owner','demo-b');assert.equal(h.run('state.labDraft'),'');
  assert.equal(h.run('state.pilotLastTrack'),null);assert.equal(h.run('state.pendingDelete'),false);
  assert.equal(h.run("state.words.some(w=>w.word==='private-example')"),false);
  h.click('data-lab-module','writing');h.input('lab-writing','Draft for B');
  h.click('data-demo-owner','demo-a');assert.equal(h.run('state.labDraft'),'Draft for A');
  h.click('data-action','pilot-resume');assert.match(h.screen.innerHTML,/รูปตัวเขียนกับเสียง/);
  h.click('data-demo-owner','invalid');assert.equal(h.run('state.labDraft'),'Draft for A');
});
test('S01-F leaving or changing a same-route activity cancels draft speech',()=>{
  const h=setup({audio:true});h.click('data-lab-module','listening');h.click('data-action','lab-play-audio');
  const count=h.cancelled();assert.equal(h.spoken.length,1);
  h.click('data-route','home');assert.ok(h.cancelled()>count);
  h.click('data-lab-module','listening');h.click('data-action','lab-play-audio');const next=h.cancelled();
  h.click('data-lab-module','writing');assert.ok(h.cancelled()>next);
});
test('S01-F explicit stop, background and page exit cancel audio; late errors do not attach to next owner',()=>{
  const h=setup({audio:true});h.click('data-lab-module','listening');h.click('data-action','lab-play-audio');
  assert.match(h.screen.innerHTML,/data-action="stop-audio"/);let count=h.cancelled();
  h.click('data-action','stop-audio');assert.ok(h.cancelled()>count);
  h.click('data-action','lab-play-audio');count=h.cancelled();h.hide();assert.ok(h.cancelled()>count);
  h.document.hidden=false;h.click('data-action','lab-play-audio');count=h.cancelled();h.pagehide();assert.ok(h.cancelled()>count);
  h.click('data-action','lab-play-audio');const old=h.spoken.at(-1);h.click('data-demo-owner','demo-b');
  const current=h.screen.innerHTML;old.onerror?.({error:'fixture'});assert.equal(h.screen.innerHTML,current);
});
test('S01-F changing exam task stops speech even without a route change',()=>{
  const h=setup({audio:true});h.click('data-route','exam');h.click('data-exam-task','listening');
  h.click('data-action','play-exam-audio');const count=h.cancelled();
  h.click('data-exam-task','reading');assert.ok(h.cancelled()>count);
  assert.doesNotMatch(h.screen.innerHTML,/กำลังเล่นเสียงจำลอง/);
});

test('exam draft captures typing before review and keeps exact text across tasks, tracks and owners',()=>{
  const h=setup();h.click('data-route','exam');h.click('data-exam-task','writing');
  const original='  My <draft>\nwith spaces  ';
  h.input('exam-writing',original);
  h.click('data-exam-task','reading');h.click('data-exam-task','writing');
  assert.equal(h.run('state.examDraft'),original);
  assert.match(h.screen.innerHTML,/&lt;draft&gt;/);
  h.click('data-exam-track','ielts');h.click('data-exam-task','writing');
  assert.equal(h.run('state.examDraft'),'');h.input('exam-writing','IELTS only');
  h.click('data-demo-owner','demo-b');h.click('data-route','exam');h.click('data-exam-task','writing');
  assert.equal(h.run('state.examDraft'),'');h.input('exam-writing','Owner B');
  h.click('data-demo-owner','demo-a');h.click('data-route','exam');
  assert.equal(h.run('state.examDraft'),'IELTS only');
  h.click('data-exam-track','toeic');h.click('data-exam-task','writing');
  assert.equal(h.run('state.examDraft'),original);
  h.click('data-route','home');h.click('data-route','exam');assert.equal(h.run('state.examDraft'),original);
  assert.match(h.screen.innerHTML,/ปิดหรือโหลดหน้าใหม่/);
  const fresh=setup();assert.equal(fresh.run('state.examDraft'),'');
});
test('review preserves exact draft and editing clears stale review feedback',()=>{
  const h=setup();h.click('data-route','exam');h.click('data-exam-task','writing');
  h.input('exam-writing','  hello  ');h.click('data-action','exam-writing-review');
  assert.equal(h.run('state.examFeedback'),'self-review');assert.equal(h.run('state.examDraft'),'  hello  ');
  h.input('exam-writing','');assert.equal(h.run('state.examFeedback'),null);
  h.click('data-action','exam-writing-review');assert.equal(h.run('state.examFeedback'),null);
  h.click('data-lab-module','writing');h.input('lab-writing','  lab  ');h.click('data-action','lab-review-writing');
  assert.equal(h.run('state.labDraft'),'  lab  ');assert.equal(h.run('state.labFeedback'),'self-review');
});
test('discard needs explicit confirmation, cancels safely and cannot cross draft or owner boundary',()=>{
  const h=setup();h.click('data-route','exam');h.click('data-exam-task','writing');h.input('exam-writing','keep');
  h.click('data-action','exam-discard');assert.equal(h.run('state.examDraft'),'keep');
  assert.match(h.screen.innerHTML,/data-action="confirm-draft-discard"/);
  h.click('data-action','cancel-draft-discard');h.click('data-action','confirm-draft-discard');
  assert.equal(h.run('state.examDraft'),'keep');
  h.click('data-action','exam-discard');h.click('data-exam-track','ielts');h.click('data-exam-task','writing');h.input('exam-writing','other');
  h.click('data-action','confirm-draft-discard');assert.equal(h.run('state.examDraft'),'other');
  h.click('data-action','exam-discard');h.click('data-demo-owner','demo-b');h.click('data-demo-owner','demo-a');h.click('data-action','confirm-draft-discard');
  assert.equal(h.run('state.examDraft'),'other');
  h.click('data-route','exam');h.click('data-action','exam-discard');h.click('data-action','confirm-draft-discard');
  assert.equal(h.run('state.examDraft'),'');
  h.click('data-exam-track','toeic');h.click('data-exam-task','writing');assert.equal(h.run('state.examDraft'),'keep');
  h.click('data-lab-module','writing');h.input('lab-writing','lab');h.click('data-action','lab-discard');
  h.click('data-action','cancel-draft-discard');assert.equal(h.run('state.labDraft'),'lab');
  h.click('data-action','lab-discard');h.click('data-action','confirm-draft-discard');assert.equal(h.run('state.labDraft'),'');
});

test('story Thai support toggles independently, labels reading modality and survives pause',()=>{
  const h=setup();h.click('data-pilot-track','story');h.click('data-action','pilot-next');
  assert.match(h.screen.innerHTML,/data-action="pilot-thai"/);
  assert.match(h.screen.innerHTML,/อ่านเรื่อง.*ไม่ใช่ผลการฟัง/);
  assert.doesNotMatch(h.screen.innerHTML,/มะลิไปที่ร้าน/);
  h.click('data-action','pilot-thai');assert.match(h.screen.innerHTML,/มะลิไปที่ร้าน/);
  assert.match(h.screen.innerHTML,/aria-expanded="true"/);
  h.click('data-action','pilot-pause');h.click('data-action','pilot-resume');assert.match(h.screen.innerHTML,/มะลิไปที่ร้าน/);
  h.click('data-action','pilot-thai');assert.doesNotMatch(h.screen.innerHTML,/มะลิไปที่ร้าน/);
});
test('content revision resets stale support and position with notice and preserves other track',()=>{
  const h=setup();h.click('data-pilot-track','phonics');h.click('data-action','pilot-next');
  h.click('data-pilot-track','story');h.click('data-action','pilot-next');h.click('data-action','pilot-help');
  h.run("pilotContent.revision='new-review-draft'");h.click('data-action','pilot-pause');h.click('data-action','pilot-resume');
  assert.equal(h.run('state.pilotProgress.story.step'),0);assert.equal(h.run('state.pilotProgress.story.help'),false);
  assert.equal(h.run('state.pilotProgress.phonics.step'),1);
  assert.match(h.screen.innerHTML,/เนื้อหาเปลี่ยนรุ่น/);
  h.click('data-action','pilot-next');assert.doesNotMatch(h.screen.innerHTML,/มะลิไปที่ร้าน/);
});


test('add form preserves exact partial and duplicate input across feedback and owner re-entry',()=>{
  const h=setup();h.click('data-route','add-word');h.input('new-word','  <pear>  ');h.input('new-meaning','');h.click('data-action','add-word');
  assert.match(h.screen.innerHTML,/value="  &lt;pear&gt;  "/);
  h.input('new-word','book');h.input('new-meaning','  alternate  ');h.click('data-action','add-word');
  assert.match(h.screen.innerHTML,/value="  alternate  "/);assert.equal(h.run('state.words.length'),3);
  h.click('data-demo-owner','demo-b');h.click('data-route','add-word');assert.doesNotMatch(h.screen.innerHTML,/value="  alternate  "/);
  h.click('data-demo-owner','demo-a');h.click('data-route','add-word');assert.match(h.screen.innerHTML,/value="  alternate  "/);
});
test('add cancel and off-route actions cannot add stale words and success clears draft',()=>{
  const h=setup();h.click('data-route','add-word');h.input('new-word','pear');h.input('new-meaning','fruit');
  assert.match(h.screen.innerHTML,/data-action="add-word-cancel"/);h.click('data-action','add-word-cancel');h.click('data-action','add-word');assert.equal(h.run('state.words.length'),3);
  h.click('data-route','add-word');assert.doesNotMatch(h.screen.innerHTML,/value="pear"/);
  h.input('new-word','pear');h.input('new-meaning','fruit');h.click('data-action','add-word');h.click('data-action','add-word');assert.equal(h.run('state.words.length'),4);
  h.click('data-route','add-word');assert.doesNotMatch(h.screen.innerHTML,/value="pear"/);
});
test('edit draft survives feedback but cancel restores persisted meaning',()=>{
  const h=setup();h.click('data-word','book');h.click('data-route','edit-word');h.input('edit-meaning','  revised  ');h.run("message('feedback')");
  assert.match(h.screen.innerHTML,/value="  revised  "/);h.input('edit-meaning','   ');h.click('data-action','save-edit-word');assert.match(h.screen.innerHTML,/value="   "/);
  assert.equal(h.run('state.words[0].meaning'),'หนังสือ');h.click('data-action','back');h.click('data-route','edit-word');assert.match(h.screen.innerHTML,/value="หนังสือ"/);
});
test('import preserves line numbers and shows invalid duplicate and accepted row outcomes',()=>{
  const h=setup();h.click('data-route','import');const draft='pear, fruit\n\n, missing word\nBOOK, duplicate\npear, repeated\norange,\nextra, a, b';h.input('import-text',draft);h.click('data-action','import-preview');
  for(const n of [1,3,4,5,6,7])assert.ok(h.screen.innerHTML.includes(`บรรทัด ${n}`));
  assert.match(h.screen.innerHTML,/ขาดคำอังกฤษ/);assert.match(h.screen.innerHTML,/ขาดความหมาย/);assert.match(h.screen.innerHTML,/คำซ้ำ/);assert.match(h.screen.innerHTML,/รูปแบบไม่ถูกต้อง/);
  h.click('data-action','import-confirm');assert.equal(h.run('state.words.length'),4);assert.equal(h.run('state.importDraft'),draft);
  assert.match(h.screen.innerHTML,/เพิ่มแล้ว/);assert.match(h.screen.innerHTML,/บรรทัด 3/);h.click('data-action','import-confirm');assert.equal(h.run('state.words.length'),4);
  h.input('import-text','orange, fruit');h.click('data-action','import-preview');h.click('data-action','import-confirm');assert.equal(h.run('state.words.length'),5);
});


test('same-view render restores focused form field and selection but navigation focuses heading',()=>{
  const h=setup();h.click('data-route','add-word');h.input('new-word','pearl');const field=h.document.getElementById('new-word');h.document.activeElement=field;
  h.run("message('feedback')");assert.equal(h.focused(),'new-word');assert.deepEqual(field.restoredSelection,[1,3,'backward']);
  h.click('data-route','home');assert.equal(h.focused(),'heading');
});
test('add validation links persistent field errors and focuses first invalid field',()=>{
  const h=setup();h.click('data-route','add-word');h.input('new-word','');h.input('new-meaning','');h.click('data-action','add-word');
  assert.match(h.screen.innerHTML,/id="new-word"[^>]*aria-invalid="true"[^>]*aria-describedby="new-word-error"/);
  assert.match(h.screen.innerHTML,/id="new-word-error"/);assert.match(h.screen.innerHTML,/id="new-meaning-error"/);assert.equal(h.focused(),'new-word');
  h.run('render()');assert.match(h.screen.innerHTML,/id="new-word-error"/);
  h.input('new-word','pear');h.click('data-action','add-word');assert.doesNotMatch(h.screen.innerHTML,/id="new-word"[^>]*aria-invalid="true"/);assert.equal(h.focused(),'new-meaning');
  h.input('new-word','book');h.input('new-meaning','alternate');h.click('data-action','add-word');assert.match(h.screen.innerHTML,/id="new-word-error"[^>]*>[^<]*มีคำนี้/);
  h.click('data-action','add-word-cancel');h.click('data-route','add-word');assert.doesNotMatch(h.screen.innerHTML,/aria-invalid="true"/);
});
test('edit validation has linked field error and clears after correction',()=>{
  const h=setup();h.click('data-word','book');h.click('data-route','edit-word');h.input('edit-meaning','');h.click('data-action','save-edit-word');
  assert.match(h.screen.innerHTML,/id="edit-meaning"[^>]*aria-invalid="true"[^>]*aria-describedby="edit-meaning-error"/);assert.equal(h.focused(),'edit-meaning');
  h.input('edit-meaning','updated');h.click('data-action','save-edit-word');assert.equal(h.run('state.words[0].meaning'),'updated');assert.doesNotMatch(h.screen.innerHTML,/aria-invalid="true"/);
});


test('S01-N no-evidence weakness offers practice without invented errors after sample answers',()=>{
  for(const scenario of ['new','offline']){
    const h=setup();h.run(`state.scenario='${scenario}'`);h.click('data-route','weakness');
    assert.match(h.screen.innerHTML,/ยังไม่มีหลักฐาน.*ไม่ได้หมายความว่าทำไม่ได้/);
    assert.doesNotMatch(h.screen.innerHTML,/window|door|เคยตอบสับสน/);
    assert.match(h.screen.innerHTML,/data-route="mode:meaning-quiz"/);
    h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');h.click('data-answer','wrong');
    h.click('data-route','weakness');assert.doesNotMatch(h.screen.innerHTML,/window|door|เคยตอบสับสน/);
  }
});
test('S01-N returning weakness is simulated and does not leak into an empty owner',()=>{
  const h=setup();h.click('data-scenario','returning');h.click('data-route','weakness');
  assert.match(h.screen.innerHTML,/ประวัติจำลอง/);assert.match(h.screen.innerHTML,/ไม่ใช่ผลการเรียนหรือข้อมูลบัญชีจริง/);
  assert.match(h.screen.innerHTML,/window/);
  h.click('data-demo-owner','demo-b');h.click('data-route','weakness');assert.doesNotMatch(h.screen.innerHTML,/window|door/);
  h.click('data-demo-owner','demo-a');h.click('data-route','weakness');assert.match(h.screen.innerHTML,/ประวัติจำลอง/);
  h.click('data-scenario','new');h.click('data-route','weakness');assert.doesNotMatch(h.screen.innerHTML,/window|door/);
});


test('S01-O goal and font expose exactly one selected option across choices and re-entry',()=>{
  const h=setup();h.document.documentElement={style:{setProperty:()=>{}}};h.document.body.classList={toggle:()=>{}};
  for(const [route,attribute,values] of [['plan','data-goal',['5','10','15']],['settings','data-font',['1','1.12']]]){
    h.click('data-route',route);
    for(const value of values){
      h.click(attribute,value);
      const buttons=h.screen.innerHTML.match(/<button[^>]*>/g).filter(tag=>tag.includes(attribute+'='));
      assert.equal(buttons.filter(tag=>tag.includes('aria-pressed="true"')).length,1);
      assert.ok(buttons.find(tag=>tag.includes(attribute+'="'+value+'"')).includes('aria-pressed="true"'));
      assert.ok(buttons.every(tag=>/aria-pressed="(?:true|false)"/.test(tag)));
      h.click('data-route','home');h.click('data-route',route);
      assert.ok(h.screen.innerHTML.match(/<button[^>]*>/g).find(tag=>tag.includes(attribute+'="'+value+'"')).includes('aria-pressed="true"'));
    }
  }
});
test('S01-O contrast announces state with a stable accessible toggle name',()=>{
  const h=setup();h.document.body.classList={toggle:()=>{}};h.click('data-route','settings');
  const toggle=()=>h.screen.innerHTML.match(/<button[^>]*data-action="toggle-contrast"[^>]*>[^<]*<\/button>/)[0];
  const label=()=>toggle().match(/>([^<]*)<\/button>/)[1];const original=label();assert.match(toggle(),/aria-pressed="false"/);
  h.click('data-action','toggle-contrast');assert.match(toggle(),/aria-pressed="true"/);assert.equal(label(),original);
  h.click('data-action','toggle-contrast');assert.match(toggle(),/aria-pressed="false"/);assert.equal(label(),original);
});
test('S01-O preference rerender retains active choice focus while navigation focuses heading',()=>{
  for(const [route,attribute,value] of [['plan','data-goal','10'],['settings','data-font','1.12']]){
    const h=setup();h.document.documentElement={style:{setProperty:()=>{}}};h.document.body.classList={toggle:()=>{}};h.click('data-route',route);
    let restored=false;h.document.activeElement={getAttribute:a=>a===attribute?value:null};
    h.screen.querySelectorAll=selector=>selector===`[${attribute}]`?[{getAttribute:a=>a===attribute?value:null,focus:()=>{restored=true;}}]:[];
    h.click(attribute,value);assert.equal(restored,true);
    h.click('data-route','home');assert.equal(h.focused(),'heading');
  }
});


for(const [route,attribute,values] of [['words','data-category',['ทั้งหมด','คำทั่วไป','คำของฉัน']],['reading','data-level',['เริ่มต้น','กำลังฝึก','อ่านคล่อง']]]){
  test(`S01-P ${route} exposes one selected filter and retains it on re-entry`,()=>{
    const h=setup();h.click('data-route',route);
    for(const value of values){
      h.click(attribute,value);
      const buttons=h.screen.innerHTML.match(/<button[^>]*>/g).filter(tag=>tag.includes(attribute+'='));
      assert.equal(buttons.filter(tag=>tag.includes('aria-pressed="true"')).length,1);
      assert.ok(buttons.find(tag=>tag.includes(attribute+'="'+value+'"'))?.includes('aria-pressed="true"'));
      assert.ok(buttons.every(tag=>/aria-pressed="(?:true|false)"/.test(tag)));
      h.click('data-route','home');h.click('data-route',route);
      assert.ok(h.screen.innerHTML.match(/<button[^>]*>/g).find(tag=>tag.includes(attribute+'="'+value+'"'))?.includes('aria-pressed="true"'));
    }
  });
}
for(const [route,attribute,value] of [['words','data-category','คำของฉัน'],['reading','data-level','อ่านคล่อง'],['exam','data-exam-track','ielts'],['exam','data-exam-task','reading'],['exam','data-exam-answer','right']]){
  test(`S01-P ${attribute} same-view click restores only an actual rendered control`,()=>{
    const h=setup();h.click('data-route',route);if(attribute==='data-exam-answer')h.click('data-exam-task','reading');
    let restored=false;
    h.document.activeElement={getAttribute:a=>a===attribute?value:null};
    h.screen.querySelectorAll=selector=>selector===`[${attribute}]`?(h.screen.innerHTML.match(/<button[^>]*>/g)||[]).filter(tag=>tag.includes(attribute+'=' )).map(tag=>({getAttribute:a=>a===attribute?tag.match(new RegExp(attribute+'="([^" ]*)"'))?.[1]:null,focus:()=>{restored=true;}})):[];
    h.click(attribute,value);assert.equal(restored,true);
    if(attribute==='data-exam-answer')assert.equal(h.run('state.examFeedback'),'right');
    if(attribute==='data-exam-task')assert.equal(h.run('state.examTask'),'reading');
    h.click('data-route','home');assert.equal(h.focused(),'heading');
  });
}


test('S01-Q sync sample states expose exactly one selected state and retain focus',()=>{
  const h=setup();h.click('data-route','sync');
  for(const value of ['idle','queued','conflict']){
    let restored=false;h.document.activeElement={getAttribute:a=>a==='data-sync'?value:null};
    h.screen.querySelectorAll=selector=>selector==='[data-sync]'?(h.screen.innerHTML.match(/<button[^>]*data-sync="[^"]*"[^>]*>/g)||[]).map(tag=>({getAttribute:a=>a==='data-sync'?tag.match(/data-sync="([^"]*)"/)[1]:null,focus:()=>{restored=true;}})):[];
    h.click('data-sync',value);
    const tags=h.screen.innerHTML.match(/<button[^>]*data-sync="[^"]*"[^>]*>/g);
    assert.equal(tags.filter(tag=>tag.includes('aria-pressed="true"')).length,1);
    assert.ok(tags.find(tag=>tag.includes('data-sync="'+value+'"')).includes('aria-pressed="true"'));
    assert.ok(tags.every(tag=>/aria-pressed="(?:true|false)"/.test(tag)));assert.equal(restored,true);
  }
});
test('S01-Q removed conflict choice moves focus to heading without changing owner words',()=>{
  const h=setup();h.click('data-route','sync');h.click('data-sync','conflict');
  const before=h.run('JSON.stringify(state.words)');let headingFocus=0;
  h.screen.querySelector=selector=>selector==='h1'?{focus:()=>{headingFocus++;}}:null;
  h.document.activeElement={getAttribute:a=>a==='data-action'?'sync-choice':null};h.screen.querySelectorAll=()=>[];
  h.click('data-action','sync-choice');assert.equal(headingFocus,1);assert.equal(h.run('state.sync'),'idle');
  assert.equal(h.run('JSON.stringify(state.words)'),before);assert.match(h.screen.innerHTML,/ตัวอย่างการเลือกข้อมูล/);
  assert.doesNotMatch(h.screen.innerHTML,/data-action="sync-choice"/);
});
test('S01-Q stale sync controls cannot change another view or resolve a non-conflict state',()=>{
  const h=setup();h.click('data-route','sync');h.click('data-sync','queued');
  h.click('data-action','sync-choice');assert.equal(h.run('state.sync'),'queued');
  h.click('data-route','words');h.click('data-sync','conflict');assert.equal(h.run('state.sync'),'queued');
  h.click('data-action','sync-choice');assert.equal(h.run('state.sync'),'queued');assert.equal(h.run('state.route'),'words');
});


for(const [route,field,key] of [['import','import-text','importDraft'],['words','word-search','wordQuery']]){
  test(`S01-R ${field} rejects input after exit and owner switch`,()=>{
    const h=setup();h.click('data-route',route);h.input(field,'kept');h.click('data-route','home');h.input(field,'late');
    assert.equal(h.run('state.'+key),'kept');
    h.click('data-demo-owner','demo-b');h.input(field,'owner A late');assert.equal(h.run('state.'+key),'');
    h.click('data-demo-owner','demo-a');assert.equal(h.run('state.'+key),'kept');
  });
}
test('S01-R exam writing cannot overwrite drafts from another task or an exited view',()=>{
  const h=setup();h.click('data-route','exam');h.click('data-exam-task','writing');h.input('exam-writing','kept');
  h.click('data-exam-task','reading');const before=h.run('JSON.stringify(state.examDrafts)');h.input('exam-writing','late');
  assert.equal(h.run('JSON.stringify(state.examDrafts)'),before);
  h.click('data-exam-task','writing');assert.equal(h.run('state.examDraft'),'kept');
  h.click('data-route','home');h.input('exam-writing','late exit');assert.equal(h.run('state.examDraft'),'kept');
  h.click('data-demo-owner','demo-b');h.input('exam-writing','owner A late');assert.equal(h.run('state.examDraft'),'');assert.equal(h.run('Object.keys(state.examDrafts).length'),0);
});
test('S01-R lab writing cannot overwrite a retained draft outside its writing activity',()=>{
  const h=setup();h.click('data-lab-module','writing');h.input('lab-writing','kept');h.click('data-lab-module','listening');h.input('lab-writing','late');
  assert.equal(h.run('state.labDraft'),'kept');h.click('data-route','home');h.input('lab-writing','late exit');assert.equal(h.run('state.labDraft'),'kept');
  h.click('data-demo-owner','demo-b');h.input('lab-writing','owner A late');assert.equal(h.run('state.labDraft'),'');
});
test('S01-R export checkbox changes apply only while export controls are present',()=>{
  const h=setup();h.click('data-route','export');h.change('export-words',false);h.change('export-history',false);h.click('data-route','home');
  h.change('export-words',true);h.change('export-history',true);assert.equal(h.run('state.exportWords'),false);assert.equal(h.run('state.exportHistory'),false);
  h.click('data-demo-owner','demo-b');h.change('export-words',false);h.change('export-history',false);assert.equal(h.run('state.exportWords'),true);assert.equal(h.run('state.exportHistory'),true);
});


for(const kind of ['exam','lab']){
  test(`S01-R ${kind} review ignores removed writing controls`,()=>{
    const h=setup();
    if(kind==='exam'){h.click('data-route','exam');h.click('data-exam-task','writing');}else h.click('data-lab-module','writing');
    h.input(kind+'-writing','kept');
    if(kind==='exam')h.click('data-exam-task','reading');else h.click('data-lab-module','listening');
    const before=h.run('JSON.stringify(state)');h.click('data-action',kind==='exam'?'exam-writing-review':'lab-review-writing');assert.equal(h.run('JSON.stringify(state)'),before);
    h.click('data-demo-owner','demo-b');const empty=h.run('JSON.stringify(state)');h.click('data-action',kind==='exam'?'exam-writing-review':'lab-review-writing');assert.equal(h.run('JSON.stringify(state)'),empty);
  });
}

// Canvas boundary double: replacing innerHTML destroys pixels and event targets.
function canvasHarness(){
 const h=setup({audio:true});let canvas=null,html=h.screen.innerHTML;
 const get=h.document.getElementById;h.document.getElementById=id=>id==='writing-canvas'?canvas:get(id);
 Object.defineProperty(h.screen,'innerHTML',{get:()=>html,set:value=>{
  html=value;canvas=null;if(!value.includes('id="writing-canvas"'))return;
  const events={},segments=[];let from;
  const ctx={beginPath(){},moveTo(x,y){from=[x,y];},lineTo(x,y){segments.push([from,[x,y]]);from=[x,y];},stroke(){},clearRect(){segments.length=0;}};
  canvas={width:310,height:155,segments,getContext:()=>ctx,getBoundingClientRect:()=>({left:0,top:0,width:310,height:155}),setPointerCapture(){},releasePointerCapture(){},addEventListener:(t,f)=>events[t]=f,fire:(t,id=1,x=10,y=20)=>events[t]?.({pointerId:id,clientX:x,clientY:y,button:0})};
 }});
 h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');
 return Object.assign(h,{canvas:()=>canvas,draw:()=>{canvas.fire('pointerdown');canvas.fire('pointermove',1,30,40);canvas.fire('pointerup');}});
}
test('S01-U strokes survive hint answer audio and route re-entry',()=>{
 const h=canvasHarness();h.draw();const expected=JSON.stringify(h.canvas().segments);
 for(const action of ['hint','show-answer','play-audio','stop-audio']){h.click('data-action',action);assert.equal(JSON.stringify(h.canvas().segments),expected,action);}
 h.click('data-route','home');h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');assert.equal(JSON.stringify(h.canvas().segments),expected);
});
test('S01-U owner drawings are isolated and restored; old canvas events stay stale',()=>{
 const h=canvasHarness();h.draw();const old=h.canvas(),expected=JSON.stringify(old.segments);old.fire('pointerdown');
 h.click('data-demo-owner','demo-b');h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');assert.equal(h.canvas().segments.length,0);
 old.fire('pointermove',1,90,90);old.fire('pointerdown');old.fire('pointermove');assert.equal(h.canvas().segments.length,0);
 h.click('data-demo-owner','demo-a');h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');assert.equal(JSON.stringify(h.canvas().segments),expected);
});
test('S01-U clear and retry invalidate active strokes and keep typed alternative boundaries',()=>{
 const h=canvasHarness();h.draw();h.input('mode-input','typed');const old=h.canvas();old.fire('pointerdown');h.click('data-action','clear-canvas');old.fire('pointermove');
 h.click('data-action','hint');assert.equal(h.canvas().segments.length,0);assert.match(h.screen.innerHTML,/value="typed"/);
 h.draw();h.click('data-action','retry-mode');assert.equal(h.canvas().segments.length,0);assert.match(h.screen.innerHTML,/id="mode-input"[^>]*value=""/);
 h.click('data-route','home');const before=h.run('JSON.stringify(state)');h.click('data-action','clear-canvas');h.click('data-action','show-answer');assert.equal(h.run('JSON.stringify(state)'),before);
});
test('S01-U pointer ownership cancel and replaced canvas reject stale moves',()=>{
 const h=canvasHarness();const c=h.canvas();c.fire('pointerdown',1);c.fire('pointermove',2);assert.equal(c.segments.length,0);
 c.fire('pointercancel',2);c.fire('pointermove',1);assert.equal(c.segments.length,1);
 c.fire('pointercancel',1);c.fire('pointermove',1);assert.equal(c.segments.length,1);
 c.fire('pointerdown',1);h.click('data-action','hint');const before=JSON.stringify(h.canvas().segments);c.fire('pointermove',1,80,90);h.click('data-action','hint');assert.equal(JSON.stringify(h.canvas().segments),before);
});

test('S01-U drawing lifetime copy and clear versus retry are explicit',()=>{
 const h=canvasHarness();assert.match(h.screen.innerHTML,/เส้นที่เขียน.*เฉพาะหน้านี้.*โหลดใหม่.*หาย/);
 assert.match(h.screen.innerHTML,/ลบแล้วเขียนใหม่.*ไม่ลบ.*พิมพ์/);
});
test('S01-U mode switch, lost capture and invalid coordinates cannot extend the wrong stroke',()=>{
 const h=canvasHarness(),c=h.canvas();c.fire('pointerdown',1);c.fire('pointerdown',2);c.fire('pointermove',2);assert.equal(c.segments.length,0);
 c.fire('pointermove',1,NaN,20);assert.equal(c.segments.length,0);c.fire('pointermove',1,30,40);assert.equal(c.segments.length,1);
 c.fire('lostpointercapture',1);c.fire('pointermove',1,50,60);assert.equal(c.segments.length,1);
 const expected=JSON.stringify(c.segments);h.click('data-mode','dictation');h.click('data-action','begin-mode');h.input('mode-input','heard');h.click('data-action','hint');
 c.fire('pointerdown');c.fire('pointermove');h.click('data-action','clear-canvas');h.click('data-action','show-answer');assert.match(h.screen.innerHTML,/value="heard"/);
 h.click('data-action','retry-mode');h.click('data-mode','handwriting-scratchpad');h.click('data-action','begin-mode');assert.equal(JSON.stringify(h.canvas().segments),expected);
});

test('S01-U shared show-answer still works for story but not absent controls',()=>{
 const h=setup();h.click('data-mode','associative-reading');h.click('data-action','show-answer');assert.equal(h.run('state.feedback'),null);
 h.click('data-action','begin-mode');h.click('data-action','show-answer');assert.ok(h.run('state.feedback?.good'));
 h.click('data-mode','typed-recall');h.click('data-action','begin-mode');h.click('data-action','show-answer');assert.equal(h.run('state.feedback'),null);
});

// S01-V rendered-choice boundary double. Re-render detaches old controls.
function choiceHarness(){
 const listeners={},nodes={'workflow-map':{},'mode-map':{},'lab-map':{}};let html='',buttons=[];
 const screen={scrollTop:0,contains:n=>buttons.includes(n),querySelector:()=>null,querySelectorAll:()=>[]};nodes['app-screen']=screen;
 Object.defineProperty(screen,'innerHTML',{get:()=>html,set:value=>{buttons.forEach(b=>b.isConnected=false);html=value;buttons=(value.match(/<button\b[^>]*>/g)||[]).map(tag=>{const attrs=Object.fromEntries([...tag.matchAll(/(data-[\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2].replaceAll('&quot;','"').replaceAll('&amp;','&').replaceAll('&lt;','<').replaceAll('&gt;','>')]));return {isConnected:true,dataset:Object.fromEntries(Object.entries(attrs).map(([k,v])=>[k.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),v]))};});buttons.forEach(b=>{b.closest=s=>Object.hasOwn(b.dataset,s.slice(6,-1).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()))?b:null;});}});
 const document={getElementById:id=>nodes[id]||null,querySelectorAll:()=>[],addEventListener:(t,f)=>listeners[t]=f};
 const context=vm.createContext({document,location:{search:''},URLSearchParams,console,window:{addEventListener(){}},setTimeout:fn=>fn()});
 vm.runInContext(fs.readFileSync(path.join(__dirname,'lexiquest-full-ux.js'),'utf8'),context);
 const run=code=>vm.runInContext(code,context);
 return {run,screen,choices:attr=>buttons.filter(b=>Object.hasOwn(b.dataset,attr)),fire:b=>listeners.click({target:b}),click:(attr,value)=>listeners.click({target:{closest:s=>s===`[${attr}]`?{dataset:{[attr.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]:value},closest:()=>null}:null}})};
}
function unchangedChoice(h,attribute,value){const before=h.run('JSON.stringify(state)');h.click(attribute,value);assert.equal(h.run('JSON.stringify(state)'),before);}
test('S01-V mode choices reject intro, absent kind, route exit and owner-switch answers',()=>{
 const h=setup();h.click('data-mode','meaning-quiz');unchangedChoice(h,'data-answer','หนังสือ');
 h.click('data-action','begin-mode');h.click('data-route','home');unchangedChoice(h,'data-answer','หนังสือ');
 h.click('data-mode','typed-recall');h.click('data-action','begin-mode');unchangedChoice(h,'data-answer','book');
 h.click('data-demo-owner','demo-b');unchangedChoice(h,'data-answer','หนังสือ');
});
test('S01-V every rendered mode choice remains valid and unknown values are ignored',()=>{
 const h=choiceHarness();const ids=JSON.parse(h.run('JSON.stringify(modes.filter(m=>["choice","reading"].includes(m.kind)).map(m=>m.id))'));
 for(const id of ids){h.click('data-mode',id);h.click('data-action','begin-mode');const values=h.choices('answer').map(b=>b.dataset.answer);assert.ok(values.length);
  for(const value of values){h.fire(h.choices('answer').find(b=>b.dataset.answer===value));assert.equal(h.run('state.feedback.good'),value===h.run('currentMode().answer'));}
  for(const value of ['', 'not-an-option', ' '+values[0]])unchangedChoice(h,'data-answer',value);
 }
});
test('S01-V lab choices reject writing, route exit, owner switch and invalid values',()=>{
 const h=setup();h.click('data-lab-module','picture');unchangedChoice(h,'data-lab-answer','unknown');
 h.click('data-lab-module','writing');unchangedChoice(h,'data-lab-answer','right');h.click('data-route','home');unchangedChoice(h,'data-lab-answer','right');
 h.click('data-demo-owner','demo-b');unchangedChoice(h,'data-lab-answer','wrong');
});
test('S01-V all rendered lab choices and both mission steps retain feedback',()=>{
 const h=choiceHarness();for(const id of ['picture','listening','sentence','evidence','mission']){
  h.click('data-lab-module',id);const values=h.choices('labAnswer').map(b=>b.dataset.labAnswer);assert.ok(values.length);
  for(const value of values){h.fire(h.choices('labAnswer').find(b=>b.dataset.labAnswer===value));assert.equal(h.run('state.labFeedback'),value);}
 }
 h.fire(h.choices('labAnswer').find(b=>b.dataset.labAnswer==='right'));h.click('data-action','lab-next-step');assert.equal(h.run('state.labMissionStep'),1);
 for(const value of h.choices('labAnswer').map(b=>b.dataset.labAnswer)){h.fire(h.choices('labAnswer').find(b=>b.dataset.labAnswer===value));assert.equal(h.run('state.labFeedback'),value);}
});
test('S01-V exam choices reject absent task, writing, invalid values, exit and owner switch',()=>{
 const h=setup();h.click('data-route','exam');unchangedChoice(h,'data-exam-answer','right');h.click('data-exam-task','reading');unchangedChoice(h,'data-exam-answer','unknown');
 h.click('data-exam-task','writing');unchangedChoice(h,'data-exam-answer','right');h.click('data-route','home');unchangedChoice(h,'data-exam-answer','wrong');
 h.click('data-demo-owner','demo-b');unchangedChoice(h,'data-exam-answer','right');
});
test('S01-V every rendered exam choice works across both tracks and all choice tasks',()=>{
 const h=choiceHarness();h.click('data-route','exam');for(const track of ['toeic','ielts']){h.click('data-exam-track',track);for(const task of ['reading','listening','reasoning']){
  h.click('data-exam-task',task);const values=h.choices('examAnswer').map(b=>b.dataset.examAnswer);assert.ok(values.length);
  for(const value of values){h.fire(h.choices('examAnswer').find(b=>b.dataset.examAnswer===value));assert.equal(h.run('state.examFeedback'),value);}
 }}
});
for(const kind of ['mode','lab','exam'])test(`S01-V detached ${kind} choices cannot answer replacement tasks or owners`,()=>{
 const h=choiceHarness(),attr={mode:'answer',lab:'labAnswer',exam:'examAnswer'}[kind];
 const open=()=>{if(kind==='mode'){h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');}else if(kind==='lab')h.click('data-lab-module','mission');else{h.click('data-route','exam');h.click('data-exam-task','reading');}};
 open();const old=h.choices(attr)[0];assert.ok(old);
 if(kind==='mode'){h.click('data-mode','cefr-reading');h.click('data-action','begin-mode');}else if(kind==='lab'){h.click('data-lab-answer','right');h.click('data-action','lab-next-step');}else{h.click('data-exam-track','ielts');h.click('data-exam-task','reading');}
 let before=h.run('JSON.stringify(state)');h.fire(old);assert.equal(h.run('JSON.stringify(state)'),before);
 const oldOwner=h.choices(attr)[0];h.click('data-demo-owner','demo-b');open();before=h.run('JSON.stringify(state)');h.fire(oldOwner);assert.equal(h.run('JSON.stringify(state)'),before);
});

// S01-W support controls: active route, activity and progression prerequisites.
test('S01-W mission progression requires current first-step correct feedback',()=>{
 const h=setup();h.click('data-lab-module','mission');unchangedChoice(h,'data-action','lab-next-step');
 h.click('data-lab-answer','wrong');unchangedChoice(h,'data-action','lab-next-step');
 h.click('data-lab-answer','right');assert.match(h.screen.innerHTML,/data-action="lab-next-step"/);h.click('data-action','lab-next-step');assert.equal(h.run('state.labMissionStep'),1);
 h.click('data-lab-answer','right');unchangedChoice(h,'data-action','lab-next-step');
 h.click('data-lab-module','picture');unchangedChoice(h,'data-action','lab-next-step');h.click('data-route','home');unchangedChoice(h,'data-action','lab-next-step');
});
test('S01-W lab retry is limited to wrong feedback on the current choice activity',()=>{
 const h=setup();h.click('data-lab-module','picture');h.click('data-lab-answer','right');unchangedChoice(h,'data-action','lab-retry');
 h.click('data-lab-answer','wrong');assert.match(h.screen.innerHTML,/data-action="lab-retry"/);h.click('data-action','lab-retry');assert.equal(h.run('state.labFeedback'),null);
 h.click('data-lab-answer','wrong');h.click('data-route','home');unchangedChoice(h,'data-action','lab-retry');
 h.click('data-lab-module','writing');h.input('lab-writing','my draft');h.click('data-action','lab-review-writing');unchangedChoice(h,'data-action','lab-retry');assert.equal(h.run('state.labDraft'),'my draft');
});
test('S01-W lab transcript is limited to rendered audio activities and mission follow-up',()=>{
 const h=setup();for(const id of ['sentence','evidence','writing','mission']){h.click('data-lab-module',id);unchangedChoice(h,'data-action','lab-show-transcript');}
 for(const id of ['picture','listening','mission']){h.click('data-lab-module',id);if(id==='mission'){h.click('data-lab-answer','right');h.click('data-action','lab-next-step');}
  assert.match(h.screen.innerHTML,/data-action="lab-show-transcript"/);h.click('data-action','lab-show-transcript');assert.equal(h.run('state.labTranscript'),true);h.click('data-action','lab-show-transcript');assert.equal(h.run('state.labTranscript'),false);
 }
 h.click('data-route','home');unchangedChoice(h,'data-action','lab-show-transcript');h.click('data-demo-owner','demo-b');unchangedChoice(h,'data-action','lab-show-transcript');
});
test('S01-W exam transcript is limited to listening on the active exam route',()=>{
 const h=setup();h.click('data-route','exam');unchangedChoice(h,'data-action','show-exam-transcript');
 for(const track of ['toeic','ielts']){h.click('data-exam-track',track);for(const task of ['reading','writing','reasoning']){h.click('data-exam-task',task);unchangedChoice(h,'data-action','show-exam-transcript');}
  h.click('data-exam-task','listening');h.click('data-action','show-exam-transcript');assert.equal(h.run('state.examTranscript'),true);h.click('data-action','show-exam-transcript');assert.equal(h.run('state.examTranscript'),false);
 }
 h.click('data-route','home');unchangedChoice(h,'data-action','show-exam-transcript');h.click('data-demo-owner','demo-b');unchangedChoice(h,'data-action','show-exam-transcript');
});
test('S01-W exited lab and exam audio controls cannot restart playback',()=>{
 for(const kind of ['lab','exam']){const h=setup({audio:true});if(kind==='lab')h.click('data-lab-module','listening');else{h.click('data-route','exam');h.click('data-exam-task','listening');}
  const action=kind==='lab'?'lab-play-audio':'play-exam-audio';assert.ok(h.screen.innerHTML.includes('data-action="'+action+'"'));h.click('data-action',action);assert.equal(h.spoken.length,1);
  h.click('data-route','home');const audio=h.run('JSON.stringify(draftAudio)');unchangedChoice(h,'data-action',action);assert.equal(h.spoken.length,1);assert.equal(h.run('JSON.stringify(draftAudio)'),audio);
 }
});
test('S01-W begin and hint apply only at their displayed mode stages',()=>{
 const h=setup();unchangedChoice(h,'data-action','begin-mode');unchangedChoice(h,'data-action','hint');h.click('data-mode','meaning-quiz');unchangedChoice(h,'data-action','hint');
 h.click('data-action','begin-mode');h.click('data-action','hint');assert.match(h.run('state.feedback.text'),/คำใบ้/);unchangedChoice(h,'data-action','begin-mode');
 h.click('data-route','home');unchangedChoice(h,'data-action','hint');
});
test('S01-W flashcard rating requires a revealed card and preserves both self-ratings',()=>{
 const h=setup();h.click('data-mode','flashcard');unchangedChoice(h,'data-action','flip-card');h.click('data-action','begin-mode');
 for(const action of ['card-hard','card-easy'])unchangedChoice(h,'data-action',action);
 h.click('data-action','flip-card');assert.equal(h.run('state.cardFlipped'),true);
 for(const action of ['card-hard','card-easy']){h.click('data-action',action);assert.ok(h.run('state.feedback.good'));}
 h.click('data-mode','meaning-quiz');h.click('data-action','begin-mode');for(const action of ['flip-card','card-hard','card-easy'])unchangedChoice(h,'data-action',action);
});
test('S01-W microphone explanation is limited to the active speech sample',()=>{
 const h=setup();h.click('data-mode','speaking');unchangedChoice(h,'data-action','speech-demo');h.click('data-action','begin-mode');h.click('data-action','speech-demo');assert.match(h.run('state.feedback.text'),/ไม่เปิดไมค์/);
 h.click('data-mode','typed-recall');h.click('data-action','begin-mode');unchangedChoice(h,'data-action','speech-demo');h.click('data-route','home');unchangedChoice(h,'data-action','speech-demo');
});
test('S01-W detached support actions do not alter replacement tasks',()=>{
 const h=choiceHarness();h.click('data-lab-module','listening');const old=h.choices('action').find(b=>b.dataset.action==='lab-show-transcript');assert.ok(old);
 h.click('data-lab-module','picture');const before=h.run('JSON.stringify(state)');h.fire(old);assert.equal(h.run('JSON.stringify(state)'),before);
});

// S01-X selectors: actual screen controls, global lab map, stale nodes and drafts.
for(const [attribute,valid] of [['data-exam-track','ielts'],['data-exam-task','reading']]){
 test(`S01-X ${attribute} ignores unknown values before mutating state or cancelling audio`,()=>{
  const h=setup({audio:true});h.click('data-route','exam');h.click('data-exam-task','listening');h.click('data-action','play-exam-audio');
  for(const value of ['', 'unknown', '__proto__', 'constructor', ' '+valid]){
   const count=h.cancelled(),audio=h.run('JSON.stringify(draftAudio)');unchangedChoice(h,attribute,value);assert.equal(h.cancelled(),count);assert.equal(h.run('JSON.stringify(draftAudio)'),audio);
  }
 });
 test(`S01-X ${attribute} ignores events outside exam and after owner switch`,()=>{
  const h=setup();h.click('data-route','exam');h.click('data-exam-task','writing');h.input('exam-writing','keep original');
  h.click('data-route','home');unchangedChoice(h,attribute,valid);h.click('data-demo-owner','demo-b');unchangedChoice(h,attribute,valid);
 });
 test(`S01-X detached ${attribute} cannot change replacement exam or owner`,()=>{
  const h=choiceHarness();h.click('data-route','exam');const key=attribute==='data-exam-track'?'examTrack':'examTask';const old=h.choices(key)[0];assert.ok(old);
  h.click('data-exam-track','ielts');h.click('data-exam-task','writing');let before=h.run('JSON.stringify(state)');h.fire(old);assert.equal(h.run('JSON.stringify(state)'),before);
  const priorOwner=h.choices(key)[0];h.click('data-demo-owner','demo-b');h.click('data-route','exam');before=h.run('JSON.stringify(state)');h.fire(priorOwner);assert.equal(h.run('JSON.stringify(state)'),before);
 });
}
test('S01-X lab selectors ignore unknown module ids without stopping audio',()=>{
 const h=setup({audio:true});h.click('data-lab-module','listening');h.click('data-action','lab-play-audio');
 for(const value of ['', 'unknown', '__proto__', 'constructor', ' writing']){const count=h.cancelled();unchangedChoice(h,'data-lab-module',value);assert.equal(h.cancelled(),count);}
});
test('S01-X detached lab cards cannot reopen after module, route or owner changes',()=>{
 for(const transition of ['module','route','owner']){
  const h=choiceHarness();h.click('data-route','skill-lab');const old=h.choices('labModule')[0];assert.ok(old);
  if(transition==='module')h.click('data-lab-module','writing');else if(transition==='route')h.click('data-route','home');else h.click('data-demo-owner','demo-b');
  const before=h.run('JSON.stringify(state)');h.fire(old);assert.equal(h.run('JSON.stringify(state)'),before);
 }
});
test('S01-X every rendered exam track and task selects its content and preserves per-track drafts',()=>{
 const h=choiceHarness();h.click('data-route','exam');const tracks=h.choices('examTrack').map(b=>b.dataset.examTrack);assert.deepEqual(tracks,['toeic','ielts']);
 for(const track of tracks){h.fire(h.choices('examTrack').find(b=>b.dataset.examTrack===track));assert.equal(h.run('state.examTrack'),track);
  const tasks=h.choices('examTask').map(b=>b.dataset.examTask);assert.deepEqual(tasks,['listening','reading','writing','reasoning']);
  for(const task of tasks){h.fire(h.choices('examTask').find(b=>b.dataset.examTask===task));assert.equal(h.run('state.examTask'),task);assert.ok(h.screen.innerHTML.includes(h.run('escapeHtml(examExamples[state.examTrack][state.examTask].question)')));}
 }
 const d=setup({audio:true});d.click('data-route','exam');
 for(const track of tracks){d.click('data-exam-track',track);d.click('data-exam-task','writing');d.input('exam-writing','  '+track+' <draft>  ');}
 for(const track of tracks){d.click('data-exam-track',track);d.click('data-exam-task','listening');d.click('data-action','play-exam-audio');const count=d.cancelled();d.click('data-exam-task','writing');assert.ok(d.cancelled()>count);assert.equal(d.run('state.examDraft'),'  '+track+' <draft>  ');}
});
test('S01-X lab cards and persistent review map remain valid navigation entry points',()=>{
 const h=choiceHarness();h.click('data-route','skill-lab');const ids=h.choices('labModule').map(b=>b.dataset.labModule);assert.equal(ids.length,6);
 for(const id of ids){h.click('data-route','skill-lab');h.fire(h.choices('labModule').find(b=>b.dataset.labModule===id));assert.equal(h.run('state.route'),'lab-activity');assert.equal(h.run('state.labModule'),id);}
 // The prototype renders lab-map outside app-screen: its buttons stay connected across routes.
 const mapHtml=h.run('document.getElementById("lab-map").innerHTML');
 for(const id of ids){assert.ok(mapHtml.includes('data-lab-module="'+id+'"'));for(const route of ['home','exam','words']){h.click('data-route',route);const b={isConnected:true,dataset:{labModule:id},closest:s=>s==='[data-lab-module]'?b:null};h.fire(b);assert.equal(h.run('state.labModule'),id);assert.equal(h.run('state.route'),'lab-activity');}}
});
test('S01-X disabled rendered selectors cannot mutate current state',()=>{
 for(const [route,key] of [['exam','examTrack'],['exam','examTask'],['skill-lab','labModule']]){
  const h=choiceHarness();h.click('data-route',route);const b=h.choices(key).at(-1);assert.ok(b);b.disabled=true;const before=h.run('JSON.stringify(state)');h.fire(b);assert.equal(h.run('JSON.stringify(state)'),before);
 }
});

// S01-Y: focus continuation after real rendered actions disappear.
// Models markup replacement and focus calls only; no browser or keyboard automation.
function continuationFocusHarness({audio=false}={}){
 const h=setup({audio}),calls=[];let html=h.screen.innerHTML,buttons=[];
 const oldContains=h.screen.contains;
 const parse=value=>{buttons.forEach(b=>b.isConnected=false);html=value;buttons=(value.match(/<button\b[^>]*>/g)||[]).map(tag=>({
  isConnected:true,disabled:/\sdisabled(?:\s|>)/.test(tag),
  getAttribute:a=>tag.match(new RegExp(a+'="([^"]*)"'))?.[1]??null,
  focus:options=>{calls.push({target:tag,preventScroll:options?.preventScroll});}
 }));};
 Object.defineProperty(h.screen,'innerHTML',{get:()=>html,set:parse});parse(html);
 h.screen.contains=n=>buttons.includes(n)||oldContains(n);
 h.screen.querySelectorAll=selector=>{const attribute=selector.match(/^\[([^\]]+)\]$/)?.[1];return buttons.filter(b=>attribute&&b.getAttribute(attribute)!==null);};
 h.screen.querySelector=selector=>selector==='h1'&&/<h1[^>]*tabindex="-1"/.test(html)?{focus:options=>calls.push({target:'heading',preventScroll:options?.preventScroll})}:null;
 const activate=action=>{const b=buttons.find(b=>b.getAttribute('data-action')===action);assert.ok(b,'rendered action '+action);assert.equal(b.disabled,false);h.document.activeElement=b;calls.length=0;h.click('data-action',action);return b;};
 return {...h,calls,activate};
}
function assertHeadingContinuation(h){assert.deepEqual(h.calls.at(-1),{target:'heading',preventScroll:true});assert.equal(h.screen.scrollTop,133);}
test('S01-Y starting every displayed mode puts focus on the exercise heading without scroll reset',()=>{
 const h=continuationFocusHarness();const ids=JSON.parse(h.run('JSON.stringify(modes.map(m=>m.id))'));
 for(const id of ids){h.click('data-mode',id);h.screen.scrollTop=133;const old=h.activate('begin-mode');assert.equal(old.isConnected,false);assertHeadingContinuation(h);assert.equal(h.run('state.modeStep'),'question');}
});
test('S01-Y mission next and wrong-answer retry keep a focus destination as their buttons disappear',()=>{
 const h=continuationFocusHarness();h.click('data-lab-module','mission');h.click('data-lab-answer','right');h.screen.scrollTop=133;h.activate('lab-next-step');assertHeadingContinuation(h);assert.equal(h.run('state.labMissionStep'),1);
 h.click('data-lab-answer','wrong');h.activate('lab-retry');assertHeadingContinuation(h);assert.equal(h.run('state.labFeedback'),null);
});
for(const kind of ['exam','lab'])test(`S01-Y ${kind} discard open, cancel and confirm keep focus and obey draft intent`,()=>{
 const h=continuationFocusHarness();if(kind==='exam'){h.click('data-route','exam');h.click('data-exam-task','writing');}else h.click('data-lab-module','writing');
 h.input(kind+'-writing','  my retained draft  ');h.screen.scrollTop=133;h.activate(kind+'-discard');assertHeadingContinuation(h);
 h.activate('cancel-draft-discard');assertHeadingContinuation(h);assert.equal(h.run('state.'+kind+'Draft'),'  my retained draft  ');
 h.activate(kind+'-discard');h.activate('confirm-draft-discard');assertHeadingContinuation(h);assert.equal(h.run('state.'+kind+'Draft'),'');
});
test('S01-Y stopping audio or natural completion while stop is focused restores a heading destination',()=>{
 for(const end of ['stop','complete','error']){const h=continuationFocusHarness({audio:true});h.click('data-lab-module','listening');h.click('data-action','lab-play-audio');h.screen.scrollTop=133;
  if(end==='stop')h.activate('stop-audio');else{const b=h.screen.querySelectorAll('[data-action]').find(b=>b.getAttribute('data-action')==='stop-audio');assert.ok(b);h.document.activeElement=b;h.calls.length=0;if(end==='complete')h.spoken.at(-1).onend();else h.spoken.at(-1).onerror();}
  assertHeadingContinuation(h);assert.doesNotMatch(h.screen.innerHTML,/data-action="stop-audio"/);
 }
});
test('S01-Y matching retry keeps a focus destination and clears only that attempt',()=>{
 const h=continuationFocusHarness();h.click('data-mode','matching');h.click('data-action','begin-mode');h.click('data-pair','book');h.click('data-pair','window');h.screen.scrollTop=133;h.activate('retry-mode');assertHeadingContinuation(h);assert.equal(h.run('state.feedback'),null);assert.equal(h.run('state.selectedPair.length'),0);
});
test('S01-Y retained controls preserve their own focus; renders without screen focus do not steal it',()=>{
 const h=continuationFocusHarness();h.click('data-lab-module','listening');h.screen.scrollTop=133;h.activate('lab-show-transcript');assert.match(h.calls.at(-1).target,/data-action="lab-show-transcript"/);assert.equal(h.calls.at(-1).preventScroll,true);
 h.document.activeElement={getAttribute:()=>null};h.calls.length=0;h.run('render()');assert.equal(h.calls.length,0);
 h.document.activeElement={getAttribute:a=>a==='data-action'?'outside-action':null};h.run('render()');assert.equal(h.calls.length,0);
});

test('S01-Y camera permission, failure and retry steps keep a keyboard destination in the sample flow',()=>{
 const h=continuationFocusHarness();h.click('data-route','camera');h.screen.scrollTop=133;
 for(const stage of ['permission','denied','permission','ready','failed','ready','result','ready']){
  const b=h.screen.querySelectorAll('[data-camera-stage]').find(b=>b.getAttribute('data-camera-stage')===stage);assert.ok(b,'displayed camera step '+stage);h.document.activeElement=b;h.calls.length=0;
  h.click('data-camera-stage',stage);assertHeadingContinuation(h);assert.equal(h.run('state.cameraStage'),stage);
 }
});
