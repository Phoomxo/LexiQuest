'use strict';

// UX draft only: all values are local examples. No app storage, provider, or network call.
const workflows = [
  {id:'W01',label:'เริ่มใช้และบัญชี',route:'account'},
  {id:'W02',label:'เมนูและการตั้งค่า',route:'settings'},
  {id:'W03',label:'คำศัพท์ของฉัน',route:'words'},
  {id:'W04',label:'ผู้ช่วยสอน AI',route:'ai'},
  {id:'W05',label:'แบบฝึกและเกม',route:'practice'},
  {id:'W06',label:'อ่านตามระดับ',route:'reading'},
  {id:'W07',label:'ทบทวนและฝึกจุดที่พลาด',route:'review'},
  {id:'W08',label:'วางแผนการเรียน',route:'plan'},
  {id:'W09',label:'ความก้าวหน้าและประวัติ',route:'progress'},
  {id:'W10',label:'ภารกิจ รางวัล และร้านค้า',route:'rewards'},
  {id:'W11',label:'ฟังและพูด',route:'speech'},
  {id:'W12',label:'เรียนคำจากภาพ',route:'camera'},
  {id:'W13',label:'ส่งออกข้อมูล',route:'export'},
  {id:'W14',label:'เรียนเมื่อไม่มีเน็ตและใช้หลายเครื่อง',route:'offline'}
];

const modes = [
  {id:'associative-reading',label:'อ่านเรื่องช่วยจำ',group:'จำคำศัพท์',hint:'อ่านเรื่องสั้นที่ช่วยเชื่อมคำกับภาพในใจ',kind:'story',sample:'The blue book is on the table.',answer:'หนังสือสีน้ำเงินอยู่บนโต๊ะ'},
  {id:'meaning-quiz',label:'เลือกความหมาย',group:'จำคำศัพท์',hint:'เห็นคำอังกฤษแล้วเลือกคำแปลไทย',kind:'choice',sample:'book',answer:'หนังสือ',options:['หน้าต่าง','หนังสือ','ประตู'],direction:'อังกฤษ → ไทย'},
  {id:'typed-recall',label:'นึกคำแล้วพิมพ์',group:'จำคำศัพท์',hint:'เห็นความหมายไทยแล้วพิมพ์คำอังกฤษ',kind:'input',sample:'หนังสือ',answer:'book',direction:'ไทย → อังกฤษ'},
  {id:'definition-quiz',label:'อ่านคำอธิบายแล้วเลือก',group:'จำคำศัพท์',hint:'อ่านคำอธิบายสั้น ๆ แล้วเลือกคำที่ตรงกัน',kind:'choice',sample:'สิ่งที่เราเปิดอ่าน มีหลายหน้า',answer:'book',options:['window','book','door']},
  {id:'cloze',label:'เติมคำในประโยค',group:'อ่านและเขียน',hint:'อ่านประโยคแล้วเลือกคำที่หายไป',kind:'choice',sample:'I read a ___ every night.',answer:'book',options:['door','book','water']},
  {id:'matching',label:'จับคู่คำกับความหมาย',group:'จำคำศัพท์',hint:'แตะคำอังกฤษแล้วจับคู่กับความหมายไทย',kind:'matching',sample:'book ↔ หนังสือ',answer:'book|หนังสือ',direction:'เลือกได้ทั้งสองทิศทาง'},
  {id:'flashcard',label:'บัตรคำทบทวน',group:'ทบทวน',hint:'ลองนึกความหมายก่อนพลิกดูคำตอบ',kind:'flashcard',sample:'book',answer:'หนังสือ'},
  {id:'handwriting-scratchpad',label:'เขียนคำด้วยตัวเอง',group:'อ่านและเขียน',hint:'ลองเขียนหรือพิมพ์คำโดยไม่คิดคะแนน',kind:'handwriting',sample:'หนังสือ',answer:'book'},
  {id:'dictation',label:'ฟังแล้วพิมพ์',group:'ฟังและพูด',hint:'ฟังเสียงคำ แล้วพิมพ์สิ่งที่ได้ยิน',kind:'dictation',sample:'book',answer:'book'},
  {id:'speaking',label:'พูดคำ',group:'ฟังและพูด',hint:'ลองพูดคำตามตัวอย่าง',kind:'speech',sample:'book',answer:'book'},
  {id:'shadowing',label:'ฟังแล้วพูดตาม',group:'ฟังและพูด',hint:'ฟังประโยคแล้วพูดตามจังหวะ',kind:'speech',sample:'I read a book.',answer:'I read a book.'},
  {id:'cefr-reading',label:'อ่านตามระดับ',group:'อ่านและเขียน',hint:'อ่านเรื่องที่เหมาะกับระดับ แล้วตอบคำถาม',kind:'reading',sample:'Mali has a small book. She reads it every day.',answer:'หนังสือ',options:['หนังสือ','กระเป๋า','หน้าต่าง']},
  {id:'sentence-scramble',label:'เรียงประโยค',group:'อ่านและเขียน',hint:'แตะคำตามลำดับให้เป็นประโยค',kind:'scramble',sample:'I read a book.',answer:'I read a book.',tokens:['book.','a','read','I']},
  {id:'word-scramble',label:'เรียงตัวอักษร',group:'จำคำศัพท์',hint:'แตะตัวอักษรเรียงเป็นคำ',kind:'scramble',sample:'หนังสือ',answer:'book',tokens:['o','k','b','o']}
];

// Original, illustrative prompts only. These are not ETS or IELTS questions.
const examExamples = {
  toeic:{
    listening:{passage:'The meeting begins at nine in the morning.',question:'การประชุมเริ่มกี่โมง?',options:[['right','9 โมงเช้า'],['wrong','9 โมงเย็น']],explanation:'เสียงตัวอย่างพูดว่า nine in the morning'},
    reading:{passage:'Office notice: The library closes at 6 p.m. on Friday.',question:'ห้องสมุดปิดกี่โมงในวันศุกร์?',options:[['wrong','9 โมงเช้า'],['right','6 โมงเย็น']],explanation:'ข้อความระบุว่า closes at 6 p.m. on Friday'},
    reasoning:{passage:'Order pickup is available after 3 p.m. on Friday.',question:'ถ้ามาถึงเวลา 2:30 p.m. จะรับของได้หรือยัง?',options:[['right','ยังไม่ได้'],['wrong','รับได้แล้ว']],explanation:'after 3 p.m. หมายถึงต้องรอให้เลยบ่าย 3 โมงก่อน'},
    writing:{passage:'เพื่อนร่วมงานถามว่า “Can we meet on Friday morning?”',question:'ลองเขียนตอบเป็นภาษาอังกฤษ 1–2 ประโยค โดยบอกเวลาที่คุณสะดวก'}
  },
  ielts:{
    listening:{passage:'The museum opens at ten on Saturday morning.',question:'พิพิธภัณฑ์เปิดกี่โมงในวันเสาร์?',options:[['wrong','8 โมงเช้า'],['right','10 โมงเช้า']],explanation:'เสียงตัวอย่างพูดว่า opens at ten on Saturday morning'},
    reading:{passage:'A small city garden opened in April. Volunteers water the plants every morning.',question:'ใครรดน้ำต้นไม้ตอนเช้า?',options:[['right','อาสาสมัคร'],['wrong','นักเรียน']],explanation:'ประโยคที่สองระบุว่า Volunteers water the plants'},
    reasoning:{passage:'The garden is open every day except Monday. Mali plans to visit on Monday.',question:'มะลิจะเข้าชมสวนในวันจันทร์ได้หรือไม่?',options:[['right','ไม่ได้'],['wrong','ได้']],explanation:'except Monday หมายถึงสวนไม่เปิดวันจันทร์'},
    writing:{passage:'หัวข้อสมมติ: Some people prefer to study alone. Others prefer to study with friends.',question:'ลองเขียนความเห็นสั้น ๆ เป็นภาษาอังกฤษ พร้อมเหตุผลหนึ่งข้อ'}
  }
};

// Six proposed worksheet-derived activity families. The samples are original UX copy.
const labModules = [
  {id:'picture',title:'ภาพ–เสียง–คำ',detail:'ฟังคำสั้นแล้วแตะภาพ เหมาะกับการเริ่มต้น',icon:'◉',tone:'green'},
  {id:'listening',title:'ฟังแล้วหา',detail:'ฟังประโยคแล้วจับข้อมูลสำคัญ',icon:'♫',tone:''},
  {id:'sentence',title:'ประโยคใช้จริง',detail:'เติมคำและเข้าใจว่าทำไมจึงใช้รูปนี้',icon:'✎',tone:'gold'},
  {id:'evidence',title:'นักสืบข้อความ',detail:'อ่านแล้วแยกสิ่งที่บอกกับสิ่งที่ไม่บอก',icon:'▤',tone:''},
  {id:'writing',title:'ห้องเขียน',detail:'ร่างข้อความสั้นและตรวจงานของตัวเอง',icon:'✧',tone:'gold'},
  {id:'mission',title:'ภารกิจใช้จริง',detail:'เลือกคำพูด ฟังคำตอบ แล้วทำขั้นต่อไป',icon:'★',tone:'pink'}
];
const labExamples = {
  picture:{spoken:'apple',question:'ฟังเสียง แล้วแตะภาพที่ตรงกัน',options:[['wrong','📕','หนังสือ'],['right','🍎','แอปเปิล'],['wrong','🚪','ประตู']],explanation:'apple หมายถึง แอปเปิล'},
  listening:{spoken:'The bus leaves at eight.',question:'รถออกกี่โมง?',options:[['right','8 โมง'],['wrong','9 โมง']],explanation:'เสียงบอกว่า leaves at eight = ออกเวลา 8 โมง'},
  sentence:{passage:'She ___ to school every day.',question:'เลือกคำที่เติมในช่องว่าง',options:[['wrong','go'],['right','goes']],explanation:'ประธาน She ใช้กริยาเติม s: She goes to school.'},
  evidence:{passage:'The cafe opens at 8 a.m. It is closed on Sunday.',question:'ข้อความบอกว่าคาเฟ่ขายอาหารเช้าราคา 50 บาท',options:[['wrong','จริง'],['wrong','ไม่จริง'],['right','ไม่มีข้อมูล']],explanation:'ข้อความไม่ได้บอกราคาอาหารเช้า จึงเลือก ไม่มีข้อมูล'},
  writing:{passage:'คุณจะไปพบเพื่อนช้ากว่าเวลานัด 10 นาที',question:'เขียนข้อความภาษาอังกฤษสั้น ๆ บอกเพื่อนว่าจะมาสาย'},
  mission:{passage:'คุณอยู่ร้านอาหารและอยากได้น้ำหนึ่งแก้ว',question:'สั่งน้ำอย่างสุภาพว่าอย่างไร?',options:[['right','I’d like a glass of water, please.'],['wrong','The bus is blue.']],explanation:'ประโยค I’d like... เป็นการขอสิ่งที่ต้องการอย่างสุภาพ'}
};

// Pinned navigation subset; assessment forms stay in the reviewer packet.
const pilotContent = {
  "revision": "s01-content-r1",
  "status": "DRAFT_UNREVIEWED",
  "tracks": [
    {
      "id": "phonics",
      "title": "เริ่มอ่านคำสั้น",
      "steps": [
        {
          "id": "welcome",
          "title": "ดูตัวอย่างก่อน",
          "thai": "วันนี้ลองฟังเสียงและผสมคำสั้น ๆ ยังไม่ต้องตอบ คุณเลือกฟังเรื่องแทนได้เสมอ",
          "english": "",
          "media": []
        },
        {
          "id": "sounds",
          "title": "รูปตัวเขียนกับเสียง",
          "thai": "แตะเพื่อฟังเสียงของรูปตัวเขียนทีละตัว เสียงนี้ต่างจากชื่อตัวอักษร",
          "english": "m · a · s · t · p · i · n",
          "media": [
            "ph-sounds-r1",
            "ph-letter-names-r1"
          ]
        },
        {
          "id": "blend",
          "title": "ดูวิธีผสมคำ",
          "thai": "ดู m–a–t แล้วฟังเสียงต่อกันเป็น mat จากนั้นดูตัวอย่าง s–i–t ภาพและความหมายเปิดหลังสาธิต",
          "english": "mat = เสื่อ · sit = นั่ง",
          "media": [
            "ph-model-r1",
            "ph-pictures-r1"
          ]
        },
        {
          "id": "segment",
          "title": "ลองแยกและเรียงเสียง",
          "thai": "ฟังคำตัวอย่าง แล้วแตะรูปตัวเขียนตามลำดับ ไม่ต้องลาก มีคำใบ้ให้เปิดดูได้",
          "english": "mat / sit",
          "media": [
            "ph-model-r1"
          ]
        },
        {
          "id": "try",
          "title": "ลองคำใหม่เมื่อสื่อพร้อม",
          "thai": "ตอนตรวจการอ่าน ผู้ตรวจจะแสดงคำใหม่ทีละคำโดยยังไม่เปิดเสียงหรือภาพ หากไม่สะดวกอ่านออกเสียง ให้ข้ามได้และบันทึกว่ายังไม่ได้ตรวจ",
          "english": "",
          "media": [
            "ph-review-r1"
          ]
        },
        {
          "id": "finish",
          "title": "เลือกทางต่อได้",
          "thai": "ต้นแบบนี้ยังไม่ได้ตรวจการอ่านออกเสียง เลือกฝึกอีกครั้ง ฟังเรื่อง หรือพักได้ ไม่มีคะแนนปลดล็อกบท",
          "english": "",
          "media": []
        }
      ]
    },
    {
      "id": "story",
      "title": "ฟังหรืออ่านเรื่องในร้าน",
      "steps": [
        {
          "id": "welcome",
          "title": "ฟังหรืออ่านเรื่องสั้น",
          "thai": "เรื่องนี้เกี่ยวกับการขอน้ำในร้าน ฟังหรืออ่านต่อได้โดยไม่ต้องตอบทุกช่วง เปิดคำไทยช่วยได้",
          "english": "",
          "media": []
        },
        {
          "id": "story",
          "title": "น้ำหนึ่งแก้ว",
          "thai": "มะลิไปที่ร้าน เธอขอน้ำ พนักงานถามว่าเย็นไหม มะลิบอกว่าเย็น พนักงานยื่นน้ำให้ มะลิขอบคุณ",
          "english": "Mali is at a cafe. ‘Water, please,’ she says. ‘Cold water?’ asks the server. ‘Yes, please.’ The server gives Mali water. ‘Thank you,’ she says.",
          "media": [
            "story-audio-r1",
            "story-picture-r1"
          ]
        },
        {
          "id": "meaning",
          "title": "ดูเหตุการณ์พร้อมคำช่วย",
          "thai": "มะลิขออะไร? พนักงานถามอะไร? เปิดคำไทยหรือกลับไปฟังซ้ำได้ นี่คือการฝึกพร้อมตัวช่วย ยังไม่ใช่ข้อใหม่สำหรับตรวจ",
          "english": "Water, please. → Cold water? → Yes, please. → Thank you.",
          "media": []
        },
        {
          "id": "try",
          "title": "เรื่องใหม่เมื่อพร้อมทดลอง",
          "thai": "ผู้ดำเนินกิจกรรมจะใช้เรื่องใหม่และถามสารสำคัญ ตอบไทยได้ ไม่ตัดสินจากการเขียนอังกฤษ ฟังกับอ่านต้องบันทึกแยกกัน",
          "english": "",
          "media": [
            "story-assessment-audio-r1"
          ]
        },
        {
          "id": "finish",
          "title": "เลือกสิ่งที่อยากทำต่อ",
          "thai": "การดูเรื่องจบไม่ใช่ผลยืนยันความเข้าใจ เลือกอ่านคำสั้น ดูเรื่องอีกครั้ง หรือพักได้",
          "english": "",
          "media": []
        }
      ]
    }
  ]
};

const state = {
  pilotTrack:null,pilotProgress:{},pilotLastTrack:null,
  route:'home',backStack:[],scenario:'new',modeId:'meaning-quiz',modeStep:'intro',
  ai:'off',showModes:false,words:[{word:'book',meaning:'หนังสือ',category:'คำทั่วไป'},{word:'learn',meaning:'เรียนรู้',category:'คำทั่วไป'},{word:'window',meaning:'หน้าต่าง',category:'คำทั่วไป'}],
  category:'ทั้งหมด',wordQuery:'',feedback:null,selectedTokens:[],selectedPair:[],cardFlipped:false,modeDrafts:{},canvasDrafts:{},
  selectedPack:'คำที่ใช้ทุกวัน',selectedLevel:'เริ่มต้น',goal:5,notice:'',fontScale:1,
  photoUrl:null,cameraStage:'start',permission:'unknown',sync:'idle',answerLocked:false,
  examTrack:'toeic',examTask:null,examFeedback:null,examDraft:'',examDrafts:{},pendingDraftDiscard:null,examTranscript:false,
  labModule:null,labFeedback:null,labTranscript:false,labDraft:'',labMissionStep:0,
  formErrors:{},addWordDraft:{word:'',meaning:''},editWordDraft:null,importRows:[],
  exportWords:true,exportHistory:true,importCandidates:[],importDraft:'',importPreviewSource:null,pendingDelete:false,highContrast:false
};
const emptyDemoOwner=JSON.stringify(state);
const demoOwnerStates=new Map();
let demoOwnerId='demo-a';
const draftAudio={generation:0,status:'idle'};

function stopDraftAudio(){
  draftAudio.generation++;
  try {window.speechSynthesis?.cancel();draftAudio.status='idle';}
  catch {draftAudio.status='error';}
}
function cancelCamera(){
  if(state.photoUrl)URL.revokeObjectURL(state.photoUrl);
  state.photoUrl=null;state.cameraStage='start';
}
function switchDemoOwner(id){
  if(!['demo-a','demo-b'].includes(id)||id===demoOwnerId)return;
  stopDraftAudio();
  cancelCamera();
  invalidateImport();
  state.pendingDelete=false;state.pendingDraftDiscard=null;
  demoOwnerStates.set(demoOwnerId,JSON.stringify(state));
  const preferences={fontScale:state.fontScale,highContrast:state.highContrast};
  for(const key of Object.keys(state))delete state[key];
  Object.assign(state,JSON.parse(demoOwnerStates.get(id)||emptyDemoOwner),preferences);
  demoOwnerId=id;
  state.pendingDelete=false;state.pendingDraftDiscard=null;state.notice='เปลี่ยนผู้ใช้ตัวอย่างแล้ว ข้อมูลแยกกันเฉพาะหน้านี้ ไม่ใช่บัญชีจริง';
  navigate('home',{replace:true});
}
const appScreen=document.getElementById('app-screen');
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const csvCell=value=>{const raw=String(value??'');const safe=/^[=+\-@]/.test(raw)?"'"+raw:raw;return '"'+safe.replaceAll('"','""')+'"';};
const topbar=()=>'<div class="topline"><div class="brand">Lexi<em>Quest</em></div><div class="avatar" aria-label="โปรไฟล์ตัวอย่าง">L</div></div>';
const back=()=>'<button class="back" data-action="back">← ย้อนกลับ</button>';
const intro=(kicker,title,subtitle,secondary=false)=>`${secondary?back():topbar()}<div class="kicker">${escapeHtml(kicker)}</div><h1 class="title" tabindex="-1">${escapeHtml(title)}</h1><p class="sub">${escapeHtml(subtitle)}</p>`;
const actionCard=(icon,title,description,route,tone='')=>`<button class="action-card" data-route="${route}"><span class="action-icon ${tone}">${icon}</span><span class="action-copy"><strong>${escapeHtml(title)}</strong><small>${escapeHtml(description)}</small></span><span class="chev">›</span></button>`;
const itemRow=(title,detail,route,badge='')=>`<button class="item-row" data-route="${route}"><span><strong>${escapeHtml(title)}</strong><small>${escapeHtml(detail)}</small></span>${badge?`<span class="smalltag">${escapeHtml(badge)}</span>`:'<span class="chev">›</span>'}</button>`;
const button=(label,route,secondary=false)=>`<button class="button ${secondary?'secondary':''} full" data-route="${route}">${escapeHtml(label)}</button>`;
const sampleNote='<p class="sample-note">ข้อมูลบนหน้านี้เป็นตัวอย่างสำหรับดูดีไซน์ ไม่ใช่ผลการเรียนหรือข้อมูลบัญชีจริง</p>';

const readingExamples={
  'เริ่มต้น':{title:'หนังสือของมะลิ',revision:'reading-draft-r1-a',sample:'Mali has a small book. She reads it every day.',thai:'มะลิมีหนังสือเล่มเล็ก เธออ่านทุกวัน',answer:'หนังสือ',options:['หนังสือ','กระเป๋า','หน้าต่าง'],question:'มะลิอ่านอะไรทุกวัน?'},
  'กำลังฝึก':{title:'ไปห้องสมุดหลังเลิกงาน',revision:'reading-draft-r1-b',sample:'Nok finishes work at five. She visits the library before going home because she needs a book for her class.',thai:'นกเลิกงานห้าโมง เธอไปห้องสมุดก่อนกลับบ้าน เพราะต้องการหนังสือสำหรับชั้นเรียน',answer:'ต้องการหนังสือเรียน',options:['ต้องการหนังสือเรียน','ไปซื้ออาหาร','ไปทำงาน'],question:'ทำไมนกไปห้องสมุดก่อนกลับบ้าน?'},
  'อ่านคล่อง':{title:'เปลี่ยนแผนเมื่อห้องสมุดปิด',revision:'reading-draft-r1-c',sample:'Although the library normally closes at six, a notice says it will close an hour earlier today. Nok finishes work at five, so she decides to borrow the book tomorrow instead.',thai:'ปกติห้องสมุดปิดหกโมง แต่วันนี้ปิดเร็วขึ้นหนึ่งชั่วโมง นกเลิกงานห้าโมง จึงเลือกยืมหนังสือวันพรุ่งนี้',answer:'ห้องสมุดปิดเวลาเลิกงาน',options:['ห้องสมุดปิดเวลาเลิกงาน','นกไม่ต้องการหนังสือแล้ว','ห้องสมุดเปิดถึงสองทุ่ม'],question:'ทำไมนกเลื่อนไปยืมวันพรุ่งนี้?'}
};

function renderPilotEntry(){
  const last=pilotContent.tracks.find(track=>track.id===state.pilotLastTrack);
  return `<div class="hero"><span class="tag">ต้นแบบทางเริ่มเรียน</span><h3>เลือกทางที่อยากลอง</h3><p>ดูตัวอย่างก่อน ไม่ต้องสอบหรือเปิดไมค์</p>${last?`<button data-action="pilot-resume">กลับต่อ: ${escapeHtml(last.title)}</button>`:''}</div>`+
    pilotContent.tracks.map(track=>`<button class="action-card" data-pilot-track="${track.id}"><span class="action-copy"><strong>${escapeHtml(track.title)}</strong><small>${track.id==='phonics'?'ดูรูปตัวเขียน เสียง และวิธีผสมคำ':'อ่านเรื่องได้ทันที ไม่ต้องผ่านบทอ่านคำ'}</small></span><span aria-hidden="true">›</span></button>`).join('')+
    '<p class="sample-note">เนื้อหาร่างยังไม่ผ่านผู้ตรวจ ใช้ดูทางเดินเท่านั้น ตำแหน่งและร่างอยู่เฉพาะหน้านี้ ปิดหรือโหลดหน้าใหม่จะเริ่มใหม่</p>';
}
function openPilot(trackId){
  if(!pilotContent.tracks.some(track=>track.id===trackId))return;
  state.pilotTrack=trackId;state.pilotLastTrack=trackId;
  const previous=state.pilotProgress[trackId];
  if(!previous||previous.revision!==pilotContent.revision){
    state.pilotProgress[trackId]={step:0,help:false,thai:false,outcomes:{},revision:pilotContent.revision};
    if(previous)state.notice='เนื้อหาเปลี่ยนรุ่น เริ่มดูตัวอย่างรุ่นใหม่ตั้งแต่ต้น คำช่วยเดิมไม่ใช้กับรุ่นนี้';
  }
  navigate('pilot');
}
function renderPilot(){
  const track=pilotContent.tracks.find(item=>item.id===state.pilotTrack);
  if(!track)return renderPilotEntry();
  const p=state.pilotProgress[track.id],step=track.steps[p.step];
  const last=p.step===track.steps.length-1;
  const other=pilotContent.tracks.find(item=>item.id!==track.id);
  return intro(track.title,step.title,'ต้นแบบการใช้ปุ่ม · เนื้อหายังไม่ผ่านผู้ตรวจ',true)+
    `<p class="smalltag">ขั้น ${p.step+1} จาก ${track.steps.length} · ${pilotContent.revision}</p><div class="card">${track.id==='story'&&step.id==='story'
      ? `<p class="hint">อ่านเรื่อง${p.thai?'พร้อมคำไทยช่วย':''} · ไม่ใช่ผลการฟัง เสียงที่ผ่านตรวจยังไม่พร้อม</p><p lang="en">${escapeHtml(step.english)}</p><button class="disclosure" data-action="pilot-thai" aria-expanded="${!!p.thai}" aria-controls="pilot-thai-text">${p.thai?'ซ่อนคำไทยช่วย':'เปิดคำไทยช่วย'}</button><div id="pilot-thai-text" ${p.thai?'':'hidden'}>${p.thai?escapeHtml(step.thai):''}</div>`
      : `<p>${escapeHtml(step.thai)}</p>${step.english?`<p lang="en">${escapeHtml(step.english)}</p>`:''}`}</div>`+
    (step.media.length?'<div class="info" role="status">สื่อยังไม่พร้อมสำหรับการทดลองเรียน</div><button class="button secondary full" data-action="pilot-audio">ตรวจความพร้อมเสียง</button>':'')+
    `<button class="disclosure" data-action="pilot-help" aria-expanded="${p.help}">ขอคำช่วย</button>`+
    (p.help?'<div class="info" role="status">คำช่วย: อ่านคำสั่งช้า ๆ เลือกข้าม พัก หรือเปลี่ยนทางได้ทุกเมื่อ ไม่มีคะแนนในต้นแบบนี้ หากต้องใช้เสียงให้รอสื่อที่ผ่านตรวจ</div>':'')+
    (!last?'<div class="button-row"><button class="button" data-action="pilot-next">ดูขั้นถัดไป</button><button class="button secondary" data-action="pilot-skip">ข้ามขั้นนี้</button></div>':'<p role="status">ยังไม่ได้ตรวจผลการอ่านหรือความเข้าใจ การดูจบไม่สร้างคะแนนหรือ mastery</p><button class="button full" data-action="pilot-restart">ดูตัวอย่างตั้งแต่ต้นอีกครั้ง</button>')+
    `<button class="button secondary full" data-pilot-track="${other.id}">เปลี่ยนไป${escapeHtml(other.title)}</button><button class="button secondary full" data-action="pilot-pause">พักไว้ แล้วกลับหน้าวันนี้</button>`+
    '<p class="sample-note">ไม่บันทึกคะแนน XP เสียง หรือข้อมูลผู้เรียนจริง ปิดหรือโหลดหน้าใหม่จะล้างตำแหน่งต้นแบบ</p>';
}

function renderHome(){
  const returning=state.scenario==='returning';
  const offline=state.scenario==='offline';
  return intro('เรียนภาษาอังกฤษแบบค่อยเป็นค่อยไป',returning?'กลับมาเรียนต่อกัน':'วันนี้ เริ่มตรงนี้เลย',returning?'งานที่ค้างอยู่รอคุณอยู่':'ไม่ต้องรู้จักชื่อโหมดฝึกก็เริ่มได้')+
    (offline?'<div class="info banner">ไม่มีอินเทอร์เน็ตก็ฝึกจากคำและบทเรียนที่อยู่ในเครื่องได้</div>':'')+
    renderPilotEntry()+
    '<div class="section-title">อยากทำอะไรต่อ?</div>'+
    actionCard('◷','ทบทวนวันนี้','ฝึกคำที่เคยเรียนให้จำแม่นขึ้น','review','gold')+
    actionCard('✦','คำศัพท์ของฉัน','ค้นหา เพิ่มคำ หรือเลือกคำมาฝึก','words','green')+
    actionCard('▤','เลือกบทเรียน','หาหัวข้อที่สนใจและระดับที่เหมาะ','packs')+
    actionCard('✧','ถามผู้ช่วยเมื่อสงสัย','คุยกับผู้ช่วยใน LexiQuest เมื่ออยากได้คำอธิบาย','ai')+
    '<p class="hint">เริ่มได้โดยไม่ต้องสมัครบัญชีหรือเปิดผู้ช่วย AI</p>';
}

function renderPractice(){
  let html=intro('เลือกจากสิ่งที่อยากทำ','วันนี้อยากฝึกอะไร?','เลือกเป้าหมายก่อน แล้วค่อยเลือกวิธีฝึก');
  html+='<div class="section-title">เลือกตามเป้าหมาย</div>';
  html+=actionCard('◈','เริ่มต้นง่าย ๆ','ฝึกคำสั้น ๆ ด้วยการเลือกและจับคู่','practice-memory');
  html+=actionCard('▤','ใช้ภาษาในชีวิตจริง','อ่าน เขียน และฝึกจากเรื่องใกล้ตัว','practice-reading','gold');
  html+=actionCard('♫','ฟังและพูด','ฟังเสียง พูดคำ และพูดตาม','speech','green');
  html+=actionCard('✚','เล่นเพื่อฝึก','เกมสั้น ๆ จากคำศัพท์ที่เรียน','games','pink');
  html+=actionCard('✎','ลองฝึกหลายแบบ','ภาพ เสียง ประโยค และสถานการณ์ใกล้ตัว','skill-lab','green');
  html+='<div class="section-title">มีเป้าหมายสอบ?</div>';
  html+=actionCard('▣','ซ้อมสอบแบบสั้น','เลือกแนว TOEIC หรือ IELTS แล้วลองโจทย์ตัวอย่าง','exam','gold');
  html+=`<button class="disclosure" data-action="toggle-modes" aria-expanded="${state.showModes}">${state.showModes?'ซ่อนวิธีฝึกทั้งหมด':'ดูวิธีฝึกทั้งหมด 14 แบบ'} ${state.showModes?'⌃':'⌄'}</button>`;
  if(state.showModes){ for(const group of [...new Set(modes.map(mode=>mode.group))]) {html+=`<div class="group-heading">${group}</div>`;for(const mode of modes.filter(item=>item.group===group))html+=`<button class="item-row" data-mode="${mode.id}"><span><strong>${mode.label}</strong><small>${mode.hint}</small></span><span class="chev">›</span></button>`;} }
  html+='<p class="hint">แบบฝึกแต่ละแบบจะบอกวิธีทำเป็นภาษาไทยก่อนเริ่ม</p>';
  return html;
}

function renderPracticeGroup(group){
  const reading=group==='practice-reading';
  const chosen=reading?modes.filter(mode=>mode.group==='อ่านและเขียน'):modes.filter(mode=>mode.group==='จำคำศัพท์'||mode.group==='ทบทวน');
  return intro('เลือกวิธีฝึก',reading?'อ่านและเขียน':'จำคำศัพท์','เลือกแบบที่อยากลอง เริ่มจากแบบง่ายได้',true)+
    (reading?actionCard('▤','เลือกบทอ่านตามระดับ','มีคำแปลช่วยและคำถามท้ายเรื่อง','reading'):'')+
    chosen.map(mode=>`<button class="item-row" data-mode="${mode.id}"><span><strong>${mode.label}</strong><small>${mode.hint}</small></span><span class="chev">›</span></button>`).join('')+button('กลับไปดูทุกวิธีฝึก','practice',true);
}

function renderSkillLab(){
  const cards=items=>items.map(module=>`<button class="action-card" data-lab-module="${module.id}"><span class="action-icon ${module.tone}">${module.icon}</span><span class="action-copy"><strong>${module.title}</strong><small>${module.detail}</small></span><span class="chev">›</span></button>`).join('');
  return intro('แบบฝึกที่เลือกตามความพร้อม','ลองฝึกหลายแบบ','เลือกสิ่งที่อยากลอง ไม่ต้องทำทุกแบบ',true)+
    '<div class="info">แต่ละแบบใช้โจทย์ตัวอย่างสั้น ๆ จากแนวใบงานและสถานการณ์จริง เลือกแบบอื่นได้ทุกเมื่อ</div>'+
    '<div class="section-title">เริ่มจากภาพและเสียง</div>'+cards(labModules.slice(0,2))+
    '<div class="section-title">ลองใช้ภาษาในชีวิตจริง</div>'+cards(labModules.slice(2))+
    actionCard('▣','มีเป้าหมายสอบ?','ลองชุดสั้นแนว TOEIC หรือ IELTS','exam','gold')+
    '<p class="sample-note">เลือกจากเป้าหมายและความพร้อม ไม่ต้องระบุอายุหรือเพศเพื่อเริ่มฝึก</p>';
}

function renderLabActivity(){
  const module=labModules.find(item=>item.id===state.labModule)||labModules[0];
  const missionFollowUp=module.id==='mission'&&state.labMissionStep===1;
  const example=missionFollowUp?{spoken:'It is twenty baht.',question:'ฟังราคาแล้วเลือกจำนวนเงิน',options:[['right','20 บาท'],['wrong','30 บาท']],explanation:'twenty baht หมายถึง 20 บาท'}:labExamples[module.id];
  const audio=['picture','listening'].includes(module.id)||missionFollowUp;
  let html=intro('ฝึกทีละข้อ',module.title,module.detail,true)+
    `<div class="smalltag">${module.id==='mission'?`ขั้นที่ ${state.labMissionStep+1} จาก 2`:'โจทย์ตัวอย่าง 1 ข้อ'}</div>`;
  if(audio){
    html+='<div class="card"><h3>ฟังเสียงตัวอย่าง</h3><p>กดฟังซ้ำได้ ถ้าไม่มีเสียงให้อ่านคำแทน</p><div class="button-row"><button class="button" data-action="lab-play-audio">▶ ฟัง</button><button class="button secondary" data-action="lab-show-transcript">อ่านคำแทน</button></div></div>';
    if(state.labTranscript)html+=`<div class="info">${escapeHtml(example.spoken)} · เมื่ออ่านแทนเสียงจะไม่ถือว่าทดสอบทักษะฟัง</div>`;
  }else html+=`<div class="card"><h3>${module.id==='writing'?'สถานการณ์':'อ่านข้อความ'}</h3><p>${escapeHtml(example.passage)}</p></div>`;
  html+=`<div class="question"><small>${module.id==='evidence'?'จริง / ไม่จริง / ไม่มีข้อมูล':'ลองตอบด้วยตัวเอง'}</small><strong class="lab-question-text">${escapeHtml(example.question)}</strong></div>`;
  if(module.id==='writing'){
    html+='<details class="card"><summary>ต้องเขียนอะไรบ้าง?</summary><p>บอกเพื่อนว่าเกิดอะไรขึ้น ระบุเวลา และใช้คำสุภาพ</p></details>'+
      `<p class="hint">ร่างเก็บระหว่างเปลี่ยนหน้าในต้นแบบนี้เท่านั้น ปิดหรือโหลดหน้าใหม่จะล้างร่าง</p><label class="label" for="lab-writing">คำตอบของคุณ</label><textarea id="lab-writing" class="input" rows="4" placeholder="ลองเขียน 1–2 ประโยค">${escapeHtml(state.labDraft)}</textarea><button class="button full" data-action="lab-review-writing">ตรวจงานของฉัน</button>`;
    html+=draftDiscardControls('lab');
    if(state.labFeedback)html+='<div class="feedback" role="status">ตรวจงานของฉัน: บอกว่าจะช้ากี่นาทีหรือยัง? ผู้รับเข้าใจเวลาหรือไม่? อ่านแล้วสุภาพไหม? ร่างนี้ไม่ให้คะแนนงานเขียน</div>';
  }else{
    const picture=module.id==='picture';
    html+=`<div class="${picture?'lab-picture-options':''}">${example.options.map(([value,label,accessible])=>`<button class="choice" data-lab-answer="${value}" ${accessible?`aria-label="${escapeHtml(accessible)}"`:''}>${escapeHtml(label)}</button>`).join('')}</div>`;
    if(state.labFeedback)html+=`<div class="feedback ${state.labFeedback==='right'?'':'bad'}" role="status">${state.labFeedback==='right'?'ตรงแล้ว!':'ยังไม่ตรง ลองอีกครั้ง'} · ${escapeHtml(example.explanation)}</div>`;
    if(missionFollowUp&&state.labFeedback==='right')html+='<div class="success">ทำภารกิจตัวอย่างครบแล้ว คุณเป็นคนเลือกและตอบเอง</div>';
    if(module.id==='mission'&&state.labMissionStep===0&&state.labFeedback==='right')html+='<button class="button full" data-action="lab-next-step">ต่อไป: ฟังราคา</button>';
    if(state.labFeedback==='wrong')html+='<button class="button secondary full" data-action="lab-retry">ลองใหม่</button>';
  }
  return html+button('เลือกแบบฝึกอื่น','skill-lab',true)+
    '<p class="sample-note">กิจกรรมนี้เป็นร่าง UX ไม่บันทึกคำตอบ คะแนน XP หรือประวัติการเรียน</p>';
}

function examDraftKey(){return JSON.stringify([state.examTrack,state.examTask]);}
function storeExamDraft(value){state.examDraft=value;state.examDrafts[examDraftKey()]=value;}
function draftDiscardControls(kind){
  const pending=state.pendingDraftDiscard;
  return pending?.kind===kind
    ? '<div class="warning" role="group" aria-label="ยืนยันลบร่าง"><p>ลบร่างนี้ใช่ไหม? ลบแล้วกู้คืนไม่ได้ ร่างอื่นยังอยู่</p><button class="button secondary" data-action="cancel-draft-discard">เก็บร่างไว้</button><button class="button" data-action="confirm-draft-discard">ยืนยันลบร่างนี้</button></div>'
    : `<button class="button secondary" data-action="${kind}-discard">ลบร่างนี้</button>`;
}
function renderExam(){
  const toeic=state.examTrack==='toeic';
  let html=intro('เลือกเมื่อมีเป้าหมายสอบ','ซ้อมสอบแบบสั้น','ลองรูปแบบโจทย์ก่อน แล้วค่อยฝึกเต็มชุดในอนาคต',true);
  html+='<div class="info">โจทย์ในร่างนี้แต่งขึ้นใหม่เพื่อแสดง UX ไม่ใช่ข้อสอบจริงหรือคะแนนทางการ</div>';
  html+=`<div class="segmented exam-tracks" role="group" aria-label="เลือกแนวข้อสอบ"><button data-exam-track="toeic" class="${toeic?'active':''}" aria-pressed="${toeic}">แนว TOEIC</button><button data-exam-track="ielts" class="${toeic?'':'active'}" aria-pressed="${!toeic}">แนว IELTS</button></div>`;
  html+=toeic?'<div class="card"><h3>แนว TOEIC</h3><p>ข้อสอบจริงมีชุดฟัง–อ่าน และชุดพูด–เขียนแยกกัน ตัวอย่างนี้ให้ลองโจทย์สั้น ๆ ก่อน</p></div>':'<div class="card"><h3>แนว IELTS Academic</h3><p>ข้อสอบจริงมีฟัง อ่าน เขียน และพูด ตัวอย่างนี้ให้ลองโจทย์สั้น ๆ ก่อน</p></div>';
  html+='<div class="section-title">อยากลองทักษะไหน?</div>';
  html+='<div class="exam-task-list"><button class="item-row" data-exam-task="listening"><span><strong>ฟังแล้วตอบ</strong><small>ฟังประโยคสั้นแล้วจับข้อมูลสำคัญ</small></span><span class="chev">›</span></button><button class="item-row" data-exam-task="reading"><span><strong>อ่านแล้วตอบ</strong><small>อ่านข้อความและหาคำตอบจากหลักฐาน</small></span><span class="chev">›</span></button><button class="item-row" data-exam-task="writing"><span><strong>เขียนตอบ</strong><small>ฝึกเรียบเรียงคำตอบของตัวเอง</small></span><span class="chev">›</span></button><button class="item-row" data-exam-task="reasoning"><span><strong>อ่านแล้วคิดจากข้อมูล</strong><small>ฝึกจับเงื่อนไขและอนุมานจากข้อความ</small></span><span class="chev">›</span></button></div>';
  html+='<p class="hint">อ่านแล้วคิดจากข้อมูลเป็นทักษะเสริม ไม่ใช่พาร์ตสอบทางการ</p>';
  if(!state.examTask)return html+'<p class="sample-note">เลือกทักษะเพื่อดูโจทย์ตัวอย่าง ไม่มีเวลา คะแนน หรือผลสอบจริง</p>';
  const example=examExamples[state.examTrack][state.examTask];
  if(state.examTask==='listening'){
    html+='<div class="card"><span class="smalltag">เสียงตัวอย่าง</span><h3>ฟังแล้วตอบ</h3><p>กดฟังได้หลายครั้ง เสียงอ่านจากเครื่องนี้ใช้ดูรูปแบบการฝึก ไม่ใช่ไฟล์เสียงข้อสอบจริง</p><div class="button-row"><button class="button" data-action="play-exam-audio">▶ ฟังเสียงตัวอย่าง</button><button class="button secondary" data-action="show-exam-transcript">อ่านบทพูดแทน</button></div></div>';
    if(state.examTranscript)html+=`<div class="info">บทพูด: ${escapeHtml(example.passage)} · เปิดเพื่อช่วยการเข้าถึง ตัวอย่างนี้ไม่คิดคะแนน</div>`;
  }else html+=`<div class="card"><span class="smalltag">โจทย์ตัวอย่างที่แต่งขึ้นใหม่</span><h3>${state.examTask==='writing'?'ลองเขียนคำตอบ':'อ่านข้อความก่อนตอบ'}</h3><p>${escapeHtml(example.passage)}</p></div>`;
  html+=`<div class="question"><small>คำถาม</small><strong class="exam-question-text">${escapeHtml(example.question)}</strong></div>`;
  if(state.examTask==='writing'){
    html+=`<label class="label" for="exam-writing">คำตอบภาษาอังกฤษของคุณ</label><textarea id="exam-writing" class="input" rows="4" placeholder="ลองเขียนที่นี่">${escapeHtml(state.examDraft)}</textarea><button class="button full" data-action="exam-writing-review">ตรวจงานเขียนด้วยตัวเอง</button>`;
    html+='<p class="hint">ร่างแยกตามแนวข้อสอบ งาน และผู้ใช้ตัวอย่าง เก็บเฉพาะหน้านี้ ปิดหรือโหลดหน้าใหม่จะล้างร่าง</p>'+draftDiscardControls('exam');
    if(state.examFeedback)html+='<div class="feedback" role="status">ลองตรวจว่าเขียนตรงคำถามหรือไม่ มีเหตุผลรองรับไหม และอ่านแล้วเข้าใจหรือเปล่า ร่างนี้ยังไม่ให้คะแนนงานเขียน</div>';
  }else{
    html+=example.options.map(([value,label])=>`<button class="choice" data-exam-answer="${value}">${escapeHtml(label)}</button>`).join('');
    if(state.examFeedback)html+=`<div class="feedback ${state.examFeedback==='right'?'':'bad'}" role="status">${state.examFeedback==='right'?(state.examTask==='listening'?'ตรงกับเสียงแล้ว':'ตรงกับข้อความแล้ว'):(state.examTask==='listening'?'ยังไม่ตรง ลองฟังอีกครั้ง':'ยังไม่ตรง ลองอ่านหลักฐานอีกครั้ง')} · ${escapeHtml(example.explanation)}</div>`;
  }
  return html+'<p class="sample-note">ตัวอย่างนี้ไม่บันทึกคะแนน ไม่ใช่การสอบเต็มรูปแบบ และไม่มีการประเมินจาก AI</p>';
}

function renderWords(){
  const cats=['ทั้งหมด','คำทั่วไป','คำของฉัน'];
  const filtered=state.words.filter(word=>(state.category==='ทั้งหมด'||word.category===state.category)&&`${word.word} ${word.meaning}`.toLowerCase().includes(state.wordQuery.toLowerCase()));
  return intro('เก็บคำที่อยากจำ','คำศัพท์ของฉัน','ค้นหา เพิ่มคำ แล้วกลับมาฝึกเมื่อพร้อม')+
    `<input id="word-search" class="input search" type="search" placeholder="ค้นหาคำหรือความหมาย" aria-label="ค้นหาคำศัพท์" value="${escapeHtml(state.wordQuery)}">`+
    `<div class="chip-row">${cats.map(cat=>`<button class="chip ${state.category===cat?'selected':''}" data-category="${cat}" aria-pressed="${state.category===cat}">${cat}</button>`).join('')}</div>`+
    `<div class="section-title">${filtered.length} คำที่พบ</div>`+
    (filtered.length?filtered.map(word=>`<button class="item-row" data-word="${escapeHtml(word.word)}"><span><strong>${escapeHtml(word.word)}</strong><small>${escapeHtml(word.meaning)}</small></span><span class="smalltag">${escapeHtml(word.category)}</span></button>`).join(''):'<div class="info">ยังไม่พบคำนี้ ลองค้นหาใหม่หรือเพิ่มคำของคุณ</div>')+
    '<div class="button-row"><button class="button" data-route="add-word">＋ เพิ่มคำ</button><button class="button secondary" data-route="import">นำเข้าคำ</button></div>'+
    actionCard('▤','จัดกลุ่มคำ','ดูคำที่บันทึกแยกตามหัวข้อ','categories')+
    actionCard('▣','เรียนคำจากภาพ','เลือกรูป แล้วตรวจคำก่อนเก็บ','camera','gold')+
    actionCard('◇','ฝึกคำของฉัน','เลือกวิธีฝึกจากคำที่มี','practice')+sampleNote;
}

function renderMe(){
  return intro('พื้นที่ของฉัน','ค่อย ๆ เก่งขึ้นทุกวัน','ดูสิ่งที่ทำแล้ว และจัดการแอปตามต้องการ')+
    (state.scenario==='returning'?`<div class="card"><div class="card-row"><span>เวลาเรียนสัปดาห์นี้</span><span class="smalltag">ตัวอย่าง</span></div><div class="stat">42 นาที</div><div class="bars"><div style="height:35%"></div><div style="height:62%"></div><div style="height:81%"></div><div style="height:44%"></div><div style="height:94%"></div><div style="height:27%"></div><div style="height:55%"></div></div><div class="days"><span>จ</span><span>อ</span><span>พ</span><span>พฤ</span><span>ศ</span><span>ส</span><span>อา</span></div></div>`:'<div class="info">ยังไม่มีผลการเรียน เริ่มฝึกครั้งแรกแล้วกลับมาดูความก้าวหน้าได้ที่นี่</div>')+
    actionCard('▥','ความก้าวหน้า','ดูคำที่จำได้และสิ่งที่ควรฝึกเพิ่ม','progress')+
    actionCard('◷','ประวัติการเรียน','ย้อนดูบทเรียนที่ทำไว้','history','gold')+
    actionCard('★','ภารกิจและรางวัล','ดูสิ่งที่ปลดล็อกด้วยการเรียน','rewards','green')+
    '<div class="section-title">เครื่องมือเพิ่มเติม</div>'+
    actionCard('▤','วางแผนการเรียน','เลือกหัวข้อและตั้งเป้าเล็ก ๆ','plan')+
    actionCard('✧','ผู้ช่วยใน LexiQuest','ถามเพิ่มเติมเมื่ออยากใช้','ai')+
    actionCard('◉','บัญชีของฉัน','เรียนต่อแบบไม่ล็อกอินหรือเชื่อมบัญชี','account')+
    actionCard('⬇','ส่งออกข้อมูล','เก็บสำเนาคำและประวัติ','export')+
    actionCard('◌','เรียนเมื่อไม่มีเน็ต','ดูบทเรียนในเครื่องและข้อมูลระหว่างเครื่อง','offline')+
    actionCard('⚙','ตั้งค่า','ขนาดตัวอักษร เสียง และการแสดงผล','settings')+sampleNote;
}

function renderMode(){
  const mode=currentMode();
  let html=intro('วิธีฝึก · '+mode.group,mode.label,mode.hint,true);
  if(mode.direction)html+=`<span class="smalltag">ตัวอย่าง ${escapeHtml(mode.direction)}</span>`;
  if(state.modeStep==='intro')return html+`<div class="card"><h3>ทำอย่างไร?</h3><p>${escapeHtml(mode.hint)} ถ้ายังไม่แน่ใจ สามารถดูคำใบ้แล้วลองใหม่ได้</p></div><div class="info">ร่างนี้ใช้คำตัวอย่างเพียงข้อเดียว ไม่คิดคะแนนหรือบันทึกความก้าวหน้า</div><div class="button-row"><button class="button" data-action="begin-mode">ลองโจทย์ตัวอย่าง</button><button class="button secondary" data-route="practice">เลือกแบบอื่น</button></div>`;
  html+='<div class="progress-track"><i></i></div>';
  if(mode.kind==='choice'||mode.kind==='reading'){
    if(mode.kind==='reading')html+=`<p class="lesson-copy"><span lang="en">${escapeHtml(mode.sample)}</span><br><em>${escapeHtml(mode.thai)}</em></p>`;
    html+=`<div class="question"><small>${escapeHtml(mode.kind==='reading'?mode.question:'เลือกคำตอบที่ถูกต้อง')}</small><strong>${escapeHtml(mode.kind==='reading'?'จากเรื่องที่อ่าน':mode.sample)}</strong></div>`;
    html+=(mode.options||[]).map(option=>`<button class="choice" data-answer="${escapeHtml(option)}">${escapeHtml(option)}</button>`).join('');
  } else if(mode.kind==='input'||mode.kind==='dictation'){
    html+=mode.kind==='dictation'?'<button class="button secondary" data-action="play-audio">▶ ฟังคำตัวอย่าง</button>':'';
    html+=`<div class="question"><small>${mode.kind==='dictation'?'ฟังแล้วพิมพ์คำที่ได้ยิน':'พิมพ์คำอังกฤษของ'}</small><strong>${mode.kind==='dictation'?'♫':escapeHtml(mode.sample)}</strong></div><label class="label" for="mode-input">คำตอบของคุณ</label><input id="mode-input" class="input" value="${escapeHtml(state.modeDrafts[mode.id]||'')}" autocomplete="off" placeholder="พิมพ์คำตอบ"><button class="button full" data-action="check-input">ตรวจคำตอบ</button>`;
  } else if(mode.kind==='matching'){
    html+='<div class="question"><small>เลือกคำอังกฤษ แล้วเลือกคำแปลไทย</small><strong>จับคู่กัน</strong></div><div class="tile-grid">'+['book','window','หนังสือ','หน้าต่าง'].map(value=>`<button class="${state.selectedPair.includes(value)?'picked':''}" data-pair="${value}" aria-pressed="${state.selectedPair.includes(value)}">${value}</button>`).join('')+'</div>';
  } else if(mode.kind==='flashcard'){
    html+=`<div class="question"><small>${state.cardFlipped?'ความหมายคือ':'ลองนึกความหมายของ'}</small><strong>${state.cardFlipped?escapeHtml(mode.answer):escapeHtml(mode.sample)}</strong></div><button class="button full" data-action="flip-card">${state.cardFlipped?'ดูคำอีกครั้ง':'พลิกดูคำตอบ'}</button><div class="button-row"><button class="button secondary" data-action="card-hard" ${state.cardFlipped?'':'disabled'}>ยังไม่แม่น</button><button class="button secondary" data-action="card-easy" ${state.cardFlipped?'':'disabled'}>จำได้แล้ว</button></div>`;
  } else if(mode.kind==='scramble'){
    html+=`<div class="question"><small>${mode.id==='word-scramble'?'เรียงเป็นคำอังกฤษของ':'เรียงให้เป็นประโยค'}</small><strong>${escapeHtml(mode.sample)}</strong></div><div class="info">คำตอบ: ${escapeHtml(state.selectedTokens.length?state.selectedTokens.map(index=>mode.tokens[index]).join(mode.id==='word-scramble'?'':' '):'แตะชิ้นส่วนด้านล่าง')}</div><div class="tile-grid">${mode.tokens.map((token,index)=>`<button data-token="${index}" ${state.selectedTokens.includes(index)?'disabled':''}>${escapeHtml(token)}</button>`).join('')}</div><div class="button-row"><button class="button secondary" data-action="clear-tokens">เริ่มเรียงใหม่</button><button class="button" data-action="check-tokens">ตรวจคำตอบ</button></div>`;
  } else if(mode.kind==='handwriting'){
    html+=`<div class="question"><small>ลองเขียนคำอังกฤษของ</small><strong>${escapeHtml(mode.sample)}</strong></div><canvas class="canvas" id="writing-canvas" width="310" height="155" aria-label="พื้นที่ฝึกเขียน"></canvas><div class="button-row"><button class="button secondary" data-action="clear-canvas">ลบแล้วเขียนใหม่</button><button class="button" data-action="show-answer">ดูตัวอย่างคำ</button></div><label class="label" for="mode-input">พิมพ์แทนการเขียน</label><input id="mode-input" class="input" value="${escapeHtml(state.modeDrafts[mode.id]||'')}" placeholder="พิมพ์คำที่ลองเขียน">`;
  } else if(mode.kind==='speech'){
    html+=`<div class="question"><small>ฟังตัวอย่าง แล้วลองพูดตาม</small><strong>${escapeHtml(mode.sample)}</strong></div><div class="button-row"><button class="button secondary" data-action="play-audio">▶ ฟังตัวอย่าง</button><button class="button" data-action="speech-demo">♩ ดูขั้นตอนใช้ไมค์</button></div><div class="info">ในแอปจริงจะขออนุญาตใช้ไมค์ก่อนฟังเสียงคุณ ร่างนี้ไม่บันทึกหรือตรวจเสียง</div>`;
  } else if(mode.kind==='story'){
    html+=`<div class="card"><h3>เรื่องช่วยจำ</h3><p>The blue book is on the table.<br>หนังสือสีน้ำเงินอยู่บนโต๊ะ</p></div><div class="question"><small>ภาพไหนช่วยให้นึกถึงคำว่า book?</small><strong>📖</strong></div><button class="button full" data-action="show-answer">ดูคำอธิบาย</button>`;
  }
  if(mode.kind==='handwriting')html+='<p class="hint">เส้นที่เขียนเก็บแยกตามแบบฝึกและผู้ใช้ตัวอย่างเฉพาะหน้านี้ ปิดหรือโหลดใหม่จะหาย · ลบแล้วเขียนใหม่ไม่ลบคำตอบที่พิมพ์ ส่วนลองอีกครั้งจะล้างทั้งเส้นและคำตอบของแบบฝึกนี้</p>';
  if(['input','dictation','handwriting'].includes(mode.kind))html+='<p class="hint">ร่างคำตอบที่พิมพ์เก็บแยกตามแบบฝึกและผู้ใช้ตัวอย่างเฉพาะหน้านี้ ปิดหรือโหลดใหม่จะหาย</p>';
  html+='<button class="disclosure" data-action="hint">ขอคำใบ้</button>';
  if(state.feedback)html+=`<div class="feedback ${state.feedback.good?'':'bad'}" role="status">${escapeHtml(state.feedback.text)}</div><button class="button full" data-action="retry-mode">ลองอีกครั้ง</button>`;
  html+='<p class="sample-note">ตัวอย่างนี้ไม่บันทึกคะแนน คำตอบจริงในแอปต้องมาจากผู้เรียนเท่านั้น</p>';
  return html;
}

function renderReview(){
  if(state.scenario!=='returning')return intro('ทบทวนทีละนิด','ยังไม่มีคำที่ถึงเวลา','เริ่มฝึกคำแรกก่อน แล้วแอปจะช่วยจำว่าควรกลับมาทบทวนเมื่อไร',true)+
    '<div class="info">ยังไม่มีประวัติการทบทวนสำหรับตัวอย่างผู้ใช้ใหม่</div>'+
    actionCard('◈','เริ่มฝึกคำศัพท์','เลือกความหมายจากคำที่ใช้บ่อย','mode:meaning-quiz')+
    actionCard('✦','ดูคำศัพท์ก่อน','เลือกคำที่อยากจำจากคลังของฉัน','words','green');
  return intro('ทบทวนทีละนิด','คำที่ถึงเวลาทบทวน','ลองนึกก่อนดูคำตอบ ไม่ต้องรีบ',true)+
    '<div class="card"><div class="card-row"><span>รอทบทวนวันนี้</span><span class="stat">6 คำ</span></div><p>เริ่มจากคำที่เคยตอบผิดหรือยังจำไม่แม่น</p></div>'+
    button('เริ่มทบทวนด้วยบัตรคำ','mode:flashcard')+
    '<div class="section-title">เลือกสิ่งที่อยากฝึกเพิ่ม</div>'+
    actionCard('♡','คำที่ยังสับสน','ดูว่าคำไหนควรกลับมาฝึก','weakness','pink')+
    actionCard('◈','จับคู่คำศัพท์','ทบทวนแบบเกมสั้น ๆ','mode:matching')+
    '<div class="info">ถ้ายังไม่มีคำที่ถึงกำหนดทบทวน แอปควรบอกตรง ๆ และเสนอฝึกคำอื่นแทน</div>'+sampleNote;
}

function renderWeakness(){
  if(state.scenario!=='returning')return intro('เลือกสิ่งที่อยากฝึก','ยังไม่มีข้อมูลจุดที่ควรฝึกเพิ่ม','เลือกฝึกได้โดยไม่ต้องรอผลการเรียน',true)+
    '<div class="info">ยังไม่มีหลักฐานการเรียน ไม่ได้หมายความว่าทำไม่ได้ เราจะไม่เดาจุดอ่อนจากการเปิดหน้าหรือตอบข้อจำลอง</div>'+
    actionCard('◈','ลองฝึกเลือกความหมาย','เลือกฝึกตามความสนใจ','mode:meaning-quiz')+
    actionCard('✦','ดูคำศัพท์ของฉัน','เลือกคำที่อยากลองฝึก','words','green');
  return intro('ดูตัวอย่างคำแนะนำ','ตัวอย่างจุดที่ควรฝึกเพิ่ม','ประวัติจำลองสำหรับดูหน้าตา ไม่ใช่ข้อสรุปเกี่ยวกับคุณ',true)+
    '<div class="card"><h3>ตัวอย่างจากประวัติจำลอง</h3><p>window · หน้าต่าง — ตัวอย่างการสับสนกับ door ไม่ใช่คำตอบของผู้ใช้จริง</p></div>'+
    actionCard('◈','ฝึกเลือกความหมาย','ลองข้อที่สั้นและง่ายก่อน','mode:meaning-quiz')+
    actionCard('▤','อ่านคำในประโยค','ดูว่าคำนี้ใช้ในบริบทไหน','mode:cloze','gold')+
    '<div class="info">คำแนะนำจริงต้องอิงประวัติของผู้ใช้คนปัจจุบัน หากไม่มีข้อมูลจะไม่เดาจุดอ่อนให้เอง</div>'+sampleNote;
}

function renderPlan(){
  return intro('เลือกเป้าหมายที่ทำไหว','แผนเรียนของฉัน','ตั้งเป้าสั้น ๆ แล้วปรับได้ทุกเมื่อ',true)+
    `<div class="card"><h3>อยากฝึกวันละกี่นาที?</h3><div class="chip-row">${[5,10,15].map(n=>`<button class="chip ${state.goal===n?'selected':''}" data-goal="${n}" aria-pressed="${state.goal===n}">${n} นาที</button>`).join('')}</div><p>แนะนำเริ่มที่ 5 นาที เมื่อคุ้นแล้วค่อยเพิ่ม</p></div>`+
    '<div class="section-title">เรียนเรื่องอะไรดี?</div>'+
    actionCard('▤',state.selectedPack,'ชุดคำที่เลือกไว้ในตัวอย่าง','packs')+
    actionCard('◷','คำที่ถึงเวลาทบทวน','ระบบช่วยเตือนเมื่อมีคำที่ควรทบทวน','review','gold')+
    `<button class="button full" data-action="save-plan">ใช้แผน ${state.goal} นาทีต่อวัน</button>`+
    '<p class="hint">แผนนี้เป็นคำแนะนำ ไม่บังคับให้ทำครบทุกวัน</p>';
}

function renderPacks(){
  return intro('เลือกหัวข้อที่สนใจ','บทเรียนและชุดคำ','ดูจำนวนคำและเนื้อหาก่อนเริ่มเรียน',true)+
    '<div class="chip-row"><button class="chip selected">ทั้งหมด</button><button class="chip" data-action="pack-filter">เริ่มต้น</button><button class="chip" data-action="pack-filter">ชีวิตประจำวัน</button></div>'+
    itemRow('คำที่ใช้ทุกวัน','10 คำ · สิ่งของรอบตัว','pack-detail','เริ่มต้น')+
    itemRow('ที่บ้านและโรงเรียน','12 คำ · คำใกล้ตัว','pack-detail','เริ่มต้น')+
    itemRow('อ่านเรื่องสั้น','บทอ่านตัวอย่างพร้อมคำแปลช่วย','reading','อ่าน')+
    '<div class="info">ระดับของชุดคำบอกความยากของเนื้อหา ไม่ใช่การประเมินระดับภาษาให้ผู้เรียน</div>';
}

function renderPackDetail(){
  return intro('รายละเอียดบทเรียน','คำที่ใช้ทุกวัน','ดูเนื้อหาก่อนตัดสินใจเริ่ม',true)+
    '<div class="card"><div class="card-row"><span>10 คำ · สิ่งของรอบตัว</span><span class="smalltag">เริ่มต้น</span></div><p>ตัวอย่าง: book หนังสือ · window หน้าต่าง · door ประตู</p></div>'+
    '<div class="section-title">ทำอะไรกับชุดคำนี้ได้?</div>'+
    actionCard('◈','ฝึกความหมาย','เรียนจากคำในชุดนี้','mode:meaning-quiz')+
    actionCard('▤','ดูคำทั้งหมด','เลือกคำไปเก็บในคลังของฉัน','words','green')+
    '<button class="button full" data-action="choose-pack">เลือกชุดคำนี้</button>'+
    '<p class="hint">การเปิดหน้านี้ยังไม่ถือว่าฝึกสำเร็จหรือได้รับคะแนน</p>';
}

function renderReading(){
  const selected=readingExamples[state.selectedLevel]||readingExamples['เริ่มต้น'];
  return intro('อ่านแบบไม่ต้องเดาทุกคำ','อ่านตามระดับ','เลือกบทที่อ่านไหว แล้วค่อยเพิ่มความยาก',true)+
    `<div class="chip-row">${['เริ่มต้น','กำลังฝึก','อ่านคล่อง'].map(level=>`<button class="chip ${state.selectedLevel===level?'selected':''}" data-level="${level}" aria-pressed="${state.selectedLevel===level}">${level}</button>`).join('')}</div>`+
    `<div class="card"><h3>${escapeHtml(selected.title)}</h3><p>${escapeHtml(selected.sample)}</p><p>${escapeHtml(selected.thai)}</p><small>ข้อความร่าง ${escapeHtml(selected.revision)} · ความยากยังไม่ผ่านผู้ตรวจ</small></div>`+
    actionCard('▤','อ่านเรื่องและตอบคำถาม','มีคำแปลช่วยเมื่อแตะคำที่ไม่รู้','mode:cefr-reading')+
    actionCard('✦','อ่านเรื่องช่วยจำ','ใช้เรื่องสั้นเชื่อมคำกับภาพในใจ','mode:associative-reading','gold')+
    '<div class="info">คำว่า “ระดับ” ในหน้านี้หมายถึงความยากของบทอ่าน ไม่ใช่การตัดสินความสามารถของคุณ</div>';
}

function renderGames(){
  return intro('เล่นสั้น ๆ แล้วได้ฝึก','เกมฝึกภาษา','เลือกเกมที่เข้าใจง่าย เล่นจบแล้วกลับมาฝึกต่อ',true)+
    actionCard('◈','จับคู่คำกับความหมาย','แตะคู่ที่ตรงกัน','mode:matching')+
    actionCard('✦','เรียงตัวอักษร','เรียงตัวอักษรเป็นคำอังกฤษ','mode:word-scramble','gold')+
    actionCard('▤','เรียงประโยค','จัดคำให้เป็นประโยคที่อ่านรู้เรื่อง','mode:sentence-scramble','green')+
    actionCard('★','ดวลกับสถิติเดิม','เปรียบเทียบกับการฝึกของตัวเอง ไม่ต้องแข่งกับคนอื่น','mode:meaning-quiz','pink')+
    '<p class="hint">เกมใช้คำศัพท์ชุดเดียวกับบทเรียน ไม่ต้องเรียนระบบใหม่</p>';
}

function renderSpeech(){
  return intro('ลองฝึกด้วยเสียง','ฟังและพูด','เริ่มจากฟังก่อน แล้วใช้ไมค์เมื่อพร้อม',true)+
    actionCard('♫','ฟังแล้วพิมพ์','ฟังคำและพิมพ์สิ่งที่ได้ยิน','mode:dictation')+
    actionCard('▣','ฟังแล้วตอบคำถาม','ลองจับข้อมูลสำคัญจากประโยคสั้น','exam','gold')+
    actionCard('◉','พูดคำ','ฟังตัวอย่างแล้วลองพูดตาม','mode:speaking','green')+
    actionCard('◷','ฟังแล้วพูดตาม','ฝึกประโยคสั้น ๆ ทีละช่วง','mode:shadowing','gold')+
    '<div class="info">ถ้าไม่อนุญาตไมค์ ยังกลับไปฝึกแบบอ่านและพิมพ์ได้ เสียงพูดจะไม่กลายเป็นคะแนนเอง</div>';
}

function renderCamera(){
  const stage=state.cameraStage;
  let step='';
  if(stage==='start')step='<div class="card"><h3>เริ่มจากภาพรอบตัว</h3><p>เปิดกล้องเพื่อถ่ายของที่อยากรู้คำศัพท์ หรือเลือกรูปที่มีอยู่ในเครื่อง</p><div class="button-row"><button class="button" data-camera-stage="permission">เปิดกล้อง</button><label class="button secondary" for="photo-input">เลือกรูป</label></div></div>';
  if(stage==='permission')step='<div class="card"><h3>ขอใช้กล้อง</h3><p>แอปจะขออนุญาตก่อนเปิดกล้อง คุณยังเลือกภาพเดิมหรือเพิ่มคำด้วยตัวเองได้</p><div class="button-row"><button class="button" data-camera-stage="ready">ดูหน้ากล้องตัวอย่าง</button><button class="button secondary" data-camera-stage="denied">ไม่อนุญาต</button></div></div>';
  if(stage==='denied')step='<div class="warning">ยังใช้กล้องไม่ได้ หากต้องการถ่ายภาพ ให้เปิดสิทธิ์กล้องในการตั้งค่าเครื่อง หรือเลือกรูปที่มีอยู่</div><button class="button secondary full" data-camera-stage="permission">ลองเปิดกล้องอีกครั้ง</button>';
  if(stage==='ready')step='<div class="card"><h3>หน้ากล้องตัวอย่าง ยังไม่ได้ตรวจความพร้อมจริง</h3><p>เล็งสิ่งของให้เห็นชัด แล้วถ่ายภาพ ในร่างนี้ไม่มีภาพจากกล้องจริง</p><div class="button-row"><button class="button" data-camera-stage="result">ดูผลตัวอย่าง</button><button class="button secondary" data-camera-stage="failed">ดูกรณีอ่านภาพไม่ได้</button></div></div>';
  if(stage==='missing')step='<div class="warning">ยังไม่มีโมเดลรู้จำภาพที่ตรวจสอบแล้ว การเลือกภาพไม่ได้ยืนยันว่าโมเดลพร้อม ต้นแบบนี้ไม่มีการเตรียมหรือเรียกโมเดล เพิ่มคำด้วยตัวเองได้ทันที</div><button class="button secondary full" data-camera-stage="ready">ดูหน้าหลังเตรียมโมเดล (ตัวอย่าง)</button>';
  if(stage==='failed')step='<div class="warning">ยังดูภาพนี้ไม่ได้ ลองถ่ายในที่สว่างขึ้นหรือเลือกภาพอื่น หากยังไม่ได้ ให้เพิ่มคำด้วยตัวเอง</div><button class="button secondary full" data-camera-stage="ready">ลองถ่ายใหม่</button>';
  if(stage==='result')step='<div class="card"><span class="smalltag">ผลสมมติสำหรับดูหน้าจอ</span><h3>ระบบเสนอ: book</h3><p>หนังสือ · โมเดลอาจทายผิด ตรวจให้ตรงกับสิ่งที่เห็นก่อนเก็บคำ</p><div class="button-row"><button class="button" data-route="add-word">ตรวจแล้ว ไปกรอกคำ</button><button class="button secondary" data-camera-stage="ready">ไม่ตรง ลองใหม่</button></div></div>';
  return intro('เห็นของรอบตัวแล้วอยากรู้คำ?','เรียนคำจากภาพ','ถ่ายหรือเลือกรูป แล้วตรวจคำก่อนบันทึก',true)+
    '<input id="photo-input" type="file" accept="image/*" class="visually-hidden">'+step+
    (state.photoUrl?`<img class="photo-preview" src="${state.photoUrl}" alt="ภาพตัวอย่างที่เลือก">`:'')+
    (state.photoUrl?'<div class="info">เลือกรูปแล้ว ภาพนี้แสดงเฉพาะในหน้าเว็บ ร่างนี้ไม่ได้วิเคราะห์ภาพ</div>':'')+
    button('เพิ่มคำด้วยตัวเอง','add-word',true)+'<button class="button secondary full" data-action="camera-cancel">ยกเลิกและล้างภาพที่เลือก</button>'+
    '<details class="card"><summary>ดูสถานะอื่นของกล้องและโมเดล (สำหรับตรวจแบบร่าง)</summary><div class="camera-demo-options"><button data-camera-stage="permission">ขอสิทธิ์</button><button data-camera-stage="missing">โมเดลยังไม่พร้อม</button><button data-camera-stage="result">ผลที่เสนอ</button><button data-camera-stage="failed">อ่านภาพไม่ได้</button></div></details>'+
    '<p class="sample-note">สถานะกล้องและผลโมเดลทั้งหมดเป็นตัวอย่าง ไม่มีการเปิดกล้อง ดาวน์โหลดโมเดล วิเคราะห์ภาพ อัปโหลด หรือบันทึกคำจริง</p>';
}

function renderAi(){
  const available=state.ai==='on'&&state.scenario!=='offline';
  const status=state.scenario==='offline'?'ไม่มีอินเทอร์เน็ต':state.ai==='off'?'ยังไม่เปิดใช้':state.ai==='failed'?'ผู้ช่วยขัดข้อง':'พร้อมใช้งาน (จำลอง)';
  let html=intro('ถามได้เมื่ออยากได้คำอธิบายเพิ่ม','ผู้ช่วยใน LexiQuest','คุยได้ในแอปนี้เมื่อเปิดใช้ และเรียนต่อได้เมื่อไม่ได้ใช้',true)+
    `<div class="${available?'success':state.ai==='failed'?'warning':'info'}">สถานะ: ${status}</div>`+
    '<details class="card"><summary>ดูสถานะตัวอย่างสำหรับตรวจร่าง</summary><div class="segmented" role="group" aria-label="ลองสถานะผู้ช่วย AI"><button data-ai="off" class="'+(state.ai==='off'?'active':'')+'">ยังไม่ใช้</button><button data-ai="on" class="'+(state.ai==='on'?'active':'')+'">พร้อมใช้</button><button data-ai="failed" class="'+(state.ai==='failed'?'active':'')+'">ขัดข้อง</button></div></details>';
  if(available){html+='<div class="message"><span>อยากให้ช่วยอธิบายอะไรเกี่ยวกับคำที่กำลังเรียน?</span></div><div class="message me"><span>คำว่า book ใช้อย่างไร?</span></div><div class="message"><span>book หมายถึง หนังสือ เช่น I read a book. = ฉันอ่านหนังสือ ลองแต่งประโยคของคุณเองได้นะ</span></div><label class="label" for="ai-question">คำถามของคุณ</label><input id="ai-question" class="input" placeholder="พิมพ์คำถามภาษาไทย"><button class="button full" data-action="ai-send">ดูตัวอย่างคำตอบ</button>';}
  else{html+='<div class="card"><h3>เรียนต่อได้ทันที</h3><p>ผู้ช่วย AI ไม่ใช่เงื่อนไขของแบบฝึก คะแนน หรือประวัติการเรียน</p></div>'+actionCard('◈','กลับไปฝึกด้วยตัวเอง','เปิดแบบฝึกที่ใช้ได้ทันที','practice');if(state.scenario!=='offline')html+=button('ดูการใช้ผู้ช่วยในแอป','ai-connect',true);}
  return html+'<button class="button secondary full" data-action="ai-cancel">ยกเลิกผู้ช่วย กลับไปฝึกเอง</button><p class="sample-note">คำตอบ AI ในหน้านี้เป็นข้อความตัวอย่าง ไม่ได้เรียกผู้ให้บริการหรือสร้างคะแนน</p>';
}

function renderAiConnect(){
  return intro('ตัวช่วยที่อยู่ในแอป','ใช้ผู้ช่วยใน LexiQuest','เปิดเมื่ออยากถามเพิ่มเติม ไม่ต้องผูกบัญชีแชตภายนอก',true)+
    '<div class="warning">ผู้ให้บริการ งบประมาณ และเงื่อนไขอายุยังไม่ผ่านการยืนยัน ใช้ได้เฉพาะหน้าจอจำลอง</div><div class="card"><h3>ก่อนเริ่มคุย</h3><p>แอปจริงต้องบอกว่าใครประมวลผลคำถาม ใช้ข้อมูลใด และมีค่าใช้จ่ายหรือไม่ ผู้ใช้เลือกเปิดหรือปิดได้</p></div>'+
    '<div class="card"><h3>ข้อมูลการเรียนเป็นของคุณ</h3><p>ผู้ช่วยอธิบายได้ แต่ไม่ตอบแทน ไม่รับคะแนนแทน และไม่ดูข้อมูลของผู้ใช้อื่น</p></div>'+
    '<div class="button-row"><button class="button" data-ai="on">เปิดผู้ช่วยในแอป (ตัวอย่างเท่านั้น)</button><button class="button secondary" data-ai="off">ยังไม่ใช้</button></div>'+
    '<p class="hint">ต้นแบบนี้ไม่ส่งคำถามออกจากเครื่อง การเปิดเป็นเพียงตัวอย่างหน้าจอ</p>';
}

function renderAccount(){
  return intro('เริ่มได้โดยไม่ต้องสมัคร','บัญชีของฉัน','เลือกวิธีใช้ที่สบายใจ',true)+
    `<div class="success">กำลังใช้ผู้ใช้ตัวอย่าง ${demoOwnerId==='demo-a'?'A':'B'} โดยไม่ล็อกอิน</div>`+
    '<div class="card"><h3>ลองสลับผู้ใช้</h3><p>ร่าง คำตัวอย่าง และตำแหน่งบทแยกกันในหน้านี้ ปิดหรือโหลดหน้าใหม่จะล้างทั้งหมด ไม่ใช่การเก็บข้อมูลบัญชีจริง</p><div class="button-row"><button class="button secondary" data-demo-owner="demo-a">ผู้ใช้ตัวอย่าง A</button><button class="button secondary" data-demo-owner="demo-b">ผู้ใช้ตัวอย่าง B</button></div></div>'+
    '<div class="card"><h3>เชื่อมบัญชีภายหลัง</h3><p>หากต้องการใช้หลายเครื่อง แอปควรบอกก่อนว่าข้อมูลอะไรจะไปอีกเครื่อง และทำอย่างไรเมื่อข้อมูลไม่ตรงกัน</p></div>'+
    '<label class="label" for="email-sample">อีเมล (หน้าตาตัวอย่าง)</label><input id="email-sample" class="input" type="email" placeholder="อีเมลของคุณ"><button class="button secondary full" data-action="account-demo">ดูขั้นตอนเข้าสู่ระบบ</button>'+
    actionCard('◌','ข้อมูลของฉันอยู่ที่ไหน?','ดูข้อมูลในเครื่องและรายการที่รอส่ง','offline')+
    '<p class="sample-note">ต้นแบบนี้ไม่สร้างบัญชี ไม่รับรหัสผ่าน และไม่ส่งอีเมล</p>';
}

function renderSettings(){
  return intro('ปรับให้ใช้สบายตา','การตั้งค่า','เปลี่ยนขนาดข้อความและสิ่งที่แอปแสดง',true)+
    '<div class="card"><h3>ขนาดตัวอักษร</h3><p>แตะเพื่อทดลองขนาดข้อความในต้นแบบ</p><div class="chip-row"><button class="chip '+(state.fontScale===1?'selected':'')+'" data-font="1" aria-pressed="'+(state.fontScale===1)+'">ปกติ</button><button class="chip '+(state.fontScale===1.12?'selected':'')+'" data-font="1.12" aria-pressed="'+(state.fontScale===1.12)+'">ใหญ่ขึ้น</button></div></div>'+
    `<div class="card"><h3>สีที่เห็นชัดขึ้น</h3><p>เพิ่มความต่างของข้อความกับพื้นหลัง</p><button class="chip ${state.highContrast?'selected':''}" data-action="toggle-contrast" aria-pressed="${state.highContrast}">สีเข้ม</button></div>`+
    actionCard('♫','เสียงและไมค์','ฝึกฟังได้ก่อน ไม่ต้องเปิดไมค์ทันที','speech')+
    actionCard('◉','บัญชีของฉัน','ดูข้อมูลที่อยู่ในเครื่อง','account')+
    actionCard('◌','เรียนเมื่อไม่มีเน็ต','ดูบทเรียนในเครื่องและข้อมูลระหว่างเครื่อง','offline')+
    actionCard('✧','ผู้ช่วย AI','ดูสถานะและเปิดหรือปิดการใช้งาน','ai')+
    '<div class="warning">การลบข้อมูลจริงต้องมีหน้าตรวจทานแยกและบอกผลให้ชัด ต้นแบบนี้ไม่มีปุ่มลบข้อมูล</div>';
}

const sampleHistory=[
  {title:'ทบทวนคำศัพท์',detail:'วันนี้ · 5 นาที',route:'review'},
  {title:'เลือกความหมาย',detail:'เมื่อวาน · คำที่ใช้ทุกวัน',route:'mode:meaning-quiz'},
  {title:'อ่านเรื่องสั้น',detail:'ก่อนหน้านี้ · หนังสือของมะลิ',route:'reading'}
];
function renderProgress(){
  if(state.scenario!=='returning')return intro('เห็นสิ่งที่ทำได้แล้ว','ความก้าวหน้าของฉัน','ผลการเรียนจะเริ่มขึ้นเมื่อคุณฝึกจริง',true)+
    '<div class="info">ยังไม่มีหลักฐานการเรียน ไม่ได้หมายความว่าทำไม่ได้ การเปิดหน้าหรือตอบข้อจำลองไม่สร้างผลสำเร็จ</div>'+
    actionCard('◈','เริ่มฝึกสั้น ๆ','ลองทำข้อแรก แล้วกลับมาดูผล','mode:meaning-quiz');
  return intro('เห็นสิ่งที่ทำได้แล้ว','ความก้าวหน้าของฉัน','ดูหน้าตาตัวอย่าง แยกการฝึกออกจากผลการเรียน',true)+
    '<div class="card"><div class="card-row"><span>ตัวอย่างจำนวนคำที่ฝึก</span><span class="stat">12</span></div><p>ตัวเลขจำลอง ยังไม่มีหลักฐานยืนยันว่าจำได้</p></div>'+
    '<div class="card"><div class="card-row"><span>ตัวอย่างเวลาฝึกสัปดาห์นี้</span><span class="stat">42 นาที</span></div><p>เวลาฝึกแสดงความพยายาม ไม่ใช่หลักฐานความสามารถ</p></div>'+
    actionCard('◷','ดูประวัติการเรียน','เปิดรายการบทเรียนที่ทำไว้','history')+
    actionCard('♡','คำที่ควรฝึกเพิ่ม','ลองกลับไปทำคำที่ยังสับสน','weakness','pink')+
    '<div class="info">หากยังไม่เคยฝึก ให้แสดง “ยังไม่มีข้อมูลการเรียน” พร้อมปุ่มเริ่ม ไม่ใช้กราฟศูนย์ที่ชวนสับสน</div>'+sampleNote;
}

function renderHistory(){
  if(state.scenario!=='returning')return intro('กลับไปดูสิ่งที่เคยทำ','ประวัติการเรียน','รายการจะปรากฏเมื่อคุณทำกิจกรรมจริง',true)+
    '<div class="info">ยังไม่มีประวัติการเรียน ลองเริ่มแบบฝึกสั้น ๆ ก่อน</div>'+button('เริ่มฝึก','mode:meaning-quiz');
  return intro('กลับไปดูสิ่งที่เคยทำ','ประวัติการเรียน','เห็นวันที่และกิจกรรมในภาษาที่เข้าใจง่าย',true)+
    sampleHistory.map(item=>itemRow(item.title,item.detail,item.route,'ตัวอย่าง')).join('')+
    '<div class="info">การเปิดหน้าเรียนเฉย ๆ ไม่ควรปรากฏเป็นกิจกรรมที่ทำสำเร็จ</div>'+sampleNote;
}

function renderRewards(){
  if(state.scenario!=='returning')return intro('กำลังใจจากการฝึก','ภารกิจและรางวัล','เริ่มเรียนก่อน รางวัลจะตามมาจากการฝึกจริง',true)+
    '<div class="info">ยังไม่มีรางวัลสำหรับผู้ใช้ใหม่ ผู้ช่วย AI และการเปิดหน้าไม่สร้างรางวัลแทนคุณ</div>'+button('เริ่มฝึกสั้น ๆ','mode:meaning-quiz');
  return intro('กำลังใจจากการฝึก','ภารกิจและรางวัล','ทำเท่าที่ไหว รางวัลไม่บังคับให้เรียนต่อ',true)+
    '<div class="card"><h3>ภารกิจวันนี้</h3><p>ฝึกคำศัพท์ 5 นาที · ความคืบหน้าในตัวอย่าง 3/5 นาที</p><div class="progress-track" style="margin:12px 0 0"><i style="width:60%"></i></div></div>'+
    '<div class="card"><h3>รางวัลที่ได้รับ</h3><p>ดาวจากการฝึกจริงของผู้เรียนเท่านั้น ไม่มาจากการเปิดหน้าหรือคำตอบ AI</p></div>'+
    actionCard('▣','ร้านค้าในแอป','ดูของตกแต่งก่อนเลือกแลก','shop','gold')+
    actionCard('◈','ไปฝึกต่อ','เลือกแบบฝึกสั้น ๆ','practice')+sampleNote;
}

function renderShop(){
  return intro('ดูให้ชัดก่อนใช้แต้ม','ร้านค้า','เห็นแต้มที่มีและแต้มที่ต้องใช้ก่อนยืนยัน',true)+
    '<div class="info">แต้มในตัวอย่าง: 20 ดวง · ไม่มีการซื้อเงินจริง</div>'+
    '<div class="card"><div class="card-row"><span>กรอบโปรไฟล์สีฟ้า</span><span class="smalltag gold">10 ดวง</span></div><p>ตกแต่งหน้า “ฉัน” เท่านั้น ไม่เพิ่มคะแนนการเรียน</p><button class="button secondary full" data-action="shop-preview" style="margin-top:10px">ดูตัวอย่างก่อนแลก</button></div>'+
    '<div class="card"><div class="card-row"><span>ธีมสีเขียว</span><span class="smalltag gold">25 ดวง</span></div><p>แต้มไม่พอจะบอกตรง ๆ และไม่หักแต้ม</p></div>'+
    '<p class="sample-note">ต้นแบบนี้ไม่หักแต้ม ไม่ซื้อสินค้า และไม่สร้างรายการแลกจริง</p>';
}

function renderExport(){
  return intro('เก็บสำเนาข้อมูลของคุณ','ส่งออกข้อมูล','เลือกว่าจะเก็บอะไร แล้วเปิดอ่านไฟล์ตัวอย่างได้',true)+
    `<div class="card"><h3>เลือกข้อมูล</h3><label><input id="export-words" type="checkbox" ${state.exportWords?'checked':''}> คำศัพท์ของฉัน</label><br><label><input id="export-history" type="checkbox" ${state.exportHistory?'checked':''}> ประวัติการเรียน</label><p>คำศัพท์ตัวอย่าง ${state.words.length} รายการ · ประวัติจำลอง ${state.scenario==='returning'?sampleHistory.length:0} รายการ · ไม่ใช่สำเนาข้อมูลบัญชีจริง</p></div>`+
    '<button class="button full" data-action="export-sample">ดาวน์โหลดไฟล์ตัวอย่าง</button><button class="button secondary full" data-action="back">ยกเลิก</button>'+
    '<div class="info" style="margin-top:12px">ไฟล์ที่ได้จากต้นแบบมีเพียงคำศัพท์ตัวอย่างในหน้านี้ ไม่ใช่ข้อมูลจริงในแอป</div>';
}

function renderOffline(){
  const offline=state.scenario==='offline';
  return intro('ฝึกได้เมื่อไม่มีเน็ต','เรียนเมื่อไม่มีเน็ต','ดูว่ามีบทเรียนอะไรอยู่ในเครื่อง',true)+
    `<div class="${offline?'warning':'success'}">${offline?'ตอนนี้จำลองว่าไม่มีอินเทอร์เน็ต':'ตอนนี้จำลองว่าพร้อมเชื่อมต่อ'} · แบบฝึกในเครื่องยังเปิดได้</div>`+
    '<div class="section-title">บทเรียนในเครื่อง</div>'+
    itemRow('คำที่ใช้ทุกวัน','พร้อมฝึก · 10 คำ','pack-detail','อยู่ในเครื่อง')+
    itemRow('คำศัพท์ของฉัน','พร้อมฝึกแม้ไม่เชื่อมต่อ','words','อยู่ในเครื่อง')+
    actionCard('⟳','ข้อมูลระหว่างเครื่อง','ดูรายการที่รอส่งและกรณีข้อมูลไม่ตรงกัน','sync')+
    '<div class="info">หากส่งข้อมูลไปอีกเครื่องยังไม่เสร็จ แอปต้องบอกตรง ๆ ว่าข้อมูลใดยังอยู่เฉพาะเครื่องนี้</div>';
}

function renderSync(){
  const status=state.sync==='conflict'?'มีข้อมูลสองชุดให้เลือก':state.sync==='queued'?'มี 2 รายการรอส่ง':'ยังไม่มีข้อมูลที่ต้องส่งไปอีกเครื่อง';
  return intro('รู้ว่าข้อมูลอยู่ที่ไหน','ข้อมูลระหว่างเครื่อง','ตรวจได้ก่อนเปลี่ยนเครื่อง',true)+
    `<div class="${state.sync==='conflict'?'warning':'info'}">${status}</div>`+
    '<div class="segmented" role="group" aria-label="สถานะข้อมูลระหว่างเครื่อง"><button data-sync="idle" aria-pressed="'+(state.sync==='idle')+'" class="'+(state.sync==='idle'?'active':'')+'">ปกติ</button><button data-sync="queued" aria-pressed="'+(state.sync==='queued')+'" class="'+(state.sync==='queued'?'active':'')+'">รอส่ง</button><button data-sync="conflict" aria-pressed="'+(state.sync==='conflict')+'" class="'+(state.sync==='conflict'?'active':'')+'">ข้อมูลซ้ำ</button></div>'+
    (state.sync==='conflict'?'<div class="card"><h3>คำว่า book อยู่สองแห่ง</h3><p>ในเครื่อง: หนังสือ · บนบัญชี: หนังสือเรียน</p><div class="button-row"><button class="button secondary" data-action="sync-choice">เก็บในเครื่อง</button><button class="button secondary" data-action="sync-choice">เก็บบนบัญชี</button></div></div>':state.sync==='queued'?'<div class="card"><h3>รายการที่รอ</h3><p>คำศัพท์ 1 รายการ · ประวัติการฝึก 1 รายการ</p></div>':'<div class="card"><h3>ไม่มีรายการรอในตัวอย่าง</h3><p>การฝึกที่ยังไม่ส่งต้องคงอยู่ในเครื่องจนกว่าจะยืนยันสำเร็จ</p></div>')+
    '<p class="sample-note">ไม่มีการส่งข้อมูลจริงจาก prototype นี้</p>';
}

function renderCategories(){
  return intro('จัดคำให้หาเจอง่าย','กลุ่มคำศัพท์','จะไม่จัดกลุ่มก็ได้ คำของคุณยังอยู่',true)+
    `<button class="item-row" data-open-category="คำทั่วไป"><span><strong>คำทั่วไป</strong><small>คำเริ่มต้นที่อยู่ในตัวอย่าง</small></span><span class="smalltag">${state.words.filter(word=>word.category==='คำทั่วไป').length} คำ</span></button>`+
    `<button class="item-row" data-open-category="คำของฉัน"><span><strong>คำของฉัน</strong><small>คำที่คุณเพิ่มเอง</small></span><span class="smalltag">${state.words.filter(word=>word.category==='คำของฉัน').length} คำ</span></button>`+
    '<button class="button secondary full" data-action="category-demo">ดูตัวอย่างเพิ่มกลุ่ม</button>';
}

function invalidateImport(){state.importCandidates=[];state.importRows=[];state.importPreviewSource=null;}
function previewImportDraft(){
  // Two-column prototype only; native import additionally validates partOfSpeech and persistence.
  const seen=new Set(state.words.map(item=>item.word.toLowerCase()));
  state.importRows=state.importDraft.split(/\r?\n/).flatMap((line,index)=>{
    if(!line.trim())return [];
    const parts=line.split(',').map(part=>part.trim());
    const [word='',meaning='']=parts;
    let code=parts.length!==2?'invalidFormat':!word?'missingWord':!meaning?'missingMeaning':seen.has(word.toLowerCase())?'duplicate':'ready';
    if(code==='ready')seen.add(word.toLowerCase());
    return [{rowNumber:index+1,word,meaning,code}];
  });
  state.importCandidates=state.importRows.filter(row=>row.code==='ready');
}
function renderImportRows(){
  const labels={invalidFormat:'รูปแบบไม่ถูกต้อง ใช้คำ, ความหมาย',missingWord:'ขาดคำอังกฤษ',missingMeaning:'ขาดความหมาย',duplicate:'คำซ้ำ ไม่บันทึกทับ',ready:'พร้อมเพิ่ม',imported:'เพิ่มแล้วในตัวอย่าง'};
  return state.importRows.length?`<div class="card"><h3>ผลตรวจรายบรรทัด</h3><ul>${state.importRows.map(row=>`<li>บรรทัด ${row.rowNumber}: ${escapeHtml(row.word)} — ${escapeHtml(labels[row.code])}</li>`).join('')}</ul><p>แก้บรรทัดที่มีปัญหาในช่องด้านบน แล้วตรวจอีกครั้ง</p></div>`:'';
}
function renderImport(){
  return intro('มีรายการคำอยู่แล้ว?','นำเข้าคำศัพท์','ตรวจตัวอย่างก่อนบันทึกทุกครั้ง',true)+
    '<div class="card"><h3>รูปแบบที่อ่านง่าย</h3><p>หนึ่งบรรทัดมีคำอังกฤษ ตามด้วยความหมายไทย เช่น book, หนังสือ</p></div>'+
    `<label class="label" for="import-text">วางรายการคำตัวอย่าง</label><textarea id="import-text" class="input" rows="4" placeholder="book, หนังสือ\nwindow, หน้าต่าง">${escapeHtml(state.importDraft)}</textarea>`+
    '<button class="button full" data-action="import-preview">ตรวจรายการก่อนนำเข้า</button>'+
    renderImportRows()+
    (state.importCandidates.length?`<div class="card"><h3>รายการที่ตรวจแล้ว ${state.importCandidates.length} คำ</h3><p>${state.importCandidates.map(item=>`${escapeHtml(item.word)} = ${escapeHtml(item.meaning)}`).join('<br>')}</p><button class="button secondary full" data-action="import-confirm" style="margin-top:10px">เพิ่มคำเหล่านี้ในตัวอย่าง</button></div>`:'')+
    '<button class="button secondary full" data-action="import-cancel">ยกเลิกการนำเข้า</button><p class="hint">คำซ้ำหรือข้อมูลไม่ครบต้องแสดงให้แก้ ไม่บันทึกทับเงียบ ๆ</p>';
}

function fieldErrorAttributes(id){return state.formErrors[id]?` aria-invalid="true" aria-describedby="${id}-error"`:'';}
function fieldErrorMessage(id){return state.formErrors[id]?`<p id="${id}-error" class="hint">${escapeHtml(state.formErrors[id])}</p>`:'';}
function showFormErrors(errors){
  state.formErrors=errors;
  message('ตรวจช่องที่ระบุ แล้วแก้ไขก่อนบันทึก ข้อมูลที่พิมพ์ยังอยู่');
  document.getElementById(Object.keys(errors)[0])?.focus?.({preventScroll:true});
}
function renderAddWord(){
  return intro('เก็บคำที่อยากจำ','เพิ่มคำศัพท์','ใส่คำและความหมายด้วยตัวเอง',true)+
    `<label class="label" for="new-word">คำภาษาอังกฤษ</label><input id="new-word" class="input"${fieldErrorAttributes('new-word')} value="${escapeHtml(state.addWordDraft.word)}" placeholder="เช่น book" autocomplete="off">`+
    `<label class="label" for="new-meaning">ความหมายภาษาไทย</label><input id="new-meaning" class="input"${fieldErrorAttributes('new-meaning')} value="${escapeHtml(state.addWordDraft.meaning)}" placeholder="เช่น หนังสือ" autocomplete="off">`+
    fieldErrorMessage('new-word')+fieldErrorMessage('new-meaning')+
    '<button class="button full" data-action="add-word">เพิ่มในตัวอย่าง</button>'+
    '<button class="button secondary full" data-action="add-word-cancel">ยกเลิกและล้างร่าง</button><p class="hint">ร่างอยู่เฉพาะผู้ใช้ตัวอย่างในหน้านี้ ปิดหรือโหลดใหม่จะหาย</p>'+sampleNote;
}

function renderMissingWord(){return intro('คำของฉัน','ไม่พบคำที่เลือก','คำนี้อาจถูกลบแล้ว เลือกคำจากคลังอีกครั้ง',true)+button('กลับคลังคำศัพท์','words');}
function renderWordDetail(){
  const word=state.words.find(item=>item.word===state.currentWord);
  if(!word)return renderMissingWord();
  return intro('คำของฉัน',word.word,word.meaning,true)+
    `<div class="card"><h3>ความหมายที่บันทึกไว้</h3><p>${escapeHtml(word.meaning)} · ${escapeHtml(word.category)}</p></div>`+
    actionCard('◈','ลองฝึกคำนี้','เลือกความหมายจากคำตัวอย่าง','mode:meaning-quiz')+
    '<button class="button secondary full" data-route="edit-word">แก้ความหมาย</button>'+
    '<button class="disclosure" data-route="delete-word">ลบคำนี้</button>'+
    '<p class="hint">การลบคำจริงต้องมีหน้าถามยืนยันและบอกผลต่อประวัติการเรียน</p>';
}

function renderEditWord(){
  const word=state.words.find(item=>item.word===state.currentWord);
  if(!word)return renderMissingWord();
  return intro('แก้คำของฉัน','แก้ความหมาย',`คำอังกฤษ: ${word.word}`,true)+
    `<label class="label" for="edit-meaning">ความหมายภาษาไทย</label><input id="edit-meaning" class="input"${fieldErrorAttributes('edit-meaning')} value="${escapeHtml(state.editWordDraft??word.meaning)}">`+
    fieldErrorMessage('edit-meaning')+
    '<button class="button full" data-action="save-edit-word">บันทึกในตัวอย่าง</button><button class="button secondary full" data-action="back">ยกเลิก</button>'+
    '<p class="hint">ในแอปจริงต้องบอกว่าการแก้คำมีผลกับแบบฝึกและประวัติอย่างไร</p>';
}

function renderDeleteWord(){
  const word=state.words.find(item=>item.word===state.currentWord);
  if(!word)return renderMissingWord();
  return intro('ตรวจให้แน่ใจก่อน','ลบคำนี้ใช่ไหม?',`คำที่จะลบ: ${word.word} = ${word.meaning}`,true)+
    '<div class="warning">ในแอปจริงต้องอธิบายผลต่อข้อมูลการฝึกเดิมก่อนยืนยัน ต้นแบบนี้ลบแค่คำตัวอย่างในหน้าปัจจุบัน</div>'+
    '<div class="button-row"><button class="button secondary" data-action="back">เก็บคำไว้</button><button class="button" data-action="confirm-delete-word">ลบคำตัวอย่าง</button></div>';
}

function render({resetScroll=false}={}){
  const previousScroll=appScreen.scrollTop;
  const active=document.activeElement;
  const screenControlFocused=!!active&&appScreen.contains?.(active);
  const fieldFocus=active?.id&&appScreen.contains?.(active)?{id:active.id,start:active.selectionStart,end:active.selectionEnd,direction:active.selectionDirection}:null;
  const focusAttributes=['data-action','data-pilot-track','data-level','data-lab-answer','data-answer','data-goal','data-font','data-category','data-exam-track','data-exam-task','data-exam-answer','data-sync','data-pair','data-token'];
  const focusKey=focusAttributes.map(attribute=>[attribute,document.activeElement?.getAttribute?.(attribute)]).find(([,value])=>value!=null);
  const route=state.route;
  const views={home:renderHome,practice:renderPractice,words:renderWords,me:renderMe,mode:renderMode,review:renderReview,weakness:renderWeakness,plan:renderPlan,packs:renderPacks,'pack-detail':renderPackDetail,reading:renderReading,games:renderGames,'skill-lab':renderSkillLab,'lab-activity':renderLabActivity,exam:renderExam,speech:renderSpeech,camera:renderCamera,ai:renderAi,'ai-connect':renderAiConnect,account:renderAccount,settings:renderSettings,progress:renderProgress,history:renderHistory,rewards:renderRewards,shop:renderShop,export:renderExport,offline:renderOffline,sync:renderSync,categories:renderCategories,import:renderImport,'add-word':renderAddWord,'word-detail':renderWordDetail,'edit-word':renderEditWord,'delete-word':renderDeleteWord,'practice-memory':()=>renderPracticeGroup('practice-memory'),'practice-reading':()=>renderPracticeGroup('practice-reading')};
  const view=route==='pilot'?renderPilot:(views[route]||renderHome);
  const audioNotice=draftAudio.status==='playing'?'<div class="info" role="status">กำลังเล่นเสียงจำลองจากเครื่อง ยังไม่ผ่านผู้ตรวจ <button class="button secondary" data-action="stop-audio">หยุดเสียง</button></div>':draftAudio.status==='error'?'<div class="info" role="status">เครื่องเล่นเสียงขัดข้อง ลองหยุดเสียงจากเครื่องหรืออ่านข้อความแทน ไม่มีผลคะแนน</div>':'';
  appScreen.innerHTML=`<section class="screen" data-view="${route}">${state.notice?`<div class="info banner" role="status">${escapeHtml(state.notice)}</div>`:''}${audioNotice}${view()}</section>`;
  state.notice='';
  const root=route==='home'?'home':route==='practice'||route==='pilot'||route==='mode'||route.startsWith('practice-')||['games','skill-lab','lab-activity','exam','speech','reading','review','weakness'].includes(route)?'practice':route==='words'||['add-word','import','categories','word-detail','edit-word','delete-word','packs','pack-detail','camera'].includes(route)?'words':'me';
  document.querySelectorAll('.bottom-nav button').forEach(button=>{const active=button.dataset.route===root;button.classList.toggle('active',active);if(active)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');});
  appScreen.scrollTop=resetScroll?0:previousScroll;
  if(resetScroll)appScreen.querySelector?.('h1')?.focus({preventScroll:true});
  else if(fieldFocus){
    const field=document.getElementById(fieldFocus.id);
    field?.focus?.({preventScroll:true});
    if(typeof fieldFocus.start==='number'&&typeof fieldFocus.end==='number')field?.setSelectionRange?.(fieldFocus.start,fieldFocus.end,fieldFocus.direction);
  }
  else if(focusKey){
    const [attribute,value]=focusKey;
    let replacement=[...appScreen.querySelectorAll(`[${attribute}]`)].find(node=>node.getAttribute(attribute)===value);
    if(attribute==='data-token'&&replacement?.disabled){
      const available=[...appScreen.querySelectorAll('[data-token]')].filter(node=>!node.disabled);
      replacement=available.find(node=>Number(node.getAttribute('data-token'))>Number(value))||available[0]||[...appScreen.querySelectorAll('[data-action]')].find(node=>node.getAttribute('data-action')==='check-tokens');
    }
    if(replacement&&!replacement.disabled)replacement.focus({preventScroll:true});
    else if(screenControlFocused)appScreen.querySelector?.('h1')?.focus({preventScroll:true});
  }else if(screenControlFocused)appScreen.querySelector?.('h1')?.focus({preventScroll:true});
  if(route==='mode'&&modes.find(mode=>mode.id===state.modeId)?.kind==='handwriting'&&state.modeStep==='question')bindCanvas();
}

function navigate(destination,{replace=false}={}){
  if(state.route==='camera'&&destination!=='camera')cancelCamera();
  invalidateImport();
  state.editWordDraft=null;state.formErrors={};
  state.pendingDraftDiscard=null;
  stopDraftAudio();
  if(destination.startsWith('mode:')){
    state.modeId=destination.slice(5);
    state.modeStep='intro';state.feedback=null;state.selectedTokens=[];state.selectedPair=[];state.cardFlipped=false;
    destination='mode';
  }
  if(!replace&&destination!==state.route)state.backStack.push(state.route);
  if(replace)state.backStack=[];
  state.route=destination;render({resetScroll:true});
}
function goBack(){
  if(state.route==='camera')cancelCamera();
  invalidateImport();
  state.editWordDraft=null;state.formErrors={};
  state.pendingDraftDiscard=null;
  stopDraftAudio();
  state.route=state.backStack.pop()||'home';
  state.feedback=null;render({resetScroll:true});
}
function message(text){state.notice=text;render();}
function currentMode(){
  const mode=modes.find(mode=>mode.id===state.modeId)||modes[1];
  return mode.id==='cefr-reading'?{...mode,...(readingExamples[state.selectedLevel]||readingExamples['เริ่มต้น'])}:mode;
}
function answer(value){
  if(state.answerLocked)return;
  const mode=currentMode();
  const good=value.trim().toLocaleLowerCase()===mode.answer.toLocaleLowerCase();
  state.feedback={good,text:good?'คำตอบตรงกับตัวอย่าง ต้นแบบนี้ไม่บันทึกผลการเรียน':'ยังไม่ตรง ลองดูคำใบ้แล้วตอบอีกครั้ง คำตอบตัวอย่างคือ '+mode.answer};
  render();
  const buttons=appScreen.querySelectorAll('[data-answer]');
  buttons.forEach(button=>{if(button.dataset.answer===value)button.classList.add(good?'correct':'wrong');});
}
function playExample(){
  const mode=currentMode();
  if(!('speechSynthesis' in window)){message('เบราว์เซอร์นี้ไม่มีเสียงตัวอย่าง ลองอ่านคำบนหน้าจอแทนได้');return;}
  speakDraft(mode.sample,.84);
}
function playExamAudio(){
  const example=examExamples[state.examTrack]?.[state.examTask];
  if(state.route!=='exam'||state.examTask!=='listening'||!example)return;
  if(!('speechSynthesis' in window)){message('เครื่องนี้ยังเล่นเสียงตัวอย่างไม่ได้ กดอ่านบทพูดแทนได้');return;}
  speakDraft(example.passage,.82);
}
function labAudioAvailable(){return state.route==='lab-activity'&&(['picture','listening'].includes(state.labModule)||(state.labModule==='mission'&&state.labMissionStep===1));}
function playLabAudio(){
  if(!labAudioAvailable())return;
  const missionFollowUp=state.labModule==='mission'&&state.labMissionStep===1;
  const spoken=missionFollowUp?'It is twenty baht.':labExamples[state.labModule]?.spoken;
  if(!spoken)return;
  if(!('speechSynthesis' in window)){message('เครื่องนี้ยังเล่นเสียงไม่ได้ กดอ่านคำแทนได้');return;}
  speakDraft(spoken,.82);
}
function speakDraft(text,rate){
  stopDraftAudio();
  if(document.hidden||draftAudio.status==='error'){render();return;}
  const generation=draftAudio.generation,owner=demoOwnerId,route=state.route;
  const current=()=>generation===draftAudio.generation&&owner===demoOwnerId&&route===state.route;
  try {
    const utterance=new SpeechSynthesisUtterance(text);
    utterance.lang='en-US';utterance.rate=rate;
    utterance.onend=()=>{if(current()){draftAudio.status='idle';render();}};
    utterance.onerror=()=>{if(current()){draftAudio.status='error';render();}};
    draftAudio.status='playing';window.speechSynthesis.speak(utterance);render();
  } catch {if(current()){draftAudio.status='error';render();}}
}
function bindCanvas(){
  const canvas=document.getElementById('writing-canvas');
  if(!canvas)return;
  const ctx=canvas.getContext('2d');
  if(!ctx)return;
  const owner=demoOwnerId,modeId=state.modeId;
  const strokes=state.canvasDrafts[modeId]||(state.canvasDrafts[modeId]=[]);
  const current=()=>owner===demoOwnerId&&state.route==='mode'&&state.modeStep==='question'&&state.modeId===modeId&&document.getElementById('writing-canvas')===canvas&&state.canvasDrafts[modeId]===strokes;
  ctx.lineWidth=3;ctx.lineCap='round';ctx.strokeStyle='#1f6fab';
  for(const stroke of strokes){
    ctx.beginPath();ctx.moveTo(stroke[0].x,stroke[0].y);
    for(const p of stroke.slice(1))ctx.lineTo(p.x,p.y);
    ctx.stroke();
  }
  let pointer=null,stroke=null;
  function point(event){const box=canvas.getBoundingClientRect();if(box.width<=0||box.height<=0)return null;const x=(event.clientX-box.left)*canvas.width/box.width,y=(event.clientY-box.top)*canvas.height/box.height;return Number.isFinite(x)&&Number.isFinite(y)?{x,y}:null;}
  canvas.addEventListener('pointerdown',event=>{
    if(!current()||pointer!==null||event.button!==0)return;
    const p=point(event);if(!p)return;
    canvas.setPointerCapture(event.pointerId);pointer=event.pointerId;stroke=[p];strokes.push(stroke);ctx.beginPath();ctx.moveTo(p.x,p.y);
  });
  canvas.addEventListener('pointermove',event=>{
    if(!current()||pointer===null||pointer!==event.pointerId)return;
    const p=point(event);if(!p)return;
    stroke.push(p);ctx.lineTo(p.x,p.y);ctx.stroke();
  });
  function finish(event){if(pointer!==event.pointerId)return;pointer=null;stroke=null;}
  canvas.addEventListener('pointerup',finish);
  canvas.addEventListener('pointercancel',finish);
  canvas.addEventListener('lostpointercapture',finish);
}

function handleAction(action){
  if(action==='exam-discard'||action==='lab-discard'){
    const kind=action==='exam-discard'?'exam':'lab';
    if((kind==='exam'&&(state.route!=='exam'||state.examTask!=='writing'))||(kind==='lab'&&(state.route!=='lab-activity'||state.labModule!=='writing')))return;
    state.pendingDraftDiscard={kind,owner:demoOwnerId,key:kind==='exam'?examDraftKey():'writing'};render();return;
  }
  if(action==='cancel-draft-discard'){state.pendingDraftDiscard=null;render();return;}
  if(action==='confirm-draft-discard'){
    const pending=state.pendingDraftDiscard;state.pendingDraftDiscard=null;
    if(pending?.owner===demoOwnerId){
      if(pending.kind==='exam'&&state.route==='exam'&&pending.key===examDraftKey()){storeExamDraft('');state.examFeedback=null;}
      if(pending.kind==='lab'&&state.route==='lab-activity'&&state.labModule==='writing'){state.labDraft='';state.labFeedback=null;}
    }
    render();return;
  }
  const mode=currentMode();
  if(action==='stop-audio'){stopDraftAudio();render();return;}
  if(action==='pilot-resume'){if(state.pilotLastTrack)openPilot(state.pilotLastTrack);return;}
  if(action==='pilot-pause'){navigate('home');return;}
  if(action==='pilot-restart'){
    if(!state.pilotProgress[state.pilotTrack])return;
    state.pilotProgress[state.pilotTrack]={step:0,help:false,thai:false,outcomes:{},revision:pilotContent.revision};
    render({resetScroll:true});return;
  }
  if(action==='pilot-thai'){const p=state.pilotProgress.story;if(state.pilotTrack==='story'&&pilotContent.tracks.find(t=>t.id==='story')?.steps[p?.step]?.id==='story'){p.thai=!p.thai;render();}return;}
  if(action==='pilot-help'){const p=state.pilotProgress[state.pilotTrack];if(p){p.help=!p.help;render();}return;}
  if(action==='pilot-audio'){message('ยังไม่มีเสียงที่ผ่านตรวจ ใช้ต้นแบบดูทางเดิน หรือเลือกอ่านข้อความแทนได้ ไม่บันทึกว่าตอบผิด');return;}
  if(action==='pilot-next'||action==='pilot-skip'){
    const track=pilotContent.tracks.find(item=>item.id===state.pilotTrack);
    const p=state.pilotProgress[state.pilotTrack];
    if(!track||!p)return;
    if(action==='pilot-skip')p.outcomes[p.step]='skipped';
    p.step=Math.min(p.step+1,track.steps.length-1);p.help=false;
    render({resetScroll:true});return;
  }
  if(action==='back'){goBack();return;}
  if(action==='toggle-modes'){state.showModes=!state.showModes;render();return;}
  if(action==='lab-play-audio'){playLabAudio();return;}
  if(action==='lab-show-transcript'){if(!labAudioAvailable())return;state.labTranscript=!state.labTranscript;render();return;}
  if(action==='lab-retry'){if(state.route!=='lab-activity'||!labExamples[state.labModule]?.options||state.labFeedback!=='wrong')return;state.labFeedback=null;render();return;}
  if(action==='lab-next-step'){if(state.route!=='lab-activity'||state.labModule!=='mission'||state.labMissionStep!==0||state.labFeedback!=='right')return;stopDraftAudio();state.labMissionStep=1;state.labFeedback=null;state.labTranscript=false;render();return;}
  if(action==='lab-review-writing'){
    if(state.route!=='lab-activity'||state.labModule!=='writing')return;
    const value=document.getElementById('lab-writing')?.value??state.labDraft;
    if(!value.trim()){message('ลองเขียนข้อความก่อน แล้วค่อยตรวจงานของตัวเอง');return;}
    state.labDraft=value;state.labFeedback='self-review';render();return;
  }
  if(action==='play-exam-audio'){playExamAudio();return;}
  if(action==='show-exam-transcript'){if(state.route!=='exam'||state.examTask!=='listening')return;state.examTranscript=!state.examTranscript;render();return;}
  if(action==='exam-writing-review'){
    if(state.route!=='exam'||state.examTask!=='writing')return;
    const value=document.getElementById('exam-writing')?.value??state.examDraft;
    if(!value.trim()){message('ลองเขียนคำตอบก่อน แล้วค่อยตรวจด้วยตัวเอง');return;}
    storeExamDraft(value);state.examFeedback='self-review';render();return;
  }
  if(action==='begin-mode'){if(state.route!=='mode'||state.modeStep!=='intro')return;state.modeStep='question';state.feedback=null;render();return;}
  if(action==='hint'){
    if(state.route!=='mode'||state.modeStep!=='question')return;
    const hints={choice:'ลองอ่านโจทย์ช้า ๆ แล้วตัดคำตอบที่ไม่เกี่ยวออก',reading:'ลองมองหาคำที่ซ้ำอยู่ในเรื่องก่อนตอบ',input:'คำอังกฤษนี้ขึ้นต้นด้วยตัว b',dictation:'ลองกดฟังอีกครั้ง แล้วฟังเสียงต้นคำ',matching:'เริ่มจากคำที่คุณจำได้แน่ ๆ หนึ่งคู่',scramble:'ลองวางคำที่บอกว่าใครทำอะไรไว้ก่อน',flashcard:'นึกภาพสิ่งของที่คุณถือเปิดอ่านได้',handwriting:'ลองนึกตัวอักษรตัวแรก แล้วค่อยเขียนต่อ',speech:'ฟังจังหวะของคำก่อน แล้วค่อยพูดตาม',story:'ดูภาพหนังสือในเรื่อง แล้วนึกถึงคำอังกฤษ'};
    state.feedback={good:true,text:'คำใบ้: '+(hints[mode.kind]||'กลับไปอ่านคำสั่งอีกครั้ง แล้วลองใหม่')};render();return;
  }
  if(action==='check-input'){
    if(state.route!=='mode'||state.modeStep!=='question'||!['input','dictation'].includes(mode.kind))return;
    const field=document.getElementById('mode-input');
    const draft=field?.value??state.modeDrafts[mode.id]??'';
    state.modeDrafts[mode.id]=draft;
    const value=draft.trim();
    if(!value){message('ลองพิมพ์คำตอบก่อน แล้วค่อยกดตรวจ');return;}
    answer(value);return;
  }
  if(action==='retry-mode'){
    if(state.route!=='mode'||state.modeStep!=='question')return;
    delete state.modeDrafts[mode.id];delete state.canvasDrafts[mode.id];state.feedback=null;state.selectedTokens=[];state.selectedPair=[];state.cardFlipped=false;render();
    if(['input','dictation','handwriting'].includes(mode.kind))document.getElementById('mode-input')?.focus({preventScroll:true});
    return;
  }
  if(action==='flip-card'){if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='flashcard')return;state.cardFlipped=!state.cardFlipped;render();return;}
  if(action==='card-hard'||action==='card-easy'){if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='flashcard'||!state.cardFlipped)return;state.feedback={good:true,text:action==='card-easy'?'จำได้แล้ว! ในแอปจริงผลจะบันทึกจากการกดของคุณ':'ยังไม่แม่นก็ไม่เป็นไร กลับมาดูคำนี้อีกได้'};render();return;}
  if(action==='clear-tokens'){if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='scramble')return;state.selectedTokens=[];state.feedback=null;render();return;}
  if(action==='check-tokens'){
    if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='scramble')return;
    const candidate=state.selectedTokens.map(index=>mode.tokens[index]).join(mode.id==='word-scramble'?'':' ');
    if(!candidate){message('แตะชิ้นส่วนเพื่อเรียงคำก่อน');return;}
    answer(candidate);return;
  }
  if(action==='clear-canvas'){if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='handwriting')return;delete state.canvasDrafts[mode.id];render();return;}
  if(action==='show-answer'){if(state.route!=='mode'||state.modeStep!=='question'||!['handwriting','story'].includes(mode.kind))return;state.feedback={good:true,text:'ตัวอย่างคำตอบคือ '+mode.answer+' · ลองเขียนอีกครั้งได้โดยไม่คิดคะแนน'};render();return;}
  if(action==='play-audio'){playExample();return;}
  if(action==='speech-demo'){if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='speech')return;state.feedback={good:true,text:'ขั้นตอนจริง: ขออนุญาตไมค์ → ฟังเสียงที่คุณพูด → ให้คุณตรวจผลและลองใหม่ได้ ร่างนี้ไม่เปิดไมค์'};render();return;}
  if(action==='save-plan'){message('เลือกเป้าหมาย '+state.goal+' นาทีแล้วในตัวอย่าง แอปจริงต้องบันทึกให้เจ้าของข้อมูลปัจจุบัน');return;}
  if(action==='choose-pack'){state.selectedPack='คำที่ใช้ทุกวัน';message('เลือกชุดคำที่ใช้ทุกวันแล้วในตัวอย่าง ยังไม่ได้เริ่มเรียนหรือคิดคะแนน');return;}
  if(action==='pack-filter'){message('ตัวกรองหัวข้อในร่างนี้แสดงรูปแบบหน้าจอ รายการจริงต้องกรองตามชุดคำที่มี');return;}
  if(action==='camera-cancel'){cancelCamera();navigate('words');return;}
  if(action==='ai-cancel'){state.ai='off';state.notice='ยกเลิกผู้ช่วยแล้ว ไม่มีการส่งคำถาม';navigate('practice');return;}
  if(action==='ai-send'){if(state.route!=='ai'||state.ai!=='on'||state.scenario==='offline')return;const value=document.getElementById('ai-question')?.value.trim();message(value?'นี่เป็นคำตอบตัวอย่างเท่านั้น ไม่มีการส่งคำถามไปยัง AI':'พิมพ์คำถามก่อน แล้วค่อยกดส่ง');return;}
  if(action==='account-demo'){message('หน้าจอเข้าสู่ระบบจริงต้องแยกจากการเริ่มเรียนแบบไม่ล็อกอิน ร่างนี้ไม่ส่งอีเมล');return;}
  if(action==='shop-preview'){message('ตัวอย่างกรอบโปรไฟล์สีฟ้า · ยังไม่มีการหักแต้ม');return;}
  if(action==='sync-choice'){if(state.route!=='sync'||state.sync!=='conflict')return;state.sync='idle';message('นี่เป็นตัวอย่างการเลือกข้อมูล แอปจริงต้องยืนยันผลก่อนเปลี่ยนข้อมูลถาวร');appScreen.querySelector?.('h1')?.focus({preventScroll:true});return;}
  if(action==='category-demo'){message('กลุ่มคำใหม่จะมีชื่อและจำนวนคำชัดเจน ร่างนี้ยังไม่สร้างกลุ่มจริง');return;}
  if(action==='toggle-contrast'){state.highContrast=!state.highContrast;document.body.classList.toggle('high-contrast',state.highContrast);render();return;}
  if(action==='import-preview'){
    if(state.route!=='import')return;
    state.importDraft=document.getElementById('import-text')?.value??state.importDraft;
    state.importPreviewSource=state.importDraft;
    previewImportDraft();
    message(state.importRows.length?`พร้อมเพิ่ม ${state.importCandidates.length} จาก ${state.importRows.length} บรรทัด · ตรวจผลรายบรรทัดก่อนยืนยัน`:'วางรายการคำก่อน แล้วค่อยกดตรวจ');return;
  }
  if(action==='import-cancel'){if(state.route!=='import')return;invalidateImport();state.importDraft='';navigate('words');return;}
  if(action==='import-confirm'){
    if(state.route!=='import'||state.importPreviewSource===null||state.importPreviewSource!==state.importDraft||!state.importCandidates.length)return;
    let added=0;
    for(const item of state.importCandidates){
      if(state.words.some(word=>word.word.toLowerCase()===item.word.toLowerCase())){item.code='duplicate';continue;}
      state.words.push({word:item.word,meaning:item.meaning,category:'คำของฉัน'});item.code='imported';added++;
    }
    state.importCandidates=[];state.importPreviewSource=null;state.wordQuery='';state.category='ทั้งหมด';
    message(`เพิ่ม ${added} คำในต้นแบบแล้ว ดูผลรายบรรทัดและแก้รายการที่เหลือได้ ข้อมูลแอปจริงไม่เปลี่ยน`);return;
  }
  if(action==='add-word-cancel'){if(state.route!=='add-word')return;state.addWordDraft={word:'',meaning:''};navigate('words');return;}
  if(action==='add-word'){
    if(state.route!=='add-word')return;
    state.addWordDraft={word:document.getElementById('new-word')?.value??state.addWordDraft.word,meaning:document.getElementById('new-meaning')?.value??state.addWordDraft.meaning};
    const word=state.addWordDraft.word.trim();
    const meaning=state.addWordDraft.meaning.trim();
    const errors={};if(!word)errors['new-word']='ใส่คำภาษาอังกฤษ';if(!meaning)errors['new-meaning']='ใส่ความหมายภาษาไทย';
    if(Object.keys(errors).length){showFormErrors(errors);return;}
    if(state.words.some(item=>item.word.toLowerCase()===word.toLowerCase())){showFormErrors({'new-word':'มีคำนี้อยู่แล้ว ลองเปิดคำเดิมเพื่อแก้ความหมาย'});return;}
    state.words.unshift({word,meaning,category:'คำของฉัน'});state.addWordDraft={word:'',meaning:''};
    state.wordQuery='';state.category='ทั้งหมด';state.notice='เพิ่มคำในต้นแบบแล้ว ข้อมูลจะหายเมื่อปิดหรือโหลดหน้าเว็บใหม่';
    navigate('words');return;
  }
  if(action==='save-edit-word'){
    if(state.route!=='edit-word'||!state.words.some(item=>item.word===state.currentWord))return;
    state.editWordDraft=document.getElementById('edit-meaning')?.value??state.editWordDraft;
    const meaning=state.editWordDraft?.trim();
    if(!meaning){showFormErrors({'edit-meaning':'ใส่ความหมายภาษาไทยก่อนบันทึก'});return;}
    const word=state.words.find(item=>item.word===state.currentWord);
    if(word)word.meaning=meaning;
    state.notice='แก้ความหมายในต้นแบบแล้ว ข้อมูลนี้อยู่เพียงในหน้าเว็บ';navigate('word-detail');return;
  }
  if(action==='confirm-delete-word'){
    if(state.route!=='delete-word'||!state.words.some(item=>item.word===state.currentWord))return;
    state.words=state.words.filter(item=>item.word!==state.currentWord);
    state.currentWord=null;state.notice='ลบคำตัวอย่างแล้ว ข้อมูลแอปจริงไม่เปลี่ยน';navigate('words');return;
  }
  if(action==='export-sample'){
    if(state.route!=='export')return;
    if(!state.exportWords&&!state.exportHistory){message('เลือกข้อมูลอย่างน้อยหนึ่งอย่างก่อน');return;}
    const rows=['ชนิด,รายการ,รายละเอียด'];
    if(state.exportWords)rows.push(...state.words.map(item=>[csvCell('คำศัพท์'),csvCell(item.word),csvCell(item.meaning)].join(',')));
    if(state.exportHistory&&state.scenario==='returning')rows.push(...sampleHistory.map(item=>[csvCell('ประวัติจำลอง'),csvCell(item.title),csvCell('รายการตัวอย่าง · '+item.detail)].join(',')));
    const csv=rows.join('\n');
    const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'});
    const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='lexiquest-example-words.csv';document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
    message('เตรียมไฟล์ตัวอย่างและส่งคำขอดาวน์โหลดแล้ว ตรวจไฟล์ในรายการดาวน์โหลดของเบราว์เซอร์ ไฟล์นี้ไม่มีข้อมูลจริงของแอป');return;
  }
}

document.addEventListener('click',event=>{
  const owner=event.target.closest('[data-demo-owner]');if(owner){switchDemoOwner(owner.dataset.demoOwner);return;}
  const pilotTrack=event.target.closest('[data-pilot-track]');if(pilotTrack){openPilot(pilotTrack.dataset.pilotTrack);return;}
  const labModule=event.target.closest('[data-lab-module]');if(labModule){if(labModule.isConnected===false||labModule.disabled||!labModules.some(module=>module.id===labModule.dataset.labModule))return;state.labModule=labModule.dataset.labModule;state.labFeedback=null;state.labTranscript=false;state.labMissionStep=0;navigate('lab-activity');return;}
  const labAnswer=event.target.closest('[data-lab-answer]');if(labAnswer){
    if(labAnswer.isConnected===false||state.route!=='lab-activity'||!labExamples[state.labModule]?.options?.some(([value])=>value===labAnswer.dataset.labAnswer))return;
    state.labFeedback=labAnswer.dataset.labAnswer;render();return;
  }
  const examTrack=event.target.closest('[data-exam-track]');if(examTrack){if(examTrack.isConnected===false||examTrack.disabled||state.route!=='exam'||!Object.keys(examExamples).includes(examTrack.dataset.examTrack))return;stopDraftAudio();state.examTrack=examTrack.dataset.examTrack;state.examTask=null;state.examFeedback=null;state.examDraft=state.examDrafts[examDraftKey()]||'';state.pendingDraftDiscard=null;state.examTranscript=false;render();return;}
  const examTask=event.target.closest('[data-exam-task]');if(examTask){if(examTask.isConnected===false||examTask.disabled||state.route!=='exam'||!Object.keys(examExamples[state.examTrack]||{}).includes(examTask.dataset.examTask))return;stopDraftAudio();state.examTask=examTask.dataset.examTask;state.examFeedback=null;state.examDraft=state.examDrafts[examDraftKey()]||'';state.pendingDraftDiscard=null;state.examTranscript=false;render();return;}
  const examAnswer=event.target.closest('[data-exam-answer]');if(examAnswer){
    if(examAnswer.isConnected===false||state.route!=='exam'||!examExamples[state.examTrack]?.[state.examTask]?.options?.some(([value])=>value===examAnswer.dataset.examAnswer))return;
    state.examFeedback=examAnswer.dataset.examAnswer;render();return;
  }
  const cameraStage=event.target.closest('[data-camera-stage]');if(cameraStage){if(state.route!=='camera')return;state.cameraStage=cameraStage.dataset.cameraStage;render();return;}
  const scenario=event.target.closest('[data-scenario]');
  if(scenario){state.scenario=scenario.dataset.scenario;document.querySelectorAll('.scenario').forEach(button=>button.classList.toggle('active',button===scenario));navigate('home',{replace:true});return;}
  const workflow=event.target.closest('[data-workflow]');if(workflow){navigate(workflow.dataset.route);return;}
  const modeButton=event.target.closest('[data-mode]');if(modeButton){navigate('mode:'+modeButton.dataset.mode);return;}
  const routeButton=event.target.closest('[data-route]');if(routeButton){navigate(routeButton.dataset.route,{replace:!!routeButton.closest('.bottom-nav')});return;}
  const openCategory=event.target.closest('[data-open-category]');if(openCategory){state.category=openCategory.dataset.openCategory;navigate('words');return;}
  const category=event.target.closest('[data-category]');if(category){state.category=category.dataset.category;render();return;}
  const goal=event.target.closest('[data-goal]');if(goal){state.goal=Number(goal.dataset.goal);render();return;}
  const level=event.target.closest('[data-level]');if(level){state.selectedLevel=level.dataset.level;render();return;}
  const ai=event.target.closest('[data-ai]');if(ai){state.ai=ai.dataset.ai;state.notice=state.ai==='on'?'กำลังแสดงผู้ช่วยในแอปแบบจำลอง ไม่มีการเรียก AI จริง':'';navigate('ai');return;}
  const sync=event.target.closest('[data-sync]');if(sync){if(state.route!=='sync')return;state.sync=sync.dataset.sync;render();return;}
  const font=event.target.closest('[data-font]');if(font){state.fontScale=Number(font.dataset.font);document.documentElement.style.setProperty('--font-scale',String(state.fontScale));document.body.classList.toggle('large-text',state.fontScale>1);render();return;}
  const word=event.target.closest('[data-word]');if(word){state.currentWord=word.dataset.word;navigate('word-detail');return;}
  const answerButton=event.target.closest('[data-answer]');if(answerButton){
    const mode=currentMode();
    if(answerButton.isConnected===false||state.route!=='mode'||state.modeStep!=='question'||!['choice','reading'].includes(mode.kind)||!mode.options?.includes(answerButton.dataset.answer))return;
    answer(answerButton.dataset.answer);return;
  }
  const pair=event.target.closest('[data-pair]');if(pair){
    if(state.route!=='mode'||state.modeStep!=='question'||currentMode().kind!=='matching'||!['book','window','หนังสือ','หน้าต่าง'].includes(pair.dataset.pair))return;
    if(state.selectedPair.includes(pair.dataset.pair)){state.selectedPair=[];render();return;}
    state.selectedPair.push(pair.dataset.pair);
    if(state.selectedPair.length===2){const two=state.selectedPair;const good=(two.includes('book')&&two.includes('หนังสือ'))||(two.includes('window')&&two.includes('หน้าต่าง'));state.feedback={good,text:good?'จับคู่ถูกแล้ว!':'คู่นี้ยังไม่ตรง ลองอีกครั้ง'};state.selectedPair=[];}
    render();return;
  }
  const token=event.target.closest('[data-token]');if(token){
    const mode=currentMode(),index=Number(token.dataset.token);
    if(state.route!=='mode'||state.modeStep!=='question'||mode.kind!=='scramble'||!Number.isInteger(index)||String(index)!==token.dataset.token||index<0||index>=mode.tokens.length||state.selectedTokens.includes(index))return;
    state.selectedTokens.push(index);render();return;
  }
  const action=event.target.closest('[data-action]');if(action&&action.isConnected!==false&&!action.disabled)handleAction(action.dataset.action);
});

document.addEventListener('input',event=>{
  if(event.target.id==='mode-input'&&state.route==='mode'&&state.modeStep==='question'&&['input','dictation','handwriting'].includes(currentMode().kind)){
    state.modeDrafts[currentMode().id]=event.target.value;
    if(state.feedback){state.feedback=null;render();}
    return;
  }
  if(event.target.id==='new-word'&&state.route==='add-word'){state.addWordDraft.word=event.target.value;return;}
  if(event.target.id==='new-meaning'&&state.route==='add-word'){state.addWordDraft.meaning=event.target.value;return;}
  if(event.target.id==='edit-meaning'&&state.route==='edit-word'){state.editWordDraft=event.target.value;return;}
  if(event.target.id==='import-text'&&state.route==='import'){
    const position=event.target.selectionStart;
    state.importDraft=event.target.value;invalidateImport();state.notice='แก้รายการแล้ว กรุณาตรวจอีกครั้งก่อนนำเข้า';render();
    const field=document.getElementById('import-text');field?.focus?.();field?.setSelectionRange?.(position,position);return;
  }
  if(event.target.id==='exam-writing'&&state.route==='exam'&&state.examTask==='writing'){storeExamDraft(event.target.value);state.examFeedback=null;state.pendingDraftDiscard=null;return;}
  if(event.target.id==='lab-writing'&&state.route==='lab-activity'&&state.labModule==='writing'){state.labDraft=event.target.value;state.labFeedback=null;return;}
  if(event.target.id==='word-search'&&state.route==='words'){
    const position=event.target.selectionStart;
    state.wordQuery=event.target.value;
    render();
    const field=document.getElementById('word-search');field?.focus();field?.setSelectionRange(position,position);
  }
});

document.addEventListener('change',event=>{
  if(event.target.id==='export-words'&&state.route==='export'){state.exportWords=event.target.checked;return;}
  if(event.target.id==='export-history'&&state.route==='export'){state.exportHistory=event.target.checked;return;}
  if(event.target.id==='photo-input'&&event.target.files?.[0]){
    if(state.route!=='camera')return;
    if(state.photoUrl)URL.revokeObjectURL(state.photoUrl);
    state.photoUrl=URL.createObjectURL(event.target.files[0]);
    state.cameraStage='missing';
    render();
  }
});

document.addEventListener('visibilitychange',()=>{if(document.hidden){stopDraftAudio();render();}});
window.addEventListener?.('pagehide',()=>{stopDraftAudio();cancelCamera();render();});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&state.backStack.length)goBack();
});

document.getElementById('workflow-map').innerHTML=workflows.map(item=>`<button data-workflow="${item.id}" data-route="${item.route}"><b>${item.id}</b>${item.label}</button>`).join('');
const labMap=document.getElementById('lab-map');
if(labMap)labMap.innerHTML=labModules.map(item=>`<button data-lab-module="${item.id}">${item.title}</button>`).join('');
document.getElementById('mode-map').innerHTML=modes.map(item=>`<button data-mode="${item.id}">${item.label}</button>`).join('');
const params=new URLSearchParams(location.search);
const initial=params.get('screen');
if(initial&&([...workflows.map(item=>item.route),'home','practice','words','me','mode'].includes(initial)))state.route=initial;
if(modes.some(mode=>mode.id===params.get('mode')))state.modeId=params.get('mode');
if(params.get('preview')==='phone')document.body.classList.add('phone-only');
render();
