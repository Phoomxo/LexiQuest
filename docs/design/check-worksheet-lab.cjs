const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, 'lexiquest-full-ux.js'), 'utf8');
const listeners = {};
const screen = {innerHTML: '', scrollTop: 0, querySelectorAll: () => []};
const nodes = {'app-screen': screen, 'workflow-map': {innerHTML: ''}, 'mode-map': {innerHTML: ''}};
const spoken = [];
const document = {
  getElementById: id => nodes[id] || null,
  querySelectorAll: () => [],
  addEventListener: (event, handler) => { listeners[event] = handler; }
};
const context = vm.createContext({document, location: {search: ''}, URLSearchParams, console,
  window: {speechSynthesis: {cancel: () => {}, speak: utterance => spoken.push(utterance.text)}},
  SpeechSynthesisUtterance: class { constructor(text) { this.text = text; } }
});
vm.runInContext(source, context);
const click = (attribute, value) => listeners.click({target: {closest: selector => selector === `[${attribute}]` ? {
  dataset: {[attribute.replace(/^data-/, '').replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())]: value},
  closest: () => null
} : null}});
const openModule = id => { click('data-route', 'skill-lab'); click('data-lab-module', id); };

click('data-route', 'practice');
assert.match(screen.innerHTML, /ลองฝึกหลายแบบ/);
click('data-route', 'skill-lab');
assert.equal((screen.innerHTML.match(/data-lab-module=/g) || []).length, 6);
for (const title of ['ภาพ–เสียง–คำ', 'ฟังแล้วหา', 'ประโยคใช้จริง', 'นักสืบข้อความ', 'ห้องเขียน', 'ภารกิจใช้จริง']) {
  assert.match(screen.innerHTML, new RegExp(title));
}

openModule('picture');
assert.match(screen.innerHTML, /แตะภาพ/);
click('data-action', 'lab-play-audio');
assert.equal(spoken.at(-1), 'apple');
click('data-lab-answer', 'wrong');
assert.match(screen.innerHTML, /ลองอีกครั้ง/);
click('data-lab-answer', 'right');
assert.match(screen.innerHTML, /แอปเปิล/);
assert.doesNotMatch(screen.innerHTML, /ได้รับ XP|คะแนนสอบ/);

openModule('listening');
assert.doesNotMatch(screen.innerHTML, /The bus leaves at eight/);
click('data-action', 'lab-play-audio');
assert.match(spoken.at(-1), /The bus leaves at eight/);
click('data-action', 'lab-show-transcript');
assert.match(screen.innerHTML, /The bus leaves at eight/);
click('data-lab-answer', 'right');
assert.match(screen.innerHTML, /8 โมง/);

openModule('sentence');
assert.match(screen.innerHTML, /She ___ to school/);
click('data-lab-answer', 'wrong');
assert.match(screen.innerHTML, /เติม s/);

openModule('evidence');
assert.match(screen.innerHTML, /ไม่มีข้อมูล/);
click('data-lab-answer', 'right');
assert.match(screen.innerHTML, /ข้อความไม่ได้บอกราคา/);

openModule('writing');
assert.match(screen.innerHTML, /เขียนข้อความ/);
nodes['lab-writing'] = {value: 'I will be ten minutes late.'};
click('data-action', 'lab-review-writing');
assert.match(screen.innerHTML, /I will be ten minutes late/);
assert.match(screen.innerHTML, /ตรวจงานของฉัน/);

openModule('mission');
assert.match(screen.innerHTML, /สั่งน้ำ/);
click('data-lab-answer', 'right');
click('data-action', 'lab-next-step');
assert.match(screen.innerHTML, /ฟังราคา/);
assert.doesNotMatch(screen.innerHTML, /ได้รับ XP|คะแนนสอบ/);
console.log('Worksheet lab verified: six modules, answer-specific feedback, audio/transcript, writing self-review, two-step mission, no score claim.');
