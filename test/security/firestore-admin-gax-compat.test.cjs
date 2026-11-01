const assert = require('node:assert/strict');
const { test, after } = require('node:test');
const { createRequire } = require('node:module');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { PassThrough, Transform } = require('node:stream');
const net = require('node:net');
const tls = require('node:tls');
const http = require('node:http');
const https = require('node:https');

const project = path.resolve(__dirname, '..', '..');
const requireProject = createRequire(path.join(project, 'package.json'));
const metadata = filename => JSON.parse(readFileSync(filename, 'utf8'));
const lock = metadata(path.join(project, 'package-lock.json'));
const original = { connect: net.Socket.prototype.connect, tls: tls.connect,
  http: http.request, https: https.request, fetch: global.fetch };
let blockedNetwork = 0;
const deny = () => { blockedNetwork++; throw new Error('Proof forbids all network/ADC requests'); };
net.Socket.prototype.connect = deny;
tls.connect = deny;
http.request = deny;
https.request = deny;
global.fetch = deny;
after(() => {
  net.Socket.prototype.connect = original.connect;
  tls.connect = original.tls;
  http.request = original.http;
  https.request = original.https;
  global.fetch = original.fetch;
  assert.equal(blockedNetwork, 0, 'Consumer paths must not attempt network/ADC');
});
const api = requireProject('@google-cloud/firestore-api');
const sdk = requireProject('@google-cloud/firestore');
const apiRequire = createRequire(requireProject.resolve('@google-cloud/firestore-api'));
const doc = id => ({name: 'projects/demo-lexiquest-closure/databases/(default)/documents/probes/' + id,
  fields: {value: {stringValue: 'synthetic-' + id}}});
async function collect(stream) { const rows = []; for await (const row of stream) rows.push(row); return rows; }
function collectStream(stream) { return new Promise((resolve,reject) => {
  const rows=[]; stream.on('data',row=>rows.push(row)); stream.on('error',reject);
  stream.on('end',()=>resolve(rows));
}); }
function makeClient(version) {
  const calls = [];
  const client = new api[version].FirestoreClient({ projectId: 'demo-lexiquest-closure' });
  const unary = name => (...args) => {
    const request = args[0];
    calls.push({name, request});
    const callback = args.findLast(arg => typeof arg === 'function');
    let response;
    if (name === 'listDocuments') response = request.pageToken === 'next'
      ? {documents: [doc('second')], nextPageToken: ''}
      : {documents: [doc('first')], nextPageToken: 'next'};
    else if (name === 'getDocument') response = {...doc('first'), name: request.name};
    else if (name === 'createDocument') response = {...doc(request.documentId), fields: request.document.fields};
    else if (name === 'updateDocument') response = request.document;
    else response = {};
    setImmediate(() => callback(null, response));
    return {cancel() {}, on() { return this; }};
  };
  const stub = Object.fromEntries(['getDocument','listDocuments','createDocument',
    'updateDocument','deleteDocument','batchGetDocuments','beginTransaction',
    'commit','rollback','runAggregationQuery','partitionQuery','write',
    'listCollectionIds','batchWrite','executePipeline'].map(name => [name, unary(name)]));
  stub.runQuery = request => {
    calls.push({name: 'runQuery', request});
    const stream = new PassThrough({objectMode: true});
    stream.cancel = () => stream.destroy();
    setImmediate(() => { stream.emit('metadata', {}); stream.write({document: doc('first')});
      stream.end({document: doc('second')}); stream.emit('status', {code:0}); });
    return stream;
  };
  stub.listen = () => {
    const stream = new Transform({objectMode: true, transform(request, _, done) {
      calls.push({name: 'listen', request});
      this.push({targetChange: {targetChangeType: 1, targetIds: [request.addTarget.targetId]}});
      done();
    }});
    setImmediate(() => stream.emit('metadata', {}));
    stream.on('finish', () => stream.emit('status', {code:0}));
    stream.cancel = () => stream.destroy();
    return stream;
  };
  stub.close = () => {};
  client._gaxGrpc.createStub = async () => stub; // Replace only transport; generated client + gax are real.
  return {client, calls};
}

test('scoped parent graph preserves generated client and removes the affected packages', () => {
  const gaxMain = apiRequire.resolve('google-gax');
  const gaxPackage = metadata(path.join(path.dirname(gaxMain), '..', '..', 'package.json'));
  assert.equal(gaxPackage.version, '6.13.0');
  assert.equal(requireProject('@google-cloud/firestore-api/package.json').version, '0.2.0');
  const affected = Object.keys(lock.packages).filter(p => /node_modules\/(glob|minimatch|rimraf)$/.test(p));
  assert.deepEqual(affected, []);
});

test('all four consumed CommonJS/deep exports and both deprecated factories remain usable', async () => {
  for (const name of ['@google-cloud/firestore-api',
      '@google-cloud/firestore-api/build/protos/protos',
      '@google-cloud/firestore-api/build/src/v1',
      '@google-cloud/firestore-api/build/src/v1/firestore_client_config.json']) {
    assert.ok(requireProject(name));
  }
  for (const version of ['v1','v1beta1']) {
    assert.equal(typeof sdk[version], 'function');
    const client = sdk[version]({projectId:'demo-lexiquest-closure'});
    assert.equal(typeof client.getDocument, 'function');
    assert.equal(typeof client.listen, 'function');
    assert.equal(client.auth.useJWTAccessWithScope, true);
    await client.close();
  }
});

test('published proto encoders retain ordinary document values and request wire shape', () => {
  const messages = requireProject('@google-cloud/firestore-api/build/protos/protos').google.firestore.v1;
  const input = {database:'projects/demo-lexiquest-closure/databases/(default)', writes:[{
    update:{...doc('wire'),fields:{number:{integerValue:'9007199254740993'}, text:{stringValue:'คำ synthetic'},
      bytes:{bytesValue:Buffer.from([1,2,3])}, map:{mapValue:{fields:{ok:{booleanValue:true}}}}}},
    updateMask:{fieldPaths:['number','text']},
  }]};
  const wire = messages.CommitRequest.encode(messages.CommitRequest.fromObject(input)).finish();
  const result = messages.CommitRequest.toObject(messages.CommitRequest.decode(wire), {longs:String,bytes:Buffer});
  assert.equal(result.database,input.database);
  assert.equal(result.writes[0].update.fields.number.integerValue,'9007199254740993');
  assert.equal(result.writes[0].update.fields.text.stringValue,'คำ synthetic');
  assert.deepEqual(result.writes[0].update.fields.bytes.bytesValue,Buffer.from([1,2,3]));
  assert.deepEqual(result.writes[0].updateMask.fieldPaths,['number','text']);
});

for (const version of ['v1','v1beta1']) {
  test(version + ' real generated unary promise/callback and auth options work through gax6', {timeout:5000}, async () => {
    const {client,calls} = makeClient(version);
    try {
      const name = doc('first').name;
      const [found] = await client.getDocument({name});
      assert.equal(found.name,name);
      const byCallback = await new Promise((resolve,reject) =>
        client.getDocument({name}, (error,response) => error ? reject(error) : resolve(response)));
      assert.equal(byCallback.fields.value.stringValue,'synthetic-first');
      const [created] = await client.createDocument({parent:'projects/demo-lexiquest-closure/databases/(default)/documents',
        collectionId:'probes',documentId:'created',document:{fields:{value:{stringValue:'created'}}}});
      assert.equal(created.fields.value.stringValue,'created');
      const [updated] = await client.updateDocument({document:doc('updated')});
      assert.equal(updated.name,doc('updated').name);
      await client.deleteDocument({name});
      assert.equal(await client.getProjectId(),'demo-lexiquest-closure');
      assert.equal(await new Promise((resolve,reject) =>
        client.getProjectId((error,id) => error ? reject(error) : resolve(id))), 'demo-lexiquest-closure');
      assert.equal(client.auth.useJWTAccessWithScope,true);
      assert.ok(calls.some(call => call.name === 'deleteDocument'));
    } finally { await client.close(); }
  });
  test(version + ' actual gax6 auto-page Promise, callback, async iterator and stream keep both pages', {timeout:5000}, async () => {
    const {client} = makeClient(version);
    const request = {parent:'projects/demo-lexiquest-closure/databases/(default)/documents',collectionId:'probes'};
    try {
      const [rows] = await client.listDocuments(request);
      assert.deepEqual(rows.map(x=>x.name),[doc('first').name,doc('second').name]);
      const callbackRows = await new Promise((resolve,reject) =>
        client.listDocuments(request,(error,rows) => error ? reject(error) : resolve(rows)));
      assert.equal(callbackRows.length,2);
      assert.equal((await collect(client.listDocumentsAsync({...request}, {autoPaginate:false}))).length,2);
      assert.equal((await collectStream(client.listDocumentsStream(request))).length,2);
    } finally { await client.close(); }
  });
  test(version + ' actual gax6 server-stream and bidirectional stream preserve response/request flow', {timeout:5000}, async () => {
    const {client,calls} = makeClient(version);
    try {
      const rows = await collectStream(client.runQuery({parent:'projects/demo-lexiquest-closure/databases/(default)/documents'}));
      assert.deepEqual(rows.map(x=>x.document.name),[doc('first').name,doc('second').name]);
      const listen = client.listen();
      const response = collectStream(listen);
      listen.end({database:'projects/demo-lexiquest-closure/databases/(default)',addTarget:{targetId:7,documents:{documents:[doc('first').name]}}});
      assert.deepEqual((await response)[0].targetChange.targetIds,[7]);
      assert.equal(calls.find(call=>call.name === 'listen').request.addTarget.targetId,7);
    } finally { await client.close(); }
  });
}

test('Firebase Admin public Firestore document/batch/transaction builders retain current source APIs', async () => {
  const {initializeApp,deleteApp,cert} = requireProject('firebase-admin/app');
  const {getFirestore,FieldValue,Timestamp,GeoPoint} = requireProject('firebase-admin/firestore');
  // Ephemeral non-production test key; never persisted or sent over a network.
  const {privateKey} = require('node:crypto').generateKeyPairSync('rsa', {
    modulusLength:2048, privateKeyEncoding:{type:'pkcs8',format:'pem'},
    publicKeyEncoding:{type:'spki',format:'pem'}});
  const app = initializeApp({projectId:'demo-lexiquest-closure',
    credential:cert({projectId:'demo-lexiquest-closure',clientEmail:'synthetic@example.invalid',privateKey})},'offline-parent-proof');
  try {
    const db=getFirestore(app);
    const ref=db.collection('probes').doc('first');
    assert.equal(ref.path,'probes/first');
    assert.equal(typeof db.runTransaction,'function');
    assert.equal(typeof ref.get,'function');
    assert.equal(typeof ref.onSnapshot,'function');
    const batch=db.batch();
    assert.equal(batch.set(ref,{text:'synthetic',count:1,at:Timestamp.fromMillis(0),
      point:new GeoPoint(1,2),ref,updatedAt:FieldValue.serverTimestamp()}),batch);
    assert.equal(batch.update(ref,{count:FieldValue.increment(1)}),batch);
    assert.equal(batch.delete(ref),batch);
  } finally {await deleteApp(app);}
});
