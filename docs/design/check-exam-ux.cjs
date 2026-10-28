const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, 'lexiquest-full-ux.js'), 'utf8');
const listeners = {};
const screen = {innerHTML: '', scrollTop: 0, querySelectorAll: () => []};
const nodes = { 'app-screen': screen, 'workflow-map': {innerHTML: ''}, 'mode-map': {innerHTML: ''} };
const document = {
  getElementById: id => nodes[id] || null,
  querySelectorAll: () => [],
  addEventListener: (event, handler) => { listeners[event] = handler; }
};
const spoken = [];
const context = vm.createContext({document, location: {search: ''}, URLSearchParams, console,
  window: {speechSynthesis: {cancel: () => {}, speak: utterance => spoken.push(utterance.text)}},
  SpeechSynthesisUtterance: class { constructor(text) { this.text = text; } }
});
vm.runInContext(source, context);
const run = expression => vm.runInContext(expression, context);
const click = (attribute, value) => listeners.click({target: {closest: selector => selector === `[${attribute}]` ? {
  dataset: {[attribute.replace(/^data-/, '').replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())]: value},
  closest: () => null
} : null}});

assert.match(run('renderPractice()'), /ซ้อมสอบ/);
assert.match(run('renderPractice()'), /เริ่มต้นง่าย/);
assert.match(run('renderPractice()'), /ใช้ภาษาในชีวิตจริง/);
click('data-route', 'exam');
assert.match(screen.innerHTML, /TOEIC/);
assert.match(screen.innerHTML, /IELTS/);
assert.match(screen.innerHTML, /อ่านแล้วคิดจากข้อมูล/);
assert.match(screen.innerHTML, /ฟังแล้วตอบ/);
assert.match(screen.innerHTML, /ไม่ใช่พาร์ตสอบทางการ/);
click('data-exam-track', 'toeic');
click('data-exam-task', 'listening');
assert.match(screen.innerHTML, /ฟังเสียงตัวอย่าง/);
assert.doesNotMatch(screen.innerHTML, /The meeting begins at/);
click('data-action', 'play-exam-audio');
assert.match(spoken.at(-1), /The meeting begins at/);
click('data-action', 'show-exam-transcript');
assert.match(screen.innerHTML, /The meeting begins at/);
click('data-exam-answer', 'right');
assert.match(screen.innerHTML, /ตรงกับเสียง/);
delete context.window.speechSynthesis;
click('data-action', 'play-exam-audio');
assert.match(screen.innerHTML, /กดอ่านบทพูดแทนได้/);
click('data-exam-task', 'reading');
assert.match(screen.innerHTML, /ข้อความ/);
assert.match(screen.innerHTML, /คำถาม/);
click('data-exam-answer', 'wrong');
assert.match(screen.innerHTML, /ยังไม่ตรง/);
assert.doesNotMatch(screen.innerHTML, /คะแนน TOEIC|คะแนน IELTS/);
click('data-exam-task', 'writing');
assert.match(screen.innerHTML, /เขียน/);
assert.match(screen.innerHTML, /ตรวจงานเขียนด้วยตัวเอง/);
nodes['exam-writing'] = {value: 'I can meet on Friday morning.'};
click('data-action', 'exam-writing-review');
assert.match(screen.innerHTML, /ลองตรวจว่าเขียนตรงคำถาม/);
assert.match(screen.innerHTML, /I can meet on Friday morning/);
assert.doesNotMatch(screen.innerHTML, /คะแนน TOEIC|คะแนน IELTS/);
click('data-exam-track', 'ielts');
assert.match(screen.innerHTML, /Academic/);
click('data-exam-task', 'listening');
assert.match(screen.innerHTML, /ฟังเสียงตัวอย่าง/);
click('data-route', 'ai');
assert.match(screen.innerHTML, /ผู้ช่วยใน LexiQuest/);
assert.doesNotMatch(screen.innerHTML, /เชื่อมบัญชี|ChatGPT|MCP/);
click('data-route', 'ai-connect');
assert.match(screen.innerHTML, /เปิดผู้ช่วยในแอป/);
assert.doesNotMatch(screen.innerHTML, /เชื่อมบัญชี|ChatGPT|MCP/);
console.log('UX draft verified: goal entry, listening/audio fallback, both exam tracks, reading and writing feedback, in-app AI without external pairing copy.');
