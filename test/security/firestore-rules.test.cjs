const { after, before, beforeEach, describe, it } = require('node:test');
const { createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  collection,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'demo-lexiquest-rules-test';
const alice = 'alice_uid';
const bob = 'bob_uid';
const productId = 'wallpaper_neon';
const purchaseId = `${alice}_${productId}`;
let testEnv;

// Synthetic R4b server-issued authority. Not a production receipt/issuer.
function researchFixture({minor = false} = {}) {
  const issuedMs = Date.now() - 60000;
  const expiresMs = issuedMs + 86400000;
  const issuedAtUtc = new Date(issuedMs).toISOString();
  const expiresAtUtc = new Date(expiresMs).toISOString();
  const signed = {
    schema: 'lexiquest.research-participation-permit.v1', id: 'permit:a', ownerId: 'owner:a',
    participantClass: minor ? 'minor' : 'adult', ageBandCode: minor ? 'minor' : 'adult', assignmentId: 'assignment:a',
    assignedTreatment: 'adventure', consentReceiptId: 'receipt:a',
    guardianPermissionReceiptRef: minor ? 'guardian:a' : null, learnerAssentReceiptRef: minor ? 'assent:a' : null,
    protocolId: 'motivation', protocolVersion: '1', issuedAtUtc, expiresAtUtc,
    revokedAtUtc: null, issuerKeyId: 'synthetic', localRevision: 1, cloudRevision: 1, isDeleted: false,
  };
  const digest = createHash('sha256').update(JSON.stringify(signed)).digest('hex');
  const permit = {...signed, payloadSha256: digest, signature: 'synthetic-server-signature'};
  const ref = {permitId: permit.id, permitPayloadSha256: digest, permitRevision: 1};
  const authority = {
    firebaseUid: alice, ownerId: 'owner:a', active: true, rulesRevision: 'research-measurement-v1-r2',
    permitPayloadSha256: digest, permitRevision: 1,
    assignmentId: 'assignment:a', protocolId: 'motivation', protocolVersion: '1', treatment: 'adventure',
    issuedAtUtc, expiresAtUtc, issuedAtUtcMs: issuedMs, expiresAtUtcMs: expiresMs,
    consentVersion: 1, consentDecidedAtUtcMs: issuedMs - 2000,
    instrumentId: 'synthetic', instrumentVersion: '1', formId: 'paired', formVersion: '1',
    appVersion: '1', buildId: 'test', databaseSchemaVersion: 24,
    contentRevision: 'content1', evidencePolicyVersion: 'policy1', itemCatalogVersion: '1',
    responseOptions: {baseline: {low: 1, high: 5}, post: {low: 1, high: 5}},
    experimentId: 'motivation', assignedAtUtc: new Date(issuedMs - 1000).toISOString(),
  };
  const run = {
    ...ref, id: 'run:a', ownerId: 'owner:a', assignmentId: 'assignment:a',
    consentVersion: 1, consentDecidedAtUtcMs: issuedMs - 2000,
    protocolId: 'motivation', protocolVersion: '1', treatment: 'adventure',
    instrumentId: 'synthetic', instrumentVersion: '1', formId: 'paired', formVersion: '1',
    appVersion: '1', buildId: 'test', databaseSchemaVersion: 24,
    contentRevision: 'content1', evidencePolicyVersion: 'policy1', state: 'started',
    startedAtUtcMs: issuedMs + 1000, closedAtUtcMs: null,
  };
  const response = {...ref, id: 'response:a', ownerId: 'owner:a', runId: run.id,
    itemId: 'baseline', itemCatalogVersion: '1', responseCode: 'high', ordinalValue: 5,
    answeredAtUtcMs: issuedMs + 2000};
  authority.runPins = Object.fromEntries(Object.entries(run).filter(([key]) =>
    !['id','permitId','permitPayloadSha256','permitRevision','state','startedAtUtcMs','closedAtUtcMs'].includes(key)));
  const opportunity = {...ref, id: 'opportunity:a', ownerId: 'owner:a', measurementRunId: run.id,
    entryAttemptId: '00000000-0000-4000-8000-000000000001', assignedTreatment: 'adventure',
    effectivePresentation: 'adventure', presentedEventId: null, learningSessionId: null,
    startedEventId: null, completedEventId: null, lastSwitchOrdinal: 0, suppressedSwitchCount: 0,
    openedAtUtcMs: issuedMs + 1500, closedAtUtcMs: null};
  authority.eventPins = {
    schemaVersion: 2, eventVersion: 1, actorIdentity: 'owner:a', ownerIdentity: 'owner:a',
    consentContext: {researchConsentVersion: 1, aiConsentGranted: false, voiceConsentGranted: false, socialConsentGranted: false},
    experimentContext: {experimentId: 'motivation', variantId: 'adventure', assignedAtUtc: authority.assignedAtUtc},
    contentRevision: 'content1', policyVersion: 'policy1', appVersion: '1', buildId: 'test', privacyClassification: 'ownerOnly',
  };
  return {permit, ref, authority, run, response, opportunity};
}
function researchEntity(id, payload, operationId = `research:${id}`, revision = 1) {
  return {schemaVersion: 1, entityId: id, payload, revision, isDeleted: false,
    clientUpdatedAtUtcMs: Date.now(), serverUpdatedAt: serverTimestamp(), lastOperationId: operationId};
}
async function seedResearch(f, {run = false, opportunity = false} = {}) {
  await testEnv.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'field_users', alice, 'research_participation_permits', f.permit.id),
      researchEntity(f.permit.id, f.permit));
    await setDoc(doc(db, 'field_users', alice, 'research_sync_authorities', f.permit.id), f.authority);
    await setDoc(doc(db, 'field_users', alice, 'research_receipts', 'receipt:a'), {
      kind: 'consent', ownerId: 'owner:a', active: true, consentVersion: 1,
      decidedAtUtcMs: f.authority.consentDecidedAtUtcMs, expiresAtUtcMs: f.authority.expiresAtUtcMs,
    });
    if (run) await setDoc(doc(db, 'field_users', alice, 'motivation_measurement_runs', f.run.id), researchEntity(f.run.id, f.run));
    if (opportunity) await setDoc(doc(db, 'field_users', alice, 'measurement_opportunities', f.opportunity.id), researchEntity(f.opportunity.id, f.opportunity));
  });
}
function writeResearch(db, collectionName, entityType, payload, {uid = alice, revision = 1, baseRevision = 0, id = payload.id} = {}) {
  const operationId = `research:${id}:${revision}`;
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, collectionName, id), researchEntity(id, payload, operationId, revision));
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion: 1, operationId, entityType, entityId: id, operationKind: 'upsert',
    baseRevision, resultingRevision: revision, acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}
function researchEvent(f, type) {
  const mission = type.startsWith('TodayExperienceMission');
  const payload = {assignedTreatment: 'adventure', effectivePresentation: 'adventure',
    ...(type === 'TodayExperiencePresented'
      ? {entryAttemptId: f.opportunity.entryAttemptId, catalogVersion: '1'}
      : type === 'TodayExperiencePresentationChanged'
        ? {fromPresentation: 'standard', switchOrdinal: 1}
        : type === 'TodayExperienceMissionStarted'
          ? {opportunityId: f.opportunity.id, planId: 'plan:a', mode: 'meaning-quiz'}
          : {opportunityId: f.opportunity.id, planId: 'plan:a', terminalState: 'completed'})};
  return {...f.ref, envelope: {
    schemaVersion: 2, eventId: `event:${type}`, eventType: type, eventVersion: 1,
    occurredAtUtc: new Date(f.authority.issuedAtUtcMs + 3000).toISOString(),
    recordedAtUtc: new Date(f.authority.issuedAtUtcMs + 3000).toISOString(),
    actorIdentity: 'owner:a', ownerIdentity: 'owner:a',
    aggregateType: mission ? 'LearningSession' : 'MeasurementOpportunity',
    aggregateId: mission ? 'session:a' : f.opportunity.id, correlationId: f.opportunity.id,
    idempotencyKey: `research:${type}`, consentContext: {researchConsentVersion: 1,
      aiConsentGranted: false, voiceConsentGranted: false, socialConsentGranted: false},
    experimentContext: {experimentId: 'motivation', variantId: 'adventure', assignedAtUtc: f.authority.assignedAtUtc},
    contentRevision: 'content1', policyVersion: 'policy1', appVersion: '1', buildId: 'test',
    privacyClassification: 'ownerOnly', payload,
  }};
}

describe('R4b Research trusted sync boundary', () => {
  for (const version of [24, 25, 26, 27, 23, 28, '25', '26', 25.5, 26.5]) {
    it(`research schema transport enforces supported version ${version} (${typeof version})`, async () => {
      const f = researchFixture();
      f.run.databaseSchemaVersion = version;
      f.authority.databaseSchemaVersion = version;
      f.authority.runPins.databaseSchemaVersion = version;
      await seedResearch(f);
      const write = writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run);
      await ([24, 25, 26, 27].includes(version) ? assertSucceeds(write) : assertFails(write));
    });
  }
  it('research schema transport retains the exact trusted issuer schema pin', async () => {
    const f = researchFixture();
    await seedResearch(f);
    await assertFails(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun',
      {...f.run, databaseSchemaVersion: 25}));
  });
  it('withdrawal marker is one-way owner-authorized and blocks active remote receipts', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true, opportunity: true});
    const marker = doc(authDb(), 'field_users', alice, 'research_withdrawals', f.permit.id);
    const data = {schemaVersion: 1, permitId: f.permit.id, ownerId: 'owner:a', withdrawnAt: serverTimestamp()};
    await assertFails(setDoc(doc(authDb(bob), 'field_users', alice, 'research_withdrawals', f.permit.id), data));
    await assertSucceeds(setDoc(marker, data));
    await assertFails(updateDoc(marker, {withdrawnAt: serverTimestamp()}));
    await assertFails(deleteDoc(marker));
    await assertFails(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', f.response));
    const p = researchEvent(f, 'TodayExperiencePresented');
    await assertFails(writeResearch(authDb(), 'neutral_events_v2', 'neutralEventV2', p, {id: p.envelope.eventId}));
    await assertSucceeds(getDoc(doc(authDb(), 'field_users', alice, 'research_participation_permits', f.permit.id)));
  });
  it('withdrawal marker cannot invent ownership or grant authority', async () => {
    const f = researchFixture(); await seedResearch(f);
    for (const patch of [{ownerId: 'forged'}, {active: true}, {permitId: 'missing'}]) {
      await assertFails(setDoc(doc(authDb(), 'field_users', alice, 'research_withdrawals', f.permit.id), {
        schemaVersion: 1, permitId: f.permit.id, ownerId: 'owner:a', withdrawnAt: serverTimestamp(), ...patch,
      }));
    }
  });
  it('accepts a run only with current server-issued permit and consent', async () => {
    const f = researchFixture(); await seedResearch(f);
    await assertSucceeds(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
  });
  it('rejects the same run without trusted issuer documents', async () => {
    const f = researchFixture();
    await assertFails(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
  });
  it('cannot forge permit, receipt or rollout authority through any client write', async () => {
    const f = researchFixture();
    for (const [collectionName, id, payload] of [
      ['research_participation_permits', f.permit.id, researchEntity(f.permit.id, f.permit)],
      ['research_receipts', 'receipt:a', {ownerId: 'owner:a', active: true, kind: 'consent'}],
      ['research_sync_authorities', f.permit.id, f.authority],
    ]) await assertFails(setDoc(doc(authDb(), 'field_users', alice, collectionName, id), payload));
    await seedResearch(f);
    await assertFails(updateDoc(doc(authDb(), 'field_users', alice, 'research_participation_permits', f.permit.id), {'payload.signature': 'forged'}));
    await assertFails(deleteDoc(doc(authDb(), 'field_users', alice, 'research_receipts', 'receipt:a')));
  });
  for (const [name, change] of [
    ['inactive authority', f => {f.authority.active = false;}],
    ['expired permit', f => {f.authority.expiresAtUtcMs = Date.now() - 1;}],
    ['revoked permit', f => {f.permit.revokedAtUtc = f.permit.issuedAtUtc;}],
    ['wrong rules revision', f => {f.authority.rulesRevision = 'research-measurement-v1-r0';}],
    ['wrong auth binding', f => {f.authority.firebaseUid = bob;}],
    ['wrong permit digest', f => {f.run.permitPayloadSha256 = 'b'.repeat(64);}],
    ['stale signed revision', f => {f.run.permitRevision = 2;}],
    ['instrument pin replacement', f => {f.run.instrumentVersion = '2';}],
    ['owner replacement', f => {f.run.ownerId = 'owner:attacker';}],
    ['unknown run key', f => {f.run.rawAnswer = 'private text';}],
  ]) it(`rejects ${name}`, async () => {
    const f = researchFixture(); change(f); await seedResearch(f);
    await assertFails(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
  });
  it('current consent withdrawal blocks all new measurement data', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    await testEnv.withSecurityRulesDisabled(async ctx => {
      await updateDoc(doc(ctx.firestore(), 'field_users', alice, 'research_receipts', 'receipt:a'), {active: false});
    });
    await assertFails(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', f.response));
    await assertFails(writeResearch(authDb(), 'measurement_opportunities', 'measurementOpportunity', f.opportunity));
  });
  it('minor requires separate current guardian and learner receipts', async () => {
    const f = researchFixture(); f.permit.participantClass = 'minor';
    f.permit.guardianPermissionReceiptRef = 'guardian:a'; f.permit.learnerAssentReceiptRef = 'assent:a';
    await seedResearch(f);
    await assertFails(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
    await testEnv.withSecurityRulesDisabled(async ctx => {
      for (const [id, kind] of [['guardian:a', 'guardianPermission'], ['assent:a', 'learnerAssent']]) {
        await setDoc(doc(ctx.firestore(), 'field_users', alice, 'research_receipts', id), {
          ownerId: 'owner:a', kind, active: true, expiresAtUtcMs: f.authority.expiresAtUtcMs,
        });
      }
    });
    await assertSucceeds(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
  });
  it('denominator opportunity uploads before baseline response or Presented exists', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    await assertSucceeds(writeResearch(authDb(), 'measurement_opportunities', 'measurementOpportunity', f.opportunity));
  });
  it('coded response must be declared by the trusted pinned instrument', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    await assertSucceeds(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', f.response));
  });
  for (const [field, value] of [['responseCode','unlisted'], ['responseCode','free text'],
    ['ordinalValue',100], ['itemId','unknown'], ['itemCatalogVersion','2'], ['runId','missing']]) {
    it(`rejects response ${field}=${value}`, async () => {
      const f = researchFixture(); await seedResearch(f, {run: true});
      await assertFails(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', {...f.response, [field]: value}));
    });
  }
  it('terminal run update cannot replace immutable pins', async () => {
    const f = researchFixture(); await seedResearch(f);
    await assertSucceeds(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', f.run));
    const terminal = {...f.run, state: 'skipped', closedAtUtcMs: Date.now()};
    await assertFails(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun',
      {...terminal, formVersion: '2'}, {revision: 2, baseRevision: 1}));
    await assertSucceeds(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun', terminal, {revision: 2, baseRevision: 1}));
  });
  it('active permit renewal delivers unacked facts against unchanged historical parents', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true, opportunity: true});
    const captured = researchEvent(f, 'TodayExperiencePresented');
    const oldEnvelope = JSON.stringify(captured.envelope);
    const signed = {...f.permit}; delete signed.payloadSha256; delete signed.signature;
    signed.localRevision = 2; signed.cloudRevision = 2;
    signed.expiresAtUtc = new Date(f.authority.expiresAtUtcMs + 86400000).toISOString();
    const digest = createHash('sha256').update(JSON.stringify(signed)).digest('hex');
    const permit = {...signed, payloadSha256: digest, signature: 'synthetic-renewal-signature'};
    const current = {permitId: f.permit.id, permitPayloadSha256: digest, permitRevision: 2};
    await testEnv.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'field_users', alice, 'research_participation_permits', permit.id),
        researchEntity(permit.id, permit, 'trusted-renewal:2', 2));
      await updateDoc(doc(db, 'field_users', alice, 'research_sync_authorities', permit.id), {
        permitPayloadSha256: digest, permitRevision: 2, expiresAtUtc: signed.expiresAtUtc,
        expiresAtUtcMs: f.authority.expiresAtUtcMs + 86400000,
      });
    });
    await assertFails(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', f.response));
    await assertSucceeds(writeResearch(authDb(), 'motivation_responses', 'motivationResponse', {...f.response, ...current}));
    await assertSucceeds(writeResearch(authDb(), 'neutral_events_v2', 'neutralEventV2',
      {...captured, ...current}, {id: captured.envelope.eventId}));
    if (JSON.stringify(captured.envelope) !== oldEnvelope) throw new Error('frozen event changed');
    // Acknowledged event is immutable, even after legitimate authority renewal.
    await assertFails(writeResearch(authDb(), 'neutral_events_v2', 'neutralEventV2',
      {...captured, ...current}, {id: captured.envelope.eventId, revision: 2, baseRevision: 1}));
    await assertSucceeds(writeResearch(authDb(), 'measurement_opportunities', 'measurementOpportunity',
      {...f.opportunity, ...current, presentedEventId: captured.envelope.eventId}, {revision: 2, baseRevision: 1}));
    await assertSucceeds(writeResearch(authDb(), 'motivation_measurement_runs', 'motivationMeasurementRun',
      {...f.run, ...current, state: 'skipped', closedAtUtcMs: Date.now()}, {revision: 2, baseRevision: 1}));
  });
  for (const type of ['TodayExperiencePresented','TodayExperiencePresentationChanged',
    'TodayExperienceMissionStarted','TodayExperienceMissionCompleted']) {
    it(`delivers frozen participant-only ${type}`, async () => {
      const f = researchFixture(); f.opportunity.lastSwitchOrdinal = 1;
      f.opportunity.learningSessionId = 'session:a';
      await seedResearch(f, {run: true, opportunity: true});
      const p = researchEvent(f, type);
      await assertSucceeds(writeResearch(authDb(), 'neutral_events_v2', 'neutralEventV2', p, {id: p.envelope.eventId}));
    });
  }
  for (const change of [e => {e.eventType = 'QuizCompleted';}, e => {e.payload.rawAnswer = 'text';},
    e => {e.permitId = 'illegal-envelope-field';}, e => {e.consentContext.researchConsentVersion = 0;},
    e => {e.ownerIdentity = 'owner:other';}]) {
    it('rejects mutated neutral event or extra envelope fields', async () => {
      const f = researchFixture(); await seedResearch(f, {run: true, opportunity: true});
      const p = researchEvent(f, 'TodayExperiencePresented'); change(p.envelope);
      await assertFails(writeResearch(authDb(), 'neutral_events_v2', 'neutralEventV2', p, {id: p.envelope.eventId}));
    });
  }
  it('other owners cannot read or write participant records', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    await assertFails(getDoc(doc(authDb(bob), 'field_users', alice, 'research_participation_permits', f.permit.id)));
    await assertFails(writeResearch(authDb(bob), 'motivation_responses', 'motivationResponse', f.response));
  });
  it('cannot mint an operation receipt without matching entity write', async () => {
    await assertFails(setDoc(doc(authDb(), 'field_users', alice, 'operations', 'forged'), {
      schemaVersion: 1, operationId: 'forged', entityType: 'motivationResponse', entityId: 'response:a',
      operationKind: 'upsert', baseRevision: 0, resultingRevision: 1, acknowledgedAt: serverTimestamp(),
    }));
  });
});

// Synthetic consistency-valid plain proof. Server-authority fixtures above are
// emulator-only; these tests do not claim a real session or issuer signature.
function sessionProofFixture(f, phase = 1) {
  const proof = {
    schema: 'lexiquest.research-session-proof.v1',
    ownerId: f.run.ownerId, measurementRunId: f.run.id,
    learningSessionId: 'session:proof', proofRevision: phase,
    activityType: 'quiz', sessionState: phase === 1 ? 'active' : 'completed',
    startedAtUtcMs: f.authority.issuedAtUtcMs + 3000,
    endedAtUtcMs: phase === 1 ? null : f.authority.issuedAtUtcMs + 4000,
    appVersion: f.run.appVersion, buildId: f.run.buildId,
    sessionConfigurationIdentity: null, sessionConfigurationJson: null,
    pairStartOperation: null, pairCheckpointEventVersion: null, pairOwnerLineage: null,
    ...f.ref,
  };
  proof.id = 'research-session-proof:' + createHash('sha256').update(JSON.stringify([
    proof.ownerId, proof.permitId, proof.measurementRunId,
    proof.learningSessionId, proof.proofRevision,
  ])).digest('hex');
  return proof;
}
function proofOperationId(proof) {
  function sorted(value) {
    if (Array.isArray(value)) return value.map(sorted);
    if (value !== null && typeof value === 'object') {
      return Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])]));
    }
    return value;
  }
  return 'research-sync:' + createHash('sha256').update(JSON.stringify(sorted({
    collection: 'research_session_proofs', id: proof.id, payload: proof,
  }))).digest('hex') + ':1';
}
function proofForSession(proof, learningSessionId) {
  const changed = {...proof, learningSessionId};
  changed.id = 'research-session-proof:' + createHash('sha256').update(JSON.stringify([
    changed.ownerId, changed.permitId, changed.measurementRunId,
    changed.learningSessionId, changed.proofRevision,
  ])).digest('hex');
  return changed;
}
function proofWrite(db, proof, {entityOnly = false, operationOnly = false, outer = {}, receipt = {}} = {}) {
  const operationId = proofOperationId(proof);
  const batch = writeBatch(db);
  if (!operationOnly) batch.set(
    doc(db, 'field_users', alice, 'research_session_proofs', proof.id),
    {...researchEntity(proof.id, proof, operationId),
      clientUpdatedAtUtcMs: proof.proofRevision === 1 ? proof.startedAtUtcMs : proof.endedAtUtcMs,
      ...outer},
  );
  if (!entityOnly) batch.set(doc(db, 'field_users', alice, 'operations', operationId), {
    schemaVersion: 1, operationId, entityType: 'researchSessionProof', entityId: proof.id,
    operationKind: 'upsert', baseRevision: 0, resultingRevision: 1,
    acknowledgedAt: serverTimestamp(), ...receipt,
  });
  return batch.commit();
}
describe('R17 research session proof server boundary', () => {
  for (const minor of [false, true]) {
  for (const conflict of [false, true]) {
  it(`checks both phase documents atomically (minor=${minor}, conflict=${conflict})`, async () => {
    const f = researchFixture({minor}); await seedResearch(f, {run: true});
    if (minor) await testEnv.withSecurityRulesDisabled(async ctx => {
      for (const [id, kind] of [['guardian:a', 'guardianPermission'], ['assent:a', 'learnerAssent']]) {
        await setDoc(doc(ctx.firestore(), 'field_users', alice, 'research_receipts', id), {
          ownerId: f.run.ownerId, kind, active: true, expiresAtUtcMs: f.authority.expiresAtUtcMs,
        });
      }
    });
    const db = authDb(), batch = writeBatch(db);
    const phases = [sessionProofFixture(f), sessionProofFixture(f, 2)];
    if (conflict) phases[1].startedAtUtcMs += 1;
    for (const proof of phases) {
      const operationId = proofOperationId(proof);
      batch.set(doc(db, 'field_users', alice, 'research_session_proofs', proof.id), {
        ...researchEntity(proof.id, proof, operationId),
        clientUpdatedAtUtcMs: proof.proofRevision === 1 ? proof.startedAtUtcMs : proof.endedAtUtcMs,
      });
      batch.set(doc(db, 'field_users', alice, 'operations', operationId), {
        schemaVersion: 1, operationId, entityType: 'researchSessionProof', entityId: proof.id,
        operationKind: 'upsert', baseRevision: 0, resultingRevision: 1, acknowledgedAt: serverTimestamp(),
      });
    }
    await (conflict ? assertFails(batch.commit()) : assertSucceeds(batch.commit()));
    for (const proof of phases) {
      assert.equal((await getDoc(doc(db, 'field_users', alice, 'research_session_proofs', proof.id))).exists(), !conflict);
      assert.equal((await getDoc(doc(db, 'field_users', alice, 'operations', proofOperationId(proof)))).exists(), !conflict);
    }
  });
  }
  }
  it('denies a matching second phase when trusted server history is tombstoned', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    const started = sessionProofFixture(f);
    await assertSucceeds(proofWrite(authDb(), started));
    await testEnv.withSecurityRulesDisabled(ctx => updateDoc(
      doc(ctx.firestore(), 'field_users', alice, 'research_session_proofs', started.id), {isDeleted: true}));
    await assertFails(proofWrite(authDb(), sessionProofFixture(f, 2)));
    assert.equal((await getDoc(doc(authDb(), 'field_users', alice, 'research_session_proofs', started.id))).data().isDeleted, true);
  });
  it('accepts two sorted lineage rows and denies reversed or duplicate lineage', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    const current = {ownerId: f.run.ownerId, createdAtUtcMs: f.authority.issuedAtUtcMs - 10000,
      upgradedAtUtcMs: null, mergedIntoOwnerId: null};
    const previous = {ownerId: 'owner:prior', createdAtUtcMs: current.createdAtUtcMs - 1000,
      upgradedAtUtcMs: current.createdAtUtcMs, mergedIntoOwnerId: f.run.ownerId};
    // Structural policy fixture: full semantic Pair source is exercised in Dart.
    const shape = {...sessionProofFixture(f), activityType: 'matching', pairStartOperation: '{}',
      pairCheckpointEventVersion: 1, pairOwnerLineage: [current, previous]};
    await assertSucceeds(proofWrite(authDb(), shape));
    await assertFails(proofWrite(authDb(), {...proofForSession(shape, 'session:reverse'), pairOwnerLineage: [previous, current]}));
    await assertFails(proofWrite(authDb(), {...proofForSession(shape, 'session:duplicate'), pairOwnerLineage: [current, current]}));
  });
  it('checks config UTF-8 bytes independently from character count', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    // Deliberately server-shape-only strings. Dart's mandatory decoder separately
    // validates the real configuration JSON and inner content identity.
    const exact = proofForSession(sessionProofFixture(f), 'session:config-limit');
    exact.sessionConfigurationJson = 'ก'.repeat(5461) + 'a';
    exact.sessionConfigurationIdentity = 'sha256:' + 'a'.repeat(64);
    assert.equal(Buffer.byteLength(exact.sessionConfigurationJson, 'utf8'), 16384);
    await assertSucceeds(proofWrite(authDb(), exact));
    const over = proofForSession(exact, 'session:config-over');
    over.sessionConfigurationJson += 'a';
    assert.ok(over.sessionConfigurationJson.length < 16384);
    await assertFails(proofWrite(authDb(), over));
  });
  for (const [label, change] of [
    ['empty lineage', p => { p.pairOwnerLineage = []; }],
    ['third lineage row', p => { p.pairOwnerLineage.push({...p.pairOwnerLineage[0]}, {...p.pairOwnerLineage[0]}); }],
    ['lineage private field', p => { p.pairOwnerLineage[0].firebaseUid = alice; }],
    ['foreign unmerged lineage', p => { p.pairOwnerLineage[0].ownerId = 'owner:b'; }],
    ['missing lineage key', p => { delete p.pairOwnerLineage[0].upgradedAtUtcMs; }],
    ['string checkpoint version', p => { p.pairCheckpointEventVersion = '1'; }],
    ['unknown checkpoint version', p => { p.pairCheckpointEventVersion = 3; }],
    ['oversize operation text', p => { p.pairStartOperation = 'a'.repeat(40001); }],
  ]) {
    it('enforces compact Pair server shape: ' + label, async () => {
      const f = researchFixture(); await seedResearch(f, {run: true});
      // This proves server structural bounds only, not Dart Pair validity. The
      // actual atomic-start/gateway/receiver test exercises the semantic decoder.
      const shape = {...sessionProofFixture(f), activityType: 'matching', pairStartOperation: '{}',
        pairCheckpointEventVersion: 1, pairOwnerLineage: [{ownerId: f.run.ownerId,
          createdAtUtcMs: f.authority.issuedAtUtcMs - 10000, upgradedAtUtcMs: null, mergedIntoOwnerId: null}]};
      await assertSucceeds(proofWrite(authDb(), shape));
      const changed = proofForSession(JSON.parse(JSON.stringify(shape)), 'session:invalid-pair');
      change(changed);
      await assertFails(proofWrite(authDb(), changed));
    });
  }
  it('accepts Completed first and later Started as separate immutable phase documents', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    const completed = sessionProofFixture(f, 2), started = sessionProofFixture(f);
    await assertSucceeds(proofWrite(authDb(), completed));
    await assertSucceeds(proofWrite(authDb(), started));
    for (const proof of [completed, started]) {
      const ref = doc(authDb(), 'field_users', alice, 'research_session_proofs', proof.id);
      const stored = await assertSucceeds(getDoc(ref));
      assert.deepEqual(stored.data().payload, proof);
      assert.equal(stored.data().revision, 1);
      await assertFails(updateDoc(ref, {'payload.buildId': 'changed'}));
      await assertFails(deleteDoc(ref));
      await assertFails(getDoc(doc(authDb(bob), 'field_users', alice, 'research_session_proofs', proof.id)));
    }
  });
  it('requires one atomic matching entity and operation receipt', async () => {
    const f = researchFixture(); await seedResearch(f, {run: true});
    const started = sessionProofFixture(f), completed = sessionProofFixture(f, 2);
    await assertSucceeds(proofWrite(authDb(), started));
    await assertFails(proofWrite(authDb(), completed, {entityOnly: true}));
    await assertFails(proofWrite(authDb(), completed, {operationOnly: true}));
    await assertFails(proofWrite(authDb(), completed, {receipt: {entityType: 'motivationResponse'}}));
    await assertFails(proofWrite(authDb(), completed, {receipt: {baseRevision: 1, resultingRevision: 2}}));
    await assertSucceeds(proofWrite(authDb(), completed));
  });
  for (const [label, change] of [
    ['unknown key', p => {p.answerHistory = [];}],
    ['missing nullable key', p => {delete p.sessionConfigurationJson;}],
    ['wrong schema', p => {p.schema = 'lexiquest.research-session-proof.v2';}],
    ['forged phase id', p => {p.id = 'research-session-proof:' + 'f'.repeat(64);}],
    ['foreign owner', p => {p.ownerId = 'owner:b';}],
    ['foreign run', p => {p.measurementRunId = 'run:missing';}],
    ['wrong permit digest', p => {p.permitPayloadSha256 = 'f'.repeat(64);}],
    ['string permit revision', p => {p.permitRevision = '1';}],
    ['string phase', p => {p.proofRevision = '2';}],
    ['completed missing end', p => {p.endedAtUtcMs = null;}],
    ['completed reversed end', p => {p.endedAtUtcMs = p.startedAtUtcMs - 1;}],
    ['inconsistent sibling start', p => {p.startedAtUtcMs += 1;}],
    ['wrong app pin', p => {p.appVersion = 'different';}],
    ['partial config', p => {p.sessionConfigurationIdentity = 'sha256:' + 'a'.repeat(64);}],
    ['Pair fields on quiz', p => {p.pairStartOperation = '{}'; p.pairCheckpointEventVersion = 1; p.pairOwnerLineage = [];}],
  ]) {
    it('rejects ' + label + ' after a valid positive control', async () => {
      const f = researchFixture(); await seedResearch(f, {run: true});
      await assertSucceeds(proofWrite(authDb(), sessionProofFixture(f)));
      const changed = sessionProofFixture(f, 2); change(changed);
      if (label === 'foreign owner' || label === 'foreign run') {
        changed.id = 'research-session-proof:' + createHash('sha256').update(JSON.stringify([
          changed.ownerId, changed.permitId, changed.measurementRunId,
          changed.learningSessionId, changed.proofRevision,
        ])).digest('hex');
      }
      await assertFails(proofWrite(authDb(), changed));
    });
  }
  for (const [label, outer] of [
    ['phase two is not wire revision two', {revision: 2}],
    ['tombstone creation', {isDeleted: true}],
    ['timestamp not matching phase fact', {clientUpdatedAtUtcMs: 0}],
    ['unknown envelope version', {schemaVersion: 2}],
  ]) {
    it('rejects ' + label, async () => {
      const f = researchFixture(); await seedResearch(f, {run: true});
      await assertSucceeds(proofWrite(authDb(), sessionProofFixture(f)));
      await assertFails(proofWrite(authDb(), sessionProofFixture(f, 2), {outer}));
    });
  }
  for (const [label, invalidate] of [
    ['missing run', async (db, f) => deleteDoc(doc(db, 'field_users', alice, 'motivation_measurement_runs', f.run.id))],
    ['withdrawal', async (db, f) => setDoc(doc(db, 'field_users', alice, 'research_withdrawals', f.permit.id),
      {schemaVersion: 1, permitId: f.permit.id, ownerId: f.run.ownerId, withdrawnAt: serverTimestamp()})],
    ['inactive receipt', async db => updateDoc(doc(db, 'field_users', alice, 'research_receipts', 'receipt:a'), {active: false})],
    ['expired authority', async (db, f) => updateDoc(doc(db, 'field_users', alice, 'research_sync_authorities', f.permit.id), {expiresAtUtcMs: 0})],
    ['revoked permit', async (db, f) => updateDoc(doc(db, 'field_users', alice, 'research_participation_permits', f.permit.id), {'payload.revokedAtUtc': new Date().toISOString()})],
  ]) {
    it('denies new phase after ' + label + ' without deleting admitted history', async () => {
      const f = researchFixture(); await seedResearch(f, {run: true});
      const started = sessionProofFixture(f);
      await assertSucceeds(proofWrite(authDb(), started));
      await testEnv.withSecurityRulesDisabled(context => invalidate(context.firestore(), f));
      await assertFails(proofWrite(authDb(), sessionProofFixture(f, 2)));
      await assertSucceeds(getDoc(doc(authDb(), 'field_users', alice, 'research_session_proofs', started.id)));
    });
  }
});

function authDb(uid = alice, isAnon = false) {
  const token = isAnon ? { firebase: { sign_in_provider: 'anonymous' } } : {};
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seedStateAndProduct(points = 100, price = 50) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'state', alice), { totalPoints: points });
    await setDoc(doc(db, 'products', productId), {
      name: 'Neon',
      price,
      image_name: 'wallpaper_neon.png',
    });
  });
}

function purchaseData(totalPrice = 50) {
  return {
    user_id: alice,
    product_id: productId,
    total_price: totalPrice,
    created_at: serverTimestamp(),
  };
}

function fieldCategoryData({
  entityId = 'category-1',
  operationId = 'operation-1',
  revision = 1,
} = {}) {
  return {
    schemaVersion: 1,
    entityId,
    payload: {
      name: 'Travel',
      normalizedName: 'travel',
      sortOrder: 0,
      isDeleted: false,
      createdAtUtcMs: 1000,
      updatedAtUtcMs: 2000,
    },
    revision,
    isDeleted: false,
    clientUpdatedAtUtcMs: 2000,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  };
}

function fieldOperationData({
  operationId = 'operation-1',
  entityId = 'category-1',
  baseRevision = 0,
  resultingRevision = 1,
} = {}) {
  return {
    schemaVersion: 1,
    operationId,
    entityType: 'category',
    entityId,
    operationKind: 'upsert',
    baseRevision,
    resultingRevision,
    acknowledgedAt: serverTimestamp(),
  };
}

function writeFieldCategory(db, options = {}) {
  const uid = options.uid ?? alice;
  const entityId = options.entityId ?? 'category-1';
  const operationId = options.operationId ?? 'operation-1';
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'field_users', uid, 'categories', entityId),
    fieldCategoryData({ ...options, entityId, operationId }),
  );
  batch.set(
    doc(db, 'field_users', uid, 'operations', operationId),
    fieldOperationData({ ...options, entityId, operationId }),
  );
  return batch.commit();
}

function writeFieldWord(db, {
  uid = alice,
  entityId = 'word-1',
  operationId = 'word-operation-1',
  categoryId = 'category-1',
  schemaVersion = 1,
  payload,
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'words', entityId), {
    schemaVersion,
    entityId,
    payload: payload ?? {
      categoryId,
      spelling: 'station',
      normalizedSpelling: 'station',
      meaning: 'สถานี',
      normalizedMeaning: 'สถานี',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
      isGlobal: false,
      isDeleted: false,
      createdAtUtcMs: 1000,
      updatedAtUtcMs: 2000,
    },
    revision: 1,
    isDeleted: false,
    clientUpdatedAtUtcMs: 2000,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType: 'word',
    entityId,
    operationKind: 'upsert',
    baseRevision: 0,
    resultingRevision: 1,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function writeFieldLearningEvent(db, {
  uid = alice,
  collection = 'attempts',
  entityType = 'attempt',
  entityId = 'attempt-1',
  operationId = 'attempt-operation-1',
  schemaVersion = 1,
  clientUpdatedAtUtcMs = 2000,
  payload,
} = {}) {
  const resolvedPayload = payload ?? {
    sessionId: 'session-1',
    wordId: 'word-1',
    promptMode: 'meaningChoice',
    isCorrect: true,
    responseTimeMs: 320,
    attemptNumber: 1,
    occurredAtUtcMs: 2000,
    providerProvenance: null,
  };
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, collection, entityId), {
    schemaVersion,
    entityId,
    payload: resolvedPayload,
    revision: 1,
    isDeleted: false,
    clientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType,
    entityId,
    operationKind: 'upsert',
    baseRevision: 0,
    resultingRevision: 1,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function fieldEvidenceContext(overrides = {}) {
  return {
    schemaVersion: 1,
    evidenceClass: 'independentRecall',
    skillId: 'meaning-recall',
    hintLevel: 0,
    policyVersion: 'learning-evidence-v1',
    contentRevision: 'built-in-v1',
    featureContractRevision: '1.0.0',
    featureContractHash:
      'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
    classificationSource: 'declared',
    rolloutMode: 'shadow',
    protocolId: 'evidence-pilot',
    protocolVersion: '1.0.0',
    experimentId: 'evidence-eligibility',
    experimentVersion: 1,
    assignmentId: 'assignment-1',
    cohort: 'shadow',
    researchConsentVersion: 1,
    instrumentId: null,
    instrumentVersion: null,
    formId: null,
    formVersion: null,
    assessmentItemId: null,
    assessmentResponseCode: null,
    scoringRuleVersion: null,
    engagementAllowed: true,
    ...overrides,
  };
}

function fieldLegacyEvidenceContext() {
  return fieldEvidenceContext({
    skillId: 'legacy-unspecified',
    policyVersion: 'legacy-v1',
    contentRevision: 'legacy-unknown',
    featureContractRevision: 'legacy-unversioned',
    featureContractHash:
      '0000000000000000000000000000000000000000000000000000000000000000',
    classificationSource: 'legacyInferred',
    rolloutMode: 'legacy',
    protocolId: null,
    protocolVersion: null,
    experimentId: null,
    experimentVersion: null,
    assignmentId: null,
    cohort: null,
    researchConsentVersion: null,
  });
}

function fieldAttemptV2Payload(context = fieldEvidenceContext()) {
  return {
    sessionId: 'session-1',
    wordId: 'word-1',
    promptMode: 'meaningChoice',
    isCorrect: true,
    responseTimeMs: 320,
    attemptNumber: 1,
    occurredAtUtcMs: 2000,
    providerProvenance: null,
    evidenceClass: context.evidenceClass,
    evidenceContext: context,
  };
}

function writeFieldRewardTransaction(db, {
  uid = alice,
  entityId = 'reward-1',
  operationId = 'reward-operation-1',
  clientUpdatedAtUtcMs,
  payload,
} = {}) {
  const resolvedPayload = payload ?? fieldRewardPayload();
  return writeFieldLearningEvent(db, {
    uid,
    collection: 'reward_transactions',
    entityType: 'rewardTransaction',
    entityId,
    operationId,
    clientUpdatedAtUtcMs:
      clientUpdatedAtUtcMs ?? resolvedPayload.occurredAtUtcMs,
    payload: resolvedPayload,
  });
}

function fieldRewardPayload(overrides = {}) {
  const payload = {
    idempotencyKey: 'purchase-tap-1',
    transactionType: 'purchase',
    amount: -80,
    itemId: 'theme_ocean',
    slot: 'theme',
    catalogVersion: 2,
    occurredAtUtcMs: 4000,
    ...overrides,
  };
  if (!Object.hasOwn(overrides, 'sourceEventId')) {
    payload.sourceEventId = payload.transactionType === 'purchase'
      && payload.catalogVersion === 2
      ? avatarEligibilitySource(payload)
      : null;
  }
  return payload;
}

function avatarEligibilitySource({
  idempotencyKey,
  itemId,
  amount,
  catalogVersion,
  occurredAtUtcMs,
  progressionPolicyVersion = 1,
  requiredAvatarLevel = 3,
  lifetimeXp = 40,
}) {
  const canonical = [
    'avatar-purchase-eligibility-v1',
    idempotencyKey,
    itemId,
    amount,
    catalogVersion,
    progressionPolicyVersion,
    requiredAvatarLevel,
    lifetimeXp,
    occurredAtUtcMs,
  ].join('\0');
  const digest = createHash('sha256').update(canonical).digest('hex');
  return `avatar-xp:v1:p${progressionPolicyVersion}:c${catalogVersion}`
    + `:l${requiredAvatarLevel}:x${lifetimeXp}:${digest}`;
}

function avatarLegacyCarrySource({
  transactionId,
  idempotencyKey,
  transactionType,
  amount,
  itemId,
  catalogVersion,
  occurredAtUtcMs,
}) {
  const canonical = [
    'avatar-legacy-carry-forward-v1',
    transactionId,
    idempotencyKey,
    transactionType,
    amount,
    itemId,
    catalogVersion,
    occurredAtUtcMs,
  ].join('\0');
  const tag = transactionType === 'purchase' ? 'p' : 'e';
  const digest = createHash('sha256').update(canonical).digest('hex');
  return `avatar-legacy:v1:c1:${tag}:${digest}`;
}

const experimentAssignmentAssignedAtUtcMs = 4000;

function fieldExperimentAssignmentPayload(overrides = {}) {
  return {
    assignmentId: 'experiment-assignment:canonical-1',
    ownerId: alice,
    experimentId: 'study-a',
    experimentVersion: 1,
    cohort: 'intervention',
    protocolVersion: 'protocol-1',
    assignedAtUtcMs: experimentAssignmentAssignedAtUtcMs,
    ...overrides,
  };
}

function writeFieldExperimentAssignment(db, {
  uid = alice,
  entityId = 'experiment-assignment:canonical-1',
  operationId = 'experiment-assignment-operation-1',
  schemaVersion = 1,
  clientUpdatedAtUtcMs,
  payload,
} = {}) {
  const resolvedPayload = payload ?? fieldExperimentAssignmentPayload({
    assignmentId: entityId,
    ownerId: uid,
  });
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'field_users', uid, 'experiment_assignments', entityId),
    {
      schemaVersion,
      entityId,
      payload: resolvedPayload,
      revision: 1,
      isDeleted: false,
      clientUpdatedAtUtcMs:
        clientUpdatedAtUtcMs ??
        (Number.isInteger(resolvedPayload.assignedAtUtcMs)
          ? resolvedPayload.assignedAtUtcMs
          : experimentAssignmentAssignedAtUtcMs),
      serverUpdatedAt: serverTimestamp(),
      lastOperationId: operationId,
    },
  );
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType: 'experimentAssignment',
    entityId,
    operationKind: 'upsert',
    baseRevision: 0,
    resultingRevision: 1,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

const assessmentRunStartedAtUtcMs = 5000;
const assessmentRunCompletedAtUtcMs = 6000;
const assessmentRunInstrumentChecksum =
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const assessmentRunFormChecksum =
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const assessmentRunContractIdentities = [
  {
    revision: '1.0.0',
    hash: 'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
  },
  {
    revision: '1.1.0',
    hash: '40e587aa5605d066e67aee81f3254671ea5484beca04dbb41fccbfd3ddb2af27',
  },
  {
    revision: '1.2.0',
    hash: 'c6a772993afa6cc2d78f3eb11687d615192ef6ff52581fa882826180f90afee7',
  },
  {
    revision: '1.3.0',
    hash: '41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4',
  },
];
const assessmentRunContractRevision = '1.3.0';
const assessmentRunContractHash =
  '41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4';

function fieldAssessmentRunPayload(overrides = {}) {
  return {
    runId: 'assessment-run-pre',
    ownerId: alice,
    learningSessionId: 'assessment-session-pre',
    studyCycleId: 'study-cycle-2026',
    phase: 'pre',
    state: 'active',
    protocolId: 'assessment-protocol',
    protocolVersion: 'protocol-1',
    experimentId: 'study-a',
    experimentVersion: 1,
    assignmentId: 'experiment-assignment:assessment-cloud-1',
    cohort: 'intervention',
    consentVersion: 1,
    consentDecidedAtUtcMs: 4500,
    instrumentId: 'instrument-core',
    instrumentVersion: 'instrument-v1',
    formId: 'form-a',
    formVersion: 'form-v1',
    instrumentChecksumSha256: assessmentRunInstrumentChecksum,
    formChecksumSha256: assessmentRunFormChecksum,
    appVersion: '1.0.0',
    buildId: 'task-12-sync',
    databaseSchemaVersion: 15,
    contentRevision: 'assessment-content-v1',
    evidencePolicyVersion: 'learning-evidence-v1',
    featureContractRevision: assessmentRunContractRevision,
    featureContractHash: assessmentRunContractHash,
    startedAtUtcMs: assessmentRunStartedAtUtcMs,
    completedAtUtcMs: null,
    abandonedAtUtcMs: null,
    ...overrides,
  };
}

function writeFieldAssessmentRun(db, {
  uid = alice,
  entityId = 'assessment-run-pre',
  operationId = 'assessmentRun:assessment-run-pre:1',
  schemaVersion = 1,
  operationSchemaVersion = 1,
  revision = 1,
  baseRevision = revision - 1,
  isDeleted = false,
  clientUpdatedAtUtcMs,
  payload,
  entityExtra = {},
  operationExtra = {},
  omitEntityKey,
  omitOperationKey,
} = {}) {
  const resolvedPayload = payload ?? fieldAssessmentRunPayload({
    runId: entityId,
    ownerId: uid,
  });
  const resolvedClientUpdatedAtUtcMs = clientUpdatedAtUtcMs ?? (
    resolvedPayload.completedAtUtcMs ??
    resolvedPayload.abandonedAtUtcMs ??
    resolvedPayload.startedAtUtcMs
  );
  const batch = writeBatch(db);
  const entityDocument = {
    schemaVersion,
    entityId,
    payload: resolvedPayload,
    revision,
    isDeleted,
    clientUpdatedAtUtcMs: resolvedClientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
    ...entityExtra,
  };
  const operationDocument = {
    schemaVersion: operationSchemaVersion,
    operationId,
    entityType: 'assessmentRun',
    entityId,
    operationKind: 'upsert',
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
    ...operationExtra,
  };
  if (omitEntityKey !== undefined) delete entityDocument[omitEntityKey];
  if (omitOperationKey !== undefined) delete operationDocument[omitOperationKey];
  batch.set(
    doc(db, 'field_users', uid, 'assessment_runs', entityId),
    entityDocument,
  );
  batch.set(
    doc(db, 'field_users', uid, 'operations', operationId),
    operationDocument,
  );
  return batch.commit();
}

function writeAssessmentAssignment(db, operationSuffix) {
  const assignmentId = 'experiment-assignment:assessment-cloud-1';
  return writeFieldExperimentAssignment(db, {
    entityId: assignmentId,
    operationId: `experiment-assignment-operation-${operationSuffix}`,
    payload: fieldExperimentAssignmentPayload({
      assignmentId,
      ownerId: alice,
      experimentId: 'study-a',
      experimentVersion: 1,
      cohort: 'intervention',
      protocolVersion: 'protocol-1',
      assignedAtUtcMs: 4600,
    }),
  });
}

async function seedFieldAssessmentRun({
  uid = alice,
  entityId = 'assessment-run-pre',
  revision = 1,
  payload,
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const resolvedPayload = payload ?? fieldAssessmentRunPayload({
      runId: entityId,
      ownerId: uid,
    });
    await setDoc(doc(db, 'field_users', uid, 'assessment_runs', entityId), {
      schemaVersion: 1,
      entityId,
      payload: resolvedPayload,
      revision,
      isDeleted: false,
      clientUpdatedAtUtcMs:
        resolvedPayload.completedAtUtcMs ??
        resolvedPayload.abandonedAtUtcMs ??
        resolvedPayload.startedAtUtcMs,
      serverUpdatedAt: new Date(0),
      lastOperationId: `seed:${entityId}:${revision}`,
    });
  });
}

function fieldSavedLearningItemPayload(overrides = {}) {
  return {
    contentType: 'lexicalMetadata',
    contentId: 'word:station',
    contentRevision: 3,
    savedAtUtcMs: 5000,
    updatedAtUtcMs: 5000,
    isDeleted: false,
    ...overrides,
  };
}

function fieldSavedLearningItemEntityId(payload = fieldSavedLearningItemPayload()) {
  const identity = `${payload.contentType}|${payload.contentId}|${payload.contentRevision}`;
  return `saved-learning-item:${createHash('sha256').update(identity, 'utf8').digest('hex')}`;
}

function writeFieldSavedLearningItem(db, {
  uid = alice,
  payload = fieldSavedLearningItemPayload(),
  entityId = fieldSavedLearningItemEntityId(payload),
  operationId = 'saved-operation-1',
  revision = 1,
  baseRevision = 0,
  schemaVersion = 1,
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'saved_learning_items', entityId), {
    schemaVersion,
    entityId,
    payload,
    revision,
    isDeleted: payload.isDeleted,
    clientUpdatedAtUtcMs: payload.updatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType: 'savedLearningItem',
    entityId,
    operationKind: payload.isDeleted ? 'delete' : 'upsert',
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function fieldContentQualityReportPayload(overrides = {}) {
  return {
    reportId: 'report:station:audio',
    contentType: 'lexicalMetadata',
    contentId: 'word:station',
    contentRevision: 3,
    reasonCode: 'audio',
    comment: 'Pronunciation is unclear',
    submittedAtUtcMs: 7000,
    isDeleted: false,
    ...overrides,
  };
}

function fieldContentQualityReportEntityId(
  payload = fieldContentQualityReportPayload(),
) {
  return `content-quality-report:${createHash('sha256')
    .update(payload.reportId, 'utf8').digest('hex')}`;
}

function fieldContentQualityReportOperationId(
  payload = fieldContentQualityReportPayload(),
) {
  const entityId = fieldContentQualityReportEntityId(payload);
  const identity = `v1|${entityId}|${payload.submittedAtUtcMs}`;
  return `content-quality-operation:${createHash('sha256')
    .update(identity, 'utf8').digest('hex')}`;
}

function writeFieldContentQualityReport(db, {
  uid = alice,
  payload = fieldContentQualityReportPayload(),
  entityId = fieldContentQualityReportEntityId(payload),
  operationId = fieldContentQualityReportOperationId(payload),
  revision = 1,
  baseRevision = 0,
  schemaVersion = 1,
  clientUpdatedAtUtcMs = payload.submittedAtUtcMs,
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'content_quality_reports', entityId), {
    schemaVersion,
    entityId,
    payload,
    revision,
    isDeleted: payload.isDeleted,
    clientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType: 'contentQualityReport',
    entityId,
    operationKind: payload.isDeleted ? 'delete' : 'upsert',
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function fieldLearningTimePayload(overrides = {}) {
  const payload = {
    sessionId: 'session:meaning-quiz:1',
    activeStartOffsetMs: 0,
    activeDurationMs: 30000,
    startedAtUtcMs: 9000,
    // A wall-clock rollback is valid; monotonic duration remains authoritative.
    endedAtUtcMs: 8000,
    timezoneId: 'Asia/Bangkok',
    timezoneOffsetMinutes: 420,
    captureSource: 'automaticLesson',
    ...overrides,
  };
  const identity = `v1|${payload.sessionId}|${payload.activeStartOffsetMs}|${payload.captureSource}`;
  return {
    segmentId: `learning-time-segment:${createHash('sha256')
      .update(identity, 'utf8').digest('hex')}`,
    ...payload,
  };
}

function fieldLearningTimeOperationId(entityId) {
  return `learning-time-operation:${createHash('sha256')
    .update(`v1|${entityId}`, 'utf8').digest('hex')}`;
}

function writeFieldLearningTime(db, {
  uid = alice,
  payload = fieldLearningTimePayload(),
  entityId = payload.segmentId,
  operationId = fieldLearningTimeOperationId(entityId),
  revision = 1,
  baseRevision = 0,
  schemaVersion = 1,
  clientUpdatedAtUtcMs = payload.endedAtUtcMs,
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'learning_time_segments', entityId), {
    schemaVersion,
    entityId,
    payload,
    revision,
    isDeleted: false,
    clientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion,
    operationId,
    entityType: 'learningTimeSegment',
    entityId,
    operationKind: 'upsert',
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function fieldLearningGoalPayload(overrides = {}) {
  return {
    goalId: 'goal:ielts',
    kind: 'languageTest',
    title: 'IELTS practice target',
    deadlineAtUtcMs: 1788238800000,
    timezoneId: 'Asia/Bangkok',
    timezoneOffsetMinutes: 420,
    status: 'active',
    createdAtUtcMs: 1787616000000,
    updatedAtUtcMs: 1787616000000,
    isDeleted: false,
    ...overrides,
  };
}

function writeFieldLearningGoal(db, {
  uid = alice,
  payload = fieldLearningGoalPayload(),
  entityId = payload.goalId,
  operationId = `learningGoal:${entityId}:1`,
  revision = 1,
  baseRevision = 0,
  operationKind = payload.isDeleted ? 'delete' : 'upsert',
  clientUpdatedAtUtcMs = payload.updatedAtUtcMs,
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'learning_goals', entityId), {
    schemaVersion: 1,
    entityId,
    payload,
    revision,
    isDeleted: payload.isDeleted,
    clientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion: 1,
    operationId,
    entityType: 'learningGoal',
    entityId,
    operationKind,
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

function fieldLearnerPreferencePayload({
  preferenceVersion = 2,
  homeExperience = 'standard',
  ...overrides
} = {}) {
  return {
    ownerId: alice,
    preferenceVersion,
    goal: 'examPreparation',
    availableMinutesPerDay: 45,
    activityPreference: 'quiz',
    ...(preferenceVersion === 2 ? { homeExperience } : {}),
    updatedAtUtcMs: 1788048000000,
    ...overrides,
  };
}

function fieldLearnerPreferenceOperationId(
  payload,
  baseRevision,
  resultingRevision,
) {
  const identity = [
    `v${payload.preferenceVersion}`,
    payload.preferenceVersion,
    payload.goal,
    payload.availableMinutesPerDay,
    payload.activityPreference,
    ...(payload.preferenceVersion === 2 ? [payload.homeExperience] : []),
    payload.updatedAtUtcMs,
    baseRevision,
    resultingRevision,
  ].join('|');
  return `learner-preference-operation:v${payload.preferenceVersion}:${createHash('sha256')
    .update(identity, 'utf8').digest('hex')}`;
}

function writeFieldLearnerPreference(db, {
  uid = alice,
  payload = fieldLearnerPreferencePayload({ ownerId: uid }),
  entityId = 'current',
  operationId,
  revision = 1,
  baseRevision = 0,
  clientUpdatedAtUtcMs = payload.updatedAtUtcMs,
} = {}) {
  const resolvedOperationId = operationId ??
    fieldLearnerPreferenceOperationId(payload, baseRevision, revision);
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'learner_preferences', entityId), {
    schemaVersion: payload.preferenceVersion,
    entityId,
    payload,
    revision,
    isDeleted: false,
    clientUpdatedAtUtcMs,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: resolvedOperationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', resolvedOperationId), {
    schemaVersion: payload.preferenceVersion,
    operationId: resolvedOperationId,
    entityType: 'learnerPreference',
    entityId,
    operationKind: 'upsert',
    baseRevision,
    resultingRevision: revision,
    acknowledgedAt: serverTimestamp(),
  });
  return batch.commit();
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'firestore.rules'),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv?.cleanup();
});

describe('purchased_items transaction integrity', () => {
  it('denies minting an item without atomically debiting points', async () => {
    await seedStateAndProduct();
    const db = authDb();

    await assertFails(
      setDoc(doc(db, 'purchased_items', purchaseId), purchaseData()),
    );
  });

  it('denies a purchase whose submitted price differs from the catalog', async () => {
    await seedStateAndProduct();
    const db = authDb();
    const batch = writeBatch(db);
    batch.update(doc(db, 'state', alice), { totalPoints: 99 });
    batch.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(1),
    );

    await assertFails(batch.commit());
  });

  it('allows one purchase with the exact catalog price and atomic debit', async () => {
    await seedStateAndProduct();
    const db = authDb();
    const batch = writeBatch(db);
    batch.update(doc(db, 'state', alice), { totalPoints: 50 });
    batch.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(),
    );

    await assertSucceeds(batch.commit());
    const state = await assertSucceeds(getDoc(doc(db, 'state', alice)));
    const purchase = await assertSucceeds(
      getDoc(doc(db, 'purchased_items', purchaseId)),
    );
    if (state.data().totalPoints !== 50 || purchase.data().total_price !== 50) {
      throw new Error('The committed purchase does not match the expected debit.');
    }
  });

  it('denies a second purchase of the same product', async () => {
    await seedStateAndProduct();
    const db = authDb();
    const first = writeBatch(db);
    first.update(doc(db, 'state', alice), { totalPoints: 50 });
    first.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(),
    );
    await assertSucceeds(first.commit());

    const second = writeBatch(db);
    second.update(doc(db, 'state', alice), { totalPoints: 0 });
    second.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(),
    );
    await assertFails(second.commit());
  });
});

describe('voice_telemetry_events telemetry contract', () => {
  function failedTelemetryToMap() {
    return {
      schemaVersion: 'voice_telemetry_v1',
      outcome: 'failed',
      mode: 'practice',
      requestedEngine: 'omniVoice',
      actualEngine: null,
      usedFallback: false,
      fallbackReason: null,
      failureCategory: 'network',
      cacheHit: false,
      latencyMs: 5000,
      contentId: 'word-2',
      contentType: 'vocabulary',
      requestId: null,
      modelVersion: null,
      occurredAtUtc: '2026-07-24T10:00:00.000Z',
    };
  }

  function validTelemetryToMap() {
    return {
      schemaVersion: 'voice_telemetry_v1',
      outcome: 'succeeded',
      mode: 'practice',
      requestedEngine: 'omniVoice',
      actualEngine: 'omniVoice',
      usedFallback: false,
      fallbackReason: 'flutterSdk',
      failureCategory: 'network',
      cacheHit: true,
      latencyMs: 120,
      contentId: 'word-1',
      contentType: 'vocabulary',
      requestId: 'req-999',
      modelVersion: '0.2.1',
      occurredAtUtc: '2026-07-24T10:00:00.000Z',
    };
  }

  const telemetryPath = 'voice_telemetry_events';

  it('allows creating the exact toMap() shape with nullable keys present as null', async () => {
    const db = authDb();
    await assertSucceeds(
      setDoc(doc(db, telemetryPath, 'evt_nulls'), failedTelemetryToMap()),
    );
  });

  it('keeps a valid telemetry event create-only (read/update/delete denied)', async () => {
    const db = authDb();
    const ref = doc(db, telemetryPath, 'evt_valid');
    await assertSucceeds(setDoc(ref, validTelemetryToMap()));

    await assertFails(getDoc(ref));
    await assertFails(updateDoc(ref, { latencyMs: 999 }));
    await assertFails(deleteDoc(ref));
  });

  it('denies creating a telemetry event with an extra field', async () => {
    const db = authDb();
    const payload = { ...validTelemetryToMap(), audioBytes: 'secret' };
    await assertFails(setDoc(doc(db, telemetryPath, 'evt_extra'), payload));
  });
});

describe('anonymous user isolation & cross-account integrity contract', () => {
  it('denies anonymous user from creating telemetry events or writing to shared collections', async () => {
    const anonDb = authDb('anon_123', true);
    await assertFails(
      setDoc(doc(anonDb, 'voice_telemetry_events', 'evt_anon'), {
        schemaVersion: 'voice_telemetry_v1',
        outcome: 'failed',
        mode: 'practice',
        requestedEngine: 'omniVoice',
        actualEngine: null,
        usedFallback: false,
        fallbackReason: null,
        failureCategory: 'network',
        cacheHit: false,
        latencyMs: 100,
        contentId: 'w-1',
        contentType: 'vocabulary',
        requestId: null,
        modelVersion: null,
        occurredAtUtc: '2026-07-24T10:00:00.000Z',
      }),
    );
  });

  it('denies user from writing to another user\'s state document', async () => {
    const db = authDb('bob_uid');
    await assertFails(
      setDoc(doc(db, 'state', alice), {
        totalPoints: 99999,
      }),
    );
  });
});

describe('field sync ownership and atomic revision contract', () => {
  it('allows registered and anonymous owners to atomically create their own entity', async () => {
    const registeredDb = authDb();
    await assertSucceeds(writeFieldCategory(registeredDb));

    const anonymousDb = authDb('anon_field', true);
    await assertSucceeds(
      writeFieldCategory(anonymousDb, {
        uid: 'anon_field',
        entityId: 'category-anon',
        operationId: 'operation-anon',
      }),
    );
  });

  it('denies cross-user reads and writes', async () => {
    await assertSucceeds(writeFieldCategory(authDb()));
    const bobDb = authDb(bob);

    await assertFails(
      getDoc(doc(bobDb, 'field_users', alice, 'categories', 'category-1')),
    );
    await assertFails(
      writeFieldCategory(bobDb, {
        uid: alice,
        entityId: 'category-by-bob',
        operationId: 'operation-by-bob',
      }),
    );
  });

  it('denies an entity write without its immutable operation acknowledgement', async () => {
    const db = authDb();
    await assertFails(
      setDoc(
        doc(db, 'field_users', alice, 'categories', 'category-1'),
        fieldCategoryData(),
      ),
    );
  });

  it('denies extra entity fields and a mismatched document id', async () => {
    const db = authDb();
    const extra = writeBatch(db);
    extra.set(
      doc(db, 'field_users', alice, 'categories', 'category-extra'),
      {
        ...fieldCategoryData({
          entityId: 'category-extra',
          operationId: 'operation-extra',
        }),
        leakedField: 'not allowed',
      },
    );
    extra.set(
      doc(db, 'field_users', alice, 'operations', 'operation-extra'),
      fieldOperationData({
        entityId: 'category-extra',
        operationId: 'operation-extra',
      }),
    );
    await assertFails(extra.commit());

    const mismatch = writeBatch(db);
    mismatch.set(
      doc(db, 'field_users', alice, 'categories', 'category-path'),
      fieldCategoryData({
        entityId: 'different',
        operationId: 'operation-mismatch',
      }),
    );
    mismatch.set(
      doc(db, 'field_users', alice, 'operations', 'operation-mismatch'),
      fieldOperationData({
        entityId: 'different',
        operationId: 'operation-mismatch',
      }),
    );
    await assertFails(mismatch.commit());
  });

  it('requires the exact current base revision and advancing result', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldCategory(db));

    await assertFails(
      writeFieldCategory(db, {
        operationId: 'operation-stale',
        baseRevision: 0,
        revision: 2,
        resultingRevision: 2,
      }),
    );
    await assertSucceeds(
      writeFieldCategory(db, {
        operationId: 'operation-2',
        baseRevision: 1,
        revision: 2,
        resultingRevision: 2,
      }),
    );
  });

  it('keeps operation acknowledgements immutable', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldCategory(db));
    await assertFails(
      updateDoc(
        doc(db, 'field_users', alice, 'operations', 'operation-1'),
        { resultingRevision: 999 },
      ),
    );
    await assertFails(
      deleteDoc(doc(db, 'field_users', alice, 'operations', 'operation-1')),
    );
  });

  it('requires each synchronized word to reference an existing cloud category', async () => {
    const db = authDb();
    await assertFails(writeFieldWord(db));
    await assertSucceeds(writeFieldCategory(db));
    await assertSucceeds(writeFieldWord(db));
  });

  it('keeps legacy vocabulary readable and rejects valid v2 before rules rollout', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldCategory(db));
    await assertSucceeds(writeFieldWord(db));
    await assertSucceeds(
      getDoc(doc(db, 'field_users', alice, 'words', 'word-1')),
    );
    await assertFails(
      writeFieldWord(db, {
        entityId: 'word-v2',
        operationId: 'word-v2-operation',
        schemaVersion: 2,
        payload: {
          categoryId: 'category-1',
          spelling: 'platform',
          normalizedSpelling: 'platform',
          meaning: 'ชานชาลา',
          normalizedMeaning: 'ชานชาลา',
          partOfSpeech: 'noun',
          cefrLevel: 'A2',
          source: 'manual',
          isGlobal: false,
          isDeleted: false,
          createdAtUtcMs: 3000,
          updatedAtUtcMs: 3000,
          contentRevision: 1,
          contentChecksumSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          contentProvenance: 'userAuthored',
          contentReviewState: 'unreviewed',
          contentPublicationState: 'private',
        },
      }),
    );
  });

  it('accepts immutable attempt and reading evidence with atomic acknowledgements', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearningEvent(db));
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'reading_events',
        entityType: 'readingEvent',
        entityId: 'reading-1',
        operationId: 'reading-operation-1',
        payload: {
          documentId: 'article-1',
          documentRevision: 1,
          eventType: 'completed',
          position: 6,
          occurredAtUtcMs: 3000,
        },
      }),
    );
  });

  it('accepts the exact AnswerAttempt payload v2 evidence context', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2',
        operationId: 'attempt-v2-operation',
        schemaVersion: 2,
        payload: fieldAttemptV2Payload(),
      }),
    );
  });

  it('rejects an otherwise-valid legacy-inferred AnswerAttempt v2', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-legacy-inferred-v2',
        operationId: 'attempt-legacy-inferred-v2-operation',
        schemaVersion: 2,
        payload: fieldAttemptV2Payload(fieldLegacyEvidenceContext()),
      }),
    );
  });

  it('rejects payload v2 for every legacy-v1-only sync collection', async () => {
    const db = authDb();
    const legacyCollections = [
      ['categories', 'category'],
      ['reading_events', 'readingEvent'],
      ['reward_transactions', 'rewardTransaction'],
      ['srs_states', 'srsState'],
      ['achievement_unlocks', 'achievementUnlock'],
      ['experiment_assignments', 'experimentAssignment'],
      ['assessment_runs', 'assessmentRun'],
    ];
    for (const [collection, entityType] of legacyCollections) {
      await assertFails(
        writeFieldLearningEvent(db, {
          collection,
          entityType,
          entityId: `${collection}-v2`,
          operationId: `${collection}-v2-operation`,
          schemaVersion: 2,
          payload: {},
        }),
      );
    }
  });

  it('rejects AnswerAttempt v2 unknown keys and class mismatch', async () => {
    const db = authDb();
    const extraContext = fieldEvidenceContext({ leakedField: 'not allowed' });
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2-extra-context',
        operationId: 'attempt-v2-extra-context-operation',
        schemaVersion: 2,
        payload: fieldAttemptV2Payload(extraContext),
      }),
    );
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2-extra-payload',
        operationId: 'attempt-v2-extra-payload-operation',
        schemaVersion: 2,
        payload: { ...fieldAttemptV2Payload(), rawAudio: 'not allowed' },
      }),
    );
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2-class-mismatch',
        operationId: 'attempt-v2-class-mismatch-operation',
        schemaVersion: 2,
        payload: {
          ...fieldAttemptV2Payload(),
          evidenceClass: 'recognition',
        },
      }),
    );
  });

  it('rejects missing keys from either exact AnswerAttempt v2 schema', async () => {
    const db = authDb();
    const missingPayloadKey = fieldAttemptV2Payload();
    delete missingPayloadKey.providerProvenance;
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2-missing-payload-key',
        operationId: 'attempt-v2-missing-payload-key-operation',
        schemaVersion: 2,
        payload: missingPayloadKey,
      }),
    );

    const missingContextKey = fieldEvidenceContext();
    delete missingContextKey.formId;
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-v2-missing-context-key',
        operationId: 'attempt-v2-missing-context-key-operation',
        schemaVersion: 2,
        payload: fieldAttemptV2Payload(missingContextKey),
      }),
    );
  });

  it('rejects AnswerAttempt v2 invalid enums and oversized context fields', async () => {
    const db = authDb();
    const invalidContexts = [
      fieldEvidenceContext({ evidenceClass: 'unknown' }),
      fieldEvidenceContext({ classificationSource: 'guessed' }),
      fieldEvidenceContext({ rolloutMode: 'active' }),
      fieldEvidenceContext({ skillId: 'x'.repeat(257) }),
      fieldEvidenceContext({ protocolId: 'x'.repeat(257) }),
    ];
    for (let index = 0; index < invalidContexts.length; index += 1) {
      await assertFails(
        writeFieldLearningEvent(db, {
          entityId: `attempt-v2-invalid-${index}`,
          operationId: `attempt-v2-invalid-${index}-operation`,
          schemaVersion: 2,
          payload: fieldAttemptV2Payload(invalidContexts[index]),
        }),
      );
    }
  });

  it('rejects mismatched AnswerAttempt entity and operation schema versions', async () => {
    const db = authDb();
    const batch = writeBatch(db);
    batch.set(doc(db, 'field_users', alice, 'attempts', 'attempt-v2-mismatch'), {
      schemaVersion: 2,
      entityId: 'attempt-v2-mismatch',
      payload: fieldAttemptV2Payload(),
      revision: 1,
      isDeleted: false,
      clientUpdatedAtUtcMs: 2000,
      serverUpdatedAt: serverTimestamp(),
      lastOperationId: 'attempt-v2-mismatch-operation',
    });
    batch.set(
      doc(
        db,
        'field_users',
        alice,
        'operations',
        'attempt-v2-mismatch-operation',
      ),
      {
        schemaVersion: 1,
        operationId: 'attempt-v2-mismatch-operation',
        entityType: 'attempt',
        entityId: 'attempt-v2-mismatch',
        operationKind: 'upsert',
        baseRevision: 0,
        resultingRevision: 1,
        acknowledgedAt: serverTimestamp(),
      },
    );

    await assertFails(batch.commit());
  });

  it('keeps learning evidence create-only and owner-isolated', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearningEvent(db));
    const ref = doc(db, 'field_users', alice, 'attempts', 'attempt-1');
    await assertFails(updateDoc(ref, { 'payload.isCorrect': false }));
    await assertFails(deleteDoc(ref));
    await assertFails(getDoc(doc(authDb(bob), 'field_users', alice, 'attempts', 'attempt-1')));
  });

  it('accepts catalog-bound reward purchases and equipment as immutable events', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldRewardTransaction(db));
    await assertSucceeds(
      writeFieldRewardTransaction(db, {
        entityId: 'reward-equip-1',
        operationId: 'reward-equip-operation-1',
        payload: {
          idempotencyKey: 'equip-reward-1',
          transactionType: 'equip',
          amount: 0,
          itemId: 'theme_ocean',
          slot: 'theme',
          catalogVersion: 2,
          sourceEventId: null,
          occurredAtUtcMs: 5000,
        },
      }),
    );
    const ref = doc(
      db,
      'field_users',
      alice,
      'reward_transactions',
      'reward-1',
    );
    await assertFails(updateDoc(ref, { 'payload.amount': 0 }));
    await assertFails(deleteDoc(ref));
  });

  it('accepts exactly the four canonical reward transaction shapes', async () => {
    const db = authDb();
    const payloads = [
      fieldRewardPayload({
        idempotencyKey: 'purchase-canonical',
        occurredAtUtcMs: 4100,
      }),
      fieldRewardPayload({
        idempotencyKey: 'equip-canonical',
        transactionType: 'equip',
        amount: 0,
        occurredAtUtcMs: 4200,
      }),
      fieldRewardPayload({
        idempotencyKey: 'legacy-backfill-canonical',
        transactionType: 'legacyEarningBackfill',
        amount: 5,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'legacy-attempt-1',
        occurredAtUtcMs: 4300,
      }),
      fieldRewardPayload({
        idempotencyKey: 'coin-grant-canonical',
        transactionType: 'coinGrant',
        amount: 1,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'learning-attempt-1',
        occurredAtUtcMs: 4400,
      }),
    ];

    for (const [index, payload] of payloads.entries()) {
      await assertSucceeds(
        writeFieldRewardTransaction(db, {
          entityId: `reward-canonical-${index}`,
          operationId: `reward-canonical-operation-${index}`,
          payload,
        }),
      );
    }
  });

  it('admits raw catalog-v1 only inside the server-time migration window', async () => {
    const db = authDb();
    const beforeRequestTime = Math.min(Date.now() - 60_000, 1790812799999);
    await assertSucceeds(
      writeFieldRewardTransaction(db, {
        entityId: 'reward-legacy-v1-pre-cutover',
        operationId: 'reward-legacy-v1-pre-cutover-operation',
        payload: fieldRewardPayload({
          idempotencyKey: 'legacy-v1-pre-cutover',
          catalogVersion: 1,
          sourceEventId: null,
          occurredAtUtcMs: beforeRequestTime,
        }),
      }),
    );
    await assertFails(
      writeFieldRewardTransaction(db, {
        entityId: 'reward-legacy-v1-post-cutover',
        operationId: 'reward-legacy-v1-post-cutover-operation',
        payload: fieldRewardPayload({
          idempotencyKey: 'legacy-v1-post-cutover',
          catalogVersion: 1,
          sourceEventId: null,
          occurredAtUtcMs: 1790812800000,
        }),
      }),
    );
  });

  it('allows exact marker-attested catalog-v1 carry-forward rows', async () => {
    const db = authDb();
    const beforeRequestTime = Math.min(Date.now() - 60_000, 1790812799000);
    const purchaseId = 'reward-legacy-carry-purchase';
    const purchase = fieldRewardPayload({
      idempotencyKey: 'legacy-carry-purchase',
      catalogVersion: 1,
      sourceEventId: null,
      occurredAtUtcMs: beforeRequestTime,
    });
    purchase.sourceEventId = avatarLegacyCarrySource({
      transactionId: purchaseId,
      ...purchase,
    });
    await assertSucceeds(
      writeFieldRewardTransaction(db, {
        entityId: purchaseId,
        operationId: 'reward-legacy-carry-purchase-operation',
        payload: purchase,
      }),
    );

    const equipId = 'reward-legacy-carry-equip';
    const equip = fieldRewardPayload({
      idempotencyKey: 'legacy-carry-equip',
      transactionType: 'equip',
      amount: 0,
      catalogVersion: 1,
      sourceEventId: null,
      occurredAtUtcMs: beforeRequestTime + 1,
    });
    equip.sourceEventId = avatarLegacyCarrySource({
      transactionId: equipId,
      ...equip,
    });
    await assertSucceeds(
      writeFieldRewardTransaction(db, {
        entityId: equipId,
        operationId: 'reward-legacy-carry-equip-operation',
        payload: equip,
      }),
    );

    const clockAheadId = 'reward-clock-ahead-legacy-carry-purchase';
    const clockAhead = fieldRewardPayload({
      idempotencyKey: 'clock-ahead-legacy-carry-purchase',
      catalogVersion: 1,
      sourceEventId: null,
      occurredAtUtcMs: Math.min(Date.now() + 86_400_000, 1790812799999),
    });
    clockAhead.sourceEventId = avatarLegacyCarrySource({
      transactionId: clockAheadId,
      ...clockAhead,
    });
    await assertFails(
      writeFieldRewardTransaction(db, {
        entityId: clockAheadId,
        operationId: 'reward-clock-ahead-legacy-carry-operation',
        payload: clockAhead,
      }),
    );

    const lateId = 'reward-late-legacy-carry-purchase';
    const late = fieldRewardPayload({
      idempotencyKey: 'late-legacy-carry-purchase',
      catalogVersion: 1,
      sourceEventId: null,
      occurredAtUtcMs: 1790812800000,
    });
    late.sourceEventId = avatarLegacyCarrySource({
      transactionId: lateId,
      ...late,
    });
    await assertFails(
      writeFieldRewardTransaction(db, {
        entityId: lateId,
        operationId: 'reward-late-legacy-carry-purchase-operation',
        payload: late,
      }),
    );
  });

  it('rejects reward payloads without exact keys and primitive types', async () => {
    const db = authDb();
    const canonical = fieldRewardPayload({ occurredAtUtcMs: 4500 });
    const { slot: omittedSlot, ...missingSlot } = canonical;
    const invalidPayloads = [
      missingSlot,
      { ...canonical, unexpected: true },
      { ...canonical, idempotencyKey: 1 },
      { ...canonical, transactionType: null },
      { ...canonical, amount: '-80' },
      { ...canonical, itemId: 80 },
      { ...canonical, slot: false },
      { ...canonical, catalogVersion: '2' },
      { ...canonical, sourceEventId: 1 },
      { ...canonical, occurredAtUtcMs: 4500.5 },
    ];
    void omittedSlot;

    for (const [index, payload] of invalidPayloads.entries()) {
      await assertFails(
        writeFieldRewardTransaction(db, {
          entityId: `reward-invalid-shape-${index}`,
          operationId: `reward-invalid-shape-operation-${index}`,
          payload,
        }),
      );
    }
  });

  it('rejects noncanonical reward type-specific semantics', async () => {
    const db = authDb();
    const grant = (transactionType, overrides = {}) => fieldRewardPayload({
      idempotencyKey: `${transactionType}-invalid`,
      transactionType,
      amount: 1,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: `${transactionType}-source`,
      occurredAtUtcMs: 4600,
      ...overrides,
    });
    const invalidPayloads = [
      fieldRewardPayload({ transactionType: 'unknown' }),
      grant('legacyEarningBackfill', { amount: 0 }),
      grant('coinGrant', { amount: -1 }),
      fieldRewardPayload({ amount: 0 }),
      fieldRewardPayload({ transactionType: 'equip', amount: -80 }),
      grant('legacyEarningBackfill', {
        itemId: 'theme_ocean',
        slot: 'theme',
      }),
      grant('coinGrant', { slot: 'theme' }),
      grant('coinGrant', { catalogVersion: 1 }),
      grant('legacyEarningBackfill', { sourceEventId: null }),
      grant('coinGrant', { sourceEventId: '' }),
      grant('coinGrant', { sourceEventId: ' leading-space' }),
      fieldRewardPayload({ sourceEventId: 'forged-purchase-source' }),
      fieldRewardPayload({ catalogVersion: 0 }),
      fieldRewardPayload({
        sourceEventId: fieldRewardPayload().sourceEventId.replace(':l3:', ':l2:'),
      }),
      fieldRewardPayload({
        sourceEventId: fieldRewardPayload().sourceEventId.replace(':x40:', ':x39:'),
      }),
      fieldRewardPayload({
        catalogVersion: 1,
        sourceEventId: null,
        occurredAtUtcMs: 1790812800000,
      }),
      fieldRewardPayload({
        itemId: 'theme_default',
        amount: 0,
      }),
      fieldRewardPayload({ idempotencyKey: ' trailing-space' }),
    ];

    for (const [index, payload] of invalidPayloads.entries()) {
      await assertFails(
        writeFieldRewardTransaction(db, {
          entityId: `reward-invalid-semantics-${index}`,
          operationId: `reward-invalid-semantics-operation-${index}`,
          payload,
        }),
      );
    }
  });

  it('binds reward occurrence time to the entity update time', async () => {
    await assertFails(
      writeFieldRewardTransaction(authDb(), {
        entityId: 'reward-time-mismatch',
        operationId: 'reward-time-mismatch-operation',
        clientUpdatedAtUtcMs: 4701,
        payload: fieldRewardPayload({ occurredAtUtcMs: 4700 }),
      }),
    );
  });

  it('rejects reward transactions with a client-invented price or slot', async () => {
    const db = authDb();
    await assertFails(
      writeFieldRewardTransaction(db, {
        entityId: 'reward-price',
        operationId: 'reward-price-operation',
        payload: {
          idempotencyKey: 'bad-price',
          transactionType: 'purchase',
          amount: -1,
          itemId: 'theme_ocean',
          slot: 'theme',
          catalogVersion: 2,
          sourceEventId: null,
          occurredAtUtcMs: 4000,
        },
      }),
    );
    await assertFails(
      writeFieldRewardTransaction(db, {
        entityId: 'reward-slot',
        operationId: 'reward-slot-operation',
        payload: {
          idempotencyKey: 'bad-slot',
          transactionType: 'equip',
          amount: 0,
          itemId: 'theme_ocean',
          slot: 'weapon',
          catalogVersion: 2,
          sourceEventId: null,
          occurredAtUtcMs: 4000,
        },
      }),
    );
  });

  it('accepts documented attempt number and response-time boundaries', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-boundary',
        operationId: 'attempt-boundary-operation',
        payload: {
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2147483647,
          attemptNumber: 1000000,
          occurredAtUtcMs: 2000,
          providerProvenance: null,
        },
      }),
    );
  });

  it('rejects a negative response time', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-negative-response',
        operationId: 'attempt-negative-response-operation',
        payload: {
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: -1,
          attemptNumber: 1,
          occurredAtUtcMs: 2000,
          providerProvenance: null,
        },
      }),
    );
  });

  it('rejects an oversized prompt mode', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-long-prompt',
        operationId: 'attempt-long-prompt-operation',
        payload: {
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'x'.repeat(61),
          isCorrect: true,
          responseTimeMs: 10,
          attemptNumber: 1,
          occurredAtUtcMs: 2000,
          providerProvenance: null,
        },
      }),
    );
  });

  it('rejects extra learning evidence fields', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-extra',
        operationId: 'attempt-extra-operation',
        payload: {
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 10,
          attemptNumber: 1,
          occurredAtUtcMs: 2000,
          providerProvenance: null,
          rawAudio: 'must-not-sync',
        },
      }),
    );
  });

  it('allows policy reads but denies client policy writes', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'app_control', 'field'), {
        schemaVersion: 1,
        cloudSyncEnabled: true,
      });
    });
    const db = authDb();
    await assertSucceeds(getDoc(doc(db, 'app_control', 'field')));
    await assertFails(
      setDoc(doc(db, 'app_control', 'field'), {
        schemaVersion: 1,
        cloudSyncEnabled: false,
      }),
    );
  });

  it('accepts immutable srs_states mirroring per-word review state', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'srs_states',
        entityType: 'srsState',
        entityId: 'word-1',
        operationId: 'srs-operation-1',
        payload: {
          wordId: 'word-1',
          stability: 2.5,
          difficulty: 0.3,
          intervalDays: 7,
          repetitions: 3,
          lapses: 1,
          lastReviewAtUtcMs: 4000,
          dueAtUtcMs: 100000,
          algorithmVersion: 1,
        },
      }),
    );
  });

  it('accepts learner attempt and SRS for packaged word without uploading a user word document', async () => {
    const db = authDb();
    const wordId = 'word:starter-book';
    const packagedWord = await getDoc(
      doc(db, 'field_users', alice, 'words', wordId),
    );
    if (packagedWord.exists()) {
      throw new Error('packaged starter word must not be uploaded as user data');
    }
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        entityId: 'attempt-packaged-word',
        operationId: 'attempt-packaged-word-operation',
        payload: {
          sessionId: 'session-packaged-word',
          wordId,
          promptMode: 'typedRecall',
          isCorrect: true,
          responseTimeMs: 250,
          attemptNumber: 1,
          occurredAtUtcMs: 2000,
          providerProvenance: 'keyboard|local|v1',
        },
      }),
    );
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'srs_states',
        entityType: 'srsState',
        entityId: wordId,
        operationId: 'srs-packaged-word-operation',
        payload: {
          wordId,
          stability: 2.5,
          difficulty: 0.3,
          intervalDays: 7,
          repetitions: 3,
          lapses: 1,
          lastReviewAtUtcMs: 4000,
          dueAtUtcMs: 100000,
          algorithmVersion: 1,
        },
      }),
    );
    await assertSucceeds(
      getDoc(doc(db, 'field_users', alice, 'attempts', 'attempt-packaged-word')),
    );
    await assertSucceeds(
      getDoc(doc(db, 'field_users', alice, 'srs_states', wordId)),
    );
    await assertFails(
      getDoc(doc(authDb(bob), 'field_users', alice, 'attempts', 'attempt-packaged-word')),
    );
    await assertFails(
      getDoc(doc(authDb(bob), 'field_users', alice, 'srs_states', wordId)),
    );
  });

  it('keeps srs_states create-only and owner-isolated', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'srs_states',
        entityType: 'srsState',
        entityId: 'word-2',
        operationId: 'srs-operation-2',
        payload: {
          wordId: 'word-2',
          stability: 1.0,
          difficulty: 0.5,
          intervalDays: 1,
          repetitions: 1,
          lapses: 0,
          lastReviewAtUtcMs: null,
          dueAtUtcMs: 5000,
          algorithmVersion: 1,
        },
      }),
    );
    const ref = doc(db, 'field_users', alice, 'srs_states', 'word-2');
    await assertFails(updateDoc(ref, { 'payload.intervalDays': 99 }));
    await assertFails(deleteDoc(ref));
    await assertFails(
      getDoc(doc(authDb(bob), 'field_users', alice, 'srs_states', 'word-2')),
    );
  });

  it('rejects srs_states with extra payload keys', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        collection: 'srs_states',
        entityType: 'srsState',
        entityId: 'word-3',
        operationId: 'srs-operation-3',
        payload: {
          wordId: 'word-3',
          stability: 1.0,
          difficulty: 0.5,
          intervalDays: 1,
          repetitions: 1,
          lapses: 0,
          lastReviewAtUtcMs: null,
          dueAtUtcMs: 5000,
          algorithmVersion: 1,
          evilExtraField: 'must-be-rejected',
        },
      }),
    );
  });

  it('accepts immutable achievement_unlocks ledger entries', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'achievement_unlocks',
        entityType: 'achievementUnlock',
        entityId: 'unlock-1',
        operationId: 'unlock-operation-1',
        payload: {
          achievementId: 'streak-7',
          definitionVersion: 1,
          sourceEventId: 'attempt-1',
          unlockedAtUtcMs: 6000,
        },
      }),
    );
  });

  it('keeps achievement_unlocks create-only and owner-isolated', async () => {
    const db = authDb();
    await assertSucceeds(
      writeFieldLearningEvent(db, {
        collection: 'achievement_unlocks',
        entityType: 'achievementUnlock',
        entityId: 'unlock-1',
        operationId: 'unlock-operation-1',
        payload: {
          achievementId: 'streak-7',
          definitionVersion: 1,
          sourceEventId: 'attempt-1',
          unlockedAtUtcMs: 6000,
        },
      }),
    );
    const ref = doc(db, 'field_users', alice, 'achievement_unlocks', 'unlock-1');
    await assertFails(updateDoc(ref, { 'payload.definitionVersion': 2 }));
    await assertFails(deleteDoc(ref));
    await assertFails(
      getDoc(
        doc(authDb(bob), 'field_users', alice, 'achievement_unlocks', 'unlock-1'),
      ),
    );
  });

  it('rejects achievement_unlocks with missing sourceEventId', async () => {
    const db = authDb();
    await assertFails(
      writeFieldLearningEvent(db, {
        collection: 'achievement_unlocks',
        entityType: 'achievementUnlock',
        entityId: 'unlock-1',
        operationId: 'unlock-operation-1',
        payload: {
          achievementId: 'streak-7',
          definitionVersion: 1,
          unlockedAtUtcMs: 6000,
        },
      }),
    );
  });
});

describe('experiment_assignments immutable research contract', () => {
  it('allows exactly one authenticated own-owner v1 create', async () => {
    const db = authDb();
    const ref = doc(
      db,
      'field_users',
      alice,
      'experiment_assignments',
      'experiment-assignment:canonical-1',
    );

    await assertSucceeds(writeFieldExperimentAssignment(db));
    const snapshot = await assertSucceeds(getDoc(ref));
    if (
      snapshot.data().schemaVersion !== 1 ||
      snapshot.data().payload.ownerId !== alice ||
      snapshot.data().payload.assignmentId !== ref.id
    ) {
      throw new Error('Experiment assignment create lost canonical identity.');
    }
    await assertFails(getDoc(doc(
      authDb(bob),
      'field_users',
      alice,
      'experiment_assignments',
      ref.id,
    )));
  });

  it('allows the Unix epoch and rejects update or delete', async () => {
    const db = authDb();
    const entityId = 'experiment-assignment:epoch';
    const ref = doc(
      db,
      'field_users',
      alice,
      'experiment_assignments',
      entityId,
    );
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId,
        operationId: 'experiment-assignment-operation-epoch',
        clientUpdatedAtUtcMs: 0,
        payload: fieldExperimentAssignmentPayload({
          assignmentId: entityId,
          assignedAtUtcMs: 0,
        }),
      }),
    );

    await assertFails(updateDoc(ref, { 'payload.cohort': 'control' }));
    await assertFails(deleteDoc(ref));
  });

  it('rejects cross-owner path, authentication, and payload identity', async () => {
    await assertFails(
      writeFieldExperimentAssignment(authDb(bob), {
        uid: alice,
        entityId: 'experiment-assignment:cross-auth',
        operationId: 'experiment-assignment-operation-cross-auth',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: 'experiment-assignment:cross-auth',
        }),
      }),
    );
    await assertFails(
      writeFieldExperimentAssignment(authDb(), {
        entityId: 'experiment-assignment:owner-mismatch',
        operationId: 'experiment-assignment-operation-owner-mismatch',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: 'experiment-assignment:owner-mismatch',
          ownerId: bob,
        }),
      }),
    );
    await assertFails(
      writeFieldExperimentAssignment(authDb(), {
        entityId: 'experiment-assignment:path-mismatch',
        operationId: 'experiment-assignment-operation-path-mismatch',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: 'experiment-assignment:different',
        }),
      }),
    );
  });

  it('rejects every missing canonical key and every extra key', async () => {
    const keys = Object.keys(fieldExperimentAssignmentPayload());
    for (const key of keys) {
      const entityId = `experiment-assignment:missing-${key}`;
      const payload = fieldExperimentAssignmentPayload({
        assignmentId: entityId,
      });
      delete payload[key];
      await assertFails(
        writeFieldExperimentAssignment(authDb(), {
          entityId,
          operationId: `experiment-assignment-operation-missing-${key}`,
          payload,
        }),
      );
    }
    await assertFails(
      writeFieldExperimentAssignment(authDb(), {
        entityId: 'experiment-assignment:extra-key',
        operationId: 'experiment-assignment-operation-extra-key',
        payload: {
          ...fieldExperimentAssignmentPayload(),
          assignmentId: 'experiment-assignment:extra-key',
          runtimeEnabled: true,
        },
      }),
    );
  });

  it('rejects noncanonical identifier values and types', async () => {
    const overlong = 'x'.repeat(257);
    const cases = [
      ['assignmentId-empty', { assignmentId: '' }],
      ['assignmentId-trimmed', { assignmentId: ' assignment-id' }],
      ['assignmentId-overlong', { assignmentId: overlong }],
      ['assignmentId-type', { assignmentId: 1 }],
      ['ownerId-empty', { ownerId: '' }],
      ['ownerId-trimmed', { ownerId: `${alice} ` }],
      ['ownerId-overlong', { ownerId: overlong }],
      ['ownerId-type', { ownerId: 1 }],
      ['experimentId-empty', { experimentId: '' }],
      ['experimentId-trimmed', { experimentId: ' study-a' }],
      ['experimentId-overlong', { experimentId: overlong }],
      ['experimentId-type', { experimentId: 1 }],
      ['cohort-empty', { cohort: '' }],
      ['cohort-trimmed', { cohort: 'intervention ' }],
      ['cohort-overlong', { cohort: overlong }],
      ['cohort-type', { cohort: 1 }],
      ['protocol-empty', { protocolVersion: '' }],
      ['protocol-trimmed', { protocolVersion: ' protocol-1' }],
      ['protocol-overlong', { protocolVersion: overlong }],
      ['protocol-type', { protocolVersion: 1 }],
    ];

    for (const [name, override] of cases) {
      const entityId = `experiment-assignment:invalid-${name}`;
      await assertFails(
        writeFieldExperimentAssignment(authDb(), {
          entityId,
          operationId: `experiment-assignment-operation-invalid-${name}`,
          payload: fieldExperimentAssignmentPayload({
            assignmentId: entityId,
            ...override,
          }),
        }),
      );
    }

    const overlongDocumentId = `experiment-assignment:${'x'.repeat(257)}`;
    await assertFails(
      writeFieldExperimentAssignment(authDb(), {
        entityId: overlongDocumentId,
        operationId: 'experiment-assignment-operation-overlong-document',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: overlongDocumentId,
        }),
      }),
    );
    const trimmedDocumentId = ' experiment-assignment:trimmed-document';
    await assertFails(
      writeFieldExperimentAssignment(authDb(), {
        entityId: trimmedDocumentId,
        operationId: 'experiment-assignment-operation-trimmed-document',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: trimmedDocumentId,
        }),
      }),
    );
  });

  it('rejects unsupported versions, timestamps, types, and timestamp drift', async () => {
    const cases = [
      ['payload-v2', { schemaVersion: 2 }],
      ['zero-version', { payloadOverride: { experimentVersion: 0 } }],
      ['negative-version', { payloadOverride: { experimentVersion: -1 } }],
      ['version-type', { payloadOverride: { experimentVersion: '1' } }],
      ['negative-time', { payloadOverride: { assignedAtUtcMs: -1 } }],
      ['time-type', { payloadOverride: { assignedAtUtcMs: '4000' } }],
      ['timestamp-drift', { clientUpdatedAtUtcMs: 4001 }],
    ];

    for (const [name, options] of cases) {
      const entityId = `experiment-assignment:invalid-${name}`;
      await assertFails(
        writeFieldExperimentAssignment(authDb(), {
          entityId,
          operationId: `experiment-assignment-operation-invalid-${name}`,
          schemaVersion: options.schemaVersion ?? 1,
          clientUpdatedAtUtcMs: options.clientUpdatedAtUtcMs,
          payload: fieldExperimentAssignmentPayload({
            assignmentId: entityId,
            ...(options.payloadOverride ?? {}),
          }),
        }),
      );
    }
  });
});

describe('assessment_runs revisioned research contract', () => {
  it('keeps assessment responses on canonical AnswerAttempts only', async () => {
    await assertFails(
      writeFieldLearningEvent(authDb(), {
        collection: 'assessment_attempts',
        entityType: 'assessmentAttempt',
        entityId: 'assessment-attempt-forbidden',
        operationId: 'assessmentAttempt:forbidden:1',
        payload: {},
      }),
    );
    await assertFails(
      writeFieldLearningEvent(authDb(), {
        collection: 'assessment_responses',
        entityType: 'assessmentResponse',
        entityId: 'assessment-response-forbidden',
        operationId: 'assessmentResponse:forbidden:1',
        payload: { submittedRawResponse: 'must-never-sync' },
      }),
    );
  });

  it('allows an authenticated own-owner Active v1 create with exact pins', async () => {
    const db = authDb();
    const assignmentId = 'experiment-assignment:assessment-cloud-1';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-create',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          ownerId: alice,
          experimentId: 'study-a',
          experimentVersion: 1,
          cohort: 'intervention',
          protocolVersion: 'protocol-1',
          assignedAtUtcMs: 4600,
        }),
      }),
    );

    await assertSucceeds(writeFieldAssessmentRun(db));
    const ref = doc(
      db,
      'field_users',
      alice,
      'assessment_runs',
      'assessment-run-pre',
    );
    const snapshot = await assertSucceeds(getDoc(ref));
    if (
      snapshot.data().schemaVersion !== 1 ||
      snapshot.data().revision !== 1 ||
      snapshot.data().payload.state !== 'active' ||
      snapshot.data().payload.ownerId !== alice ||
      snapshot.data().payload.assignmentId !== assignmentId
    ) {
      throw new Error('Assessment run create lost canonical research pins.');
    }
    await assertFails(getDoc(doc(
      authDb(bob),
      'field_users',
      alice,
      'assessment_runs',
      ref.id,
    )));
  });

  it('accepts only append-only exact feature-contract identity pairs', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'contract-identity'));
    for (let index = 0; index < assessmentRunContractIdentities.length; index += 1) {
      const identity = assessmentRunContractIdentities[index];
      const entityId = `assessment-run-supported-contract-${index}`;
      await assertSucceeds(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            featureContractRevision: identity.revision,
            featureContractHash: identity.hash,
          }),
        }),
      );
      await assertSucceeds(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:2`,
          revision: 2,
          baseRevision: 1,
          clientUpdatedAtUtcMs: assessmentRunCompletedAtUtcMs,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            state: 'completed',
            completedAtUtcMs: assessmentRunCompletedAtUtcMs,
            featureContractRevision: identity.revision,
            featureContractHash: identity.hash,
          }),
        }),
      );
    }

    const unsupported = [
      {
        revision: '1.0.0',
        hash: assessmentRunContractHash,
      },
      {
        revision: assessmentRunContractRevision,
        hash:
          'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
      },
      {
        revision: '2.0.0',
        hash: assessmentRunContractHash,
      },
    ];
    for (let index = 0; index < unsupported.length; index += 1) {
      const identity = unsupported[index];
      const entityId = `assessment-run-unsupported-contract-${index}`;
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            featureContractRevision: identity.revision,
            featureContractHash: identity.hash,
          }),
        }),
      );
    }
  });

  it('accepts assessment evidence pinned to supported database schemas through v25', async () => {
    const db = authDb();
    const assignmentId = 'experiment-assignment:assessment-cloud-schema';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-schema',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          assignedAtUtcMs: 4600,
        }),
      }),
    );
    for (const databaseSchemaVersion of [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]) {
      const entityId = `assessment-run-schema-${databaseSchemaVersion}`;
      await assertSucceeds(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            assignmentId,
            databaseSchemaVersion,
          }),
        }),
      );
    }
    for (const databaseSchemaVersion of [14, 28, '25', '26', 25.5, 26.5]) {
      const entityId = `assessment-run-schema-${databaseSchemaVersion}`;
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            assignmentId,
            databaseSchemaVersion,
          }),
        }),
      );
    }
  });

  it('allows only revision-two Completed or Abandoned terminal updates', async () => {
    const db = authDb();
    const assignmentId = 'experiment-assignment:assessment-cloud-1';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-terminal',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          assignedAtUtcMs: 4600,
        }),
      }),
    );

    const terminalCases = [
      {
        entityId: 'assessment-run-completed',
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        abandonedAtUtcMs: null,
      },
      {
        entityId: 'assessment-run-abandoned',
        state: 'abandoned',
        completedAtUtcMs: null,
        abandonedAtUtcMs: assessmentRunCompletedAtUtcMs,
      },
    ];
    for (const terminal of terminalCases) {
      await seedFieldAssessmentRun({
        entityId: terminal.entityId,
        payload: fieldAssessmentRunPayload({ runId: terminal.entityId }),
      });
      await assertSucceeds(
        writeFieldAssessmentRun(db, {
          entityId: terminal.entityId,
          operationId: `assessmentRun:${terminal.entityId}:2`,
          revision: 2,
          baseRevision: 1,
          clientUpdatedAtUtcMs: assessmentRunCompletedAtUtcMs,
          payload: fieldAssessmentRunPayload({
            runId: terminal.entityId,
            state: terminal.state,
            completedAtUtcMs: terminal.completedAtUtcMs,
            abandonedAtUtcMs: terminal.abandonedAtUtcMs,
          }),
        }),
      );
      const snapshot = await assertSucceeds(getDoc(doc(
        db,
        'field_users',
        alice,
        'assessment_runs',
        terminal.entityId,
      )));
      if (
        snapshot.data().revision !== 2 ||
        snapshot.data().payload.state !== terminal.state
      ) {
        throw new Error(`Assessment ${terminal.state} transition was not exact.`);
      }
    }
  });

  it('requires the exact cloud assignment dependency before run creation', async () => {
    const db = authDb();
    await assertFails(writeFieldAssessmentRun(db));

    const assignmentId = 'experiment-assignment:assessment-cloud-1';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-dependency',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          assignedAtUtcMs: 4600,
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-assignment-mismatch',
        operationId: 'assessmentRun:assessment-run-assignment-mismatch:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-assignment-mismatch',
          experimentId: 'different-study',
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-cohort-mismatch',
        operationId: 'assessmentRun:assessment-run-cohort-mismatch:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-cohort-mismatch',
          cohort: 'control',
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-protocol-mismatch',
        operationId: 'assessmentRun:assessment-run-protocol-mismatch:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-protocol-mismatch',
          protocolVersion: 'protocol-2',
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-experiment-version-mismatch',
        operationId:
          'assessmentRun:assessment-run-experiment-version-mismatch:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-experiment-version-mismatch',
          experimentVersion: 2,
        }),
      }),
    );

    const secondAssignmentId = 'experiment-assignment:assessment-cloud-2';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: secondAssignmentId,
        operationId: 'experiment-assignment-operation-assessment-dependency-2',
        payload: fieldExperimentAssignmentPayload({
          assignmentId: secondAssignmentId,
          ownerId: alice,
          experimentId: 'study-a',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtcMs: 4600,
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-cross-assignment',
        operationId: 'assessmentRun:assessment-run-cross-assignment:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-cross-assignment',
          assignmentId: secondAssignmentId,
        }),
      }),
    );
  });

  it('rejects every missing canonical payload key and every extra key', async () => {
    const db = authDb();
    const assignmentId = 'experiment-assignment:assessment-cloud-1';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-shape',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          assignedAtUtcMs: 4600,
        }),
      }),
    );
    const keys = Object.keys(fieldAssessmentRunPayload());
    for (const key of keys) {
      const entityId = `assessment-run-missing-${key}`;
      const payload = fieldAssessmentRunPayload({ runId: entityId });
      delete payload[key];
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          clientUpdatedAtUtcMs: assessmentRunStartedAtUtcMs,
          payload,
        }),
      );
    }
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-extra-key',
        operationId: 'assessmentRun:assessment-run-extra-key:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-extra-key',
          submittedRawResponse: 'must-never-sync',
        }),
      }),
    );
  });

  it('rejects missing or extra entity and operation envelope keys', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-outer-shape'));
    const cases = [
      ['entity-missing', { omitEntityKey: 'lastOperationId' }],
      ['entity-extra', { entityExtra: { unexpected: true } }],
      ['operation-missing', { omitOperationKey: 'resultingRevision' }],
      ['operation-extra', { operationExtra: { unexpected: true } }],
    ];
    for (const [name, options] of cases) {
      const entityId = `assessment-run-outer-${name}`;
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({ runId: entityId }),
          ...options,
        }),
      );
    }
  });

  it('rejects noncanonical identifiers checksums versions and field types', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-types'));
    const overlong = 'x'.repeat(257);
    const cases = [
      ['run-empty', { runId: '' }],
      ['run-trimmed', { runId: ' assessment-run' }],
      ['run-overlong', { runId: overlong }],
      ['owner-empty', { ownerId: '' }],
      ['owner-type', { ownerId: 1 }],
      ['session-empty', { learningSessionId: '' }],
      ['cycle-trimmed', { studyCycleId: ' cycle' }],
      ['phase-unknown', { phase: 'during' }],
      ['state-unknown', { state: 'reopened' }],
      ['protocol-empty', { protocolId: '' }],
      ['protocol-trimmed', { protocolId: ' assessment-protocol' }],
      ['protocol-overlong', { protocolId: overlong }],
      ['protocol-version-empty', { protocolVersion: '' }],
      ['protocol-version-trimmed', { protocolVersion: ' protocol-1' }],
      ['protocol-version-overlong', { protocolVersion: overlong }],
      ['protocol-version-type', { protocolVersion: 1 }],
      ['experiment-empty', { experimentId: '' }],
      ['experiment-version-zero', { experimentVersion: 0 }],
      ['experiment-version-type', { experimentVersion: '1' }],
      ['assignment-empty', { assignmentId: '' }],
      ['cohort-overlong', { cohort: overlong }],
      ['consent-version-zero', { consentVersion: 0 }],
      ['consent-version-type', { consentVersion: '1' }],
      ['instrument-empty', { instrumentId: '' }],
      ['instrument-trimmed', { instrumentId: ' instrument-core' }],
      ['instrument-version-empty', { instrumentVersion: '' }],
      ['instrument-version-trimmed', { instrumentVersion: ' instrument-v1' }],
      ['instrument-version-overlong', { instrumentVersion: overlong }],
      ['form-empty', { formId: '' }],
      ['form-trimmed', { formId: ' form-a' }],
      ['form-version-empty', { formVersion: '' }],
      ['form-version-trimmed', { formVersion: ' form-v1' }],
      ['form-version-overlong', { formVersion: overlong }],
      ['instrument-checksum-short', { instrumentChecksumSha256: 'abc' }],
      ['instrument-checksum-uppercase', {
        instrumentChecksumSha256: assessmentRunInstrumentChecksum.toUpperCase(),
      }],
      ['form-checksum-type', { formChecksumSha256: 1 }],
      ['schema-version-wrong', { databaseSchemaVersion: 14 }],
      ['schema-version-type', { databaseSchemaVersion: '15' }],
      ['app-version-empty', { appVersion: '' }],
      ['app-version-trimmed', { appVersion: ' 1.0.0' }],
      ['app-version-overlong', { appVersion: overlong }],
      ['build-id-empty', { buildId: '' }],
      ['build-id-trimmed', { buildId: ' task-12-sync' }],
      ['build-id-overlong', { buildId: overlong }],
      ['content-revision-empty', { contentRevision: '' }],
      ['content-revision-trimmed', {
        contentRevision: ' assessment-content-v1',
      }],
      ['content-revision-overlong', { contentRevision: overlong }],
      ['evidence-policy-empty', { evidencePolicyVersion: '' }],
      ['evidence-policy-trimmed', {
        evidencePolicyVersion: ' learning-evidence-v1',
      }],
      ['evidence-policy-overlong', { evidencePolicyVersion: overlong }],
      ['contract-revision-empty', { featureContractRevision: '' }],
      ['contract-revision-trimmed', { featureContractRevision: ' 1.0.0' }],
      ['contract-revision-overlong', { featureContractRevision: overlong }],
      ['contract-hash-short', { featureContractHash: 'abc' }],
      ['contract-hash-uppercase', {
        featureContractHash: assessmentRunContractHash.toUpperCase(),
      }],
      ['started-type', { startedAtUtcMs: '5000' }],
    ];

    for (const [name, override] of cases) {
      const entityId = `assessment-run-invalid-${name}`;
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            ...override,
          }),
        }),
      );
    }
    const overlongDocumentId = `assessment-run-${'x'.repeat(257)}`;
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: overlongDocumentId,
        operationId: 'assessmentRun:overlong-document:1',
        payload: fieldAssessmentRunPayload({ runId: overlongDocumentId }),
      }),
    );
    const trimmedDocumentId = ' assessment-run-trimmed';
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: trimmedDocumentId,
        operationId: 'assessmentRun:trimmed-document:1',
        payload: fieldAssessmentRunPayload({ runId: trimmedDocumentId }),
      }),
    );
  });

  it('rejects invalid timestamp and terminal-state shapes', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-times'));
    const cases = [
      ['negative-consent-time', { consentDecidedAtUtcMs: -1 }],
      ['consent-after-start', { consentDecidedAtUtcMs: 5001 }],
      ['negative-start', { startedAtUtcMs: -1 }],
      ['active-completed-time', { completedAtUtcMs: 6000 }],
      ['active-abandoned-time', { abandonedAtUtcMs: 6000 }],
      ['completed-missing-time', { state: 'completed' }],
      ['completed-both-times', {
        state: 'completed',
        completedAtUtcMs: 6000,
        abandonedAtUtcMs: 6000,
      }],
      ['completed-before-start', {
        state: 'completed',
        completedAtUtcMs: 4999,
      }],
      ['abandoned-missing-time', { state: 'abandoned' }],
      ['abandoned-both-times', {
        state: 'abandoned',
        completedAtUtcMs: 6000,
        abandonedAtUtcMs: 6000,
      }],
    ];
    for (const [name, override] of cases) {
      const entityId = `assessment-run-time-${name}`;
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:1`,
          clientUpdatedAtUtcMs: assessmentRunStartedAtUtcMs,
          payload: fieldAssessmentRunPayload({
            runId: entityId,
            ...override,
          }),
        }),
      );
    }
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-client-time-drift',
        operationId: 'assessmentRun:assessment-run-client-time-drift:1',
        clientUpdatedAtUtcMs: assessmentRunStartedAtUtcMs + 1,
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-client-time-drift',
        }),
      }),
    );
  });

  it('rejects assessment schema v2 and deletion envelopes', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-envelope'));
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-schema-v2',
        operationId: 'assessmentRun:assessment-run-schema-v2:1',
        schemaVersion: 2,
        operationSchemaVersion: 1,
        payload: fieldAssessmentRunPayload({ runId: 'assessment-run-schema-v2' }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-deleted',
        operationId: 'assessmentRun:assessment-run-deleted:1',
        isDeleted: true,
        payload: fieldAssessmentRunPayload({ runId: 'assessment-run-deleted' }),
      }),
    );
  });

  it('rejects create-terminal cross-owner and owner reassignment writes', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-owner'));
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-created-completed',
        operationId: 'assessmentRun:assessment-run-created-completed:1',
        clientUpdatedAtUtcMs: assessmentRunCompletedAtUtcMs,
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-created-completed',
          state: 'completed',
          completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        }),
      }),
    );
    await assertFails(
      writeFieldAssessmentRun(authDb(bob), {
        uid: alice,
        entityId: 'assessment-run-cross-auth',
        operationId: 'assessmentRun:assessment-run-cross-auth:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-cross-auth',
        }),
      }),
    );

    await seedFieldAssessmentRun({ entityId: 'assessment-run-owner-change' });
    await assertFails(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-owner-change',
        operationId: 'assessmentRun:assessment-run-owner-change:2',
        revision: 2,
        baseRevision: 1,
        clientUpdatedAtUtcMs: assessmentRunCompletedAtUtcMs,
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-owner-change',
          ownerId: bob,
          state: 'completed',
          completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        }),
      }),
    );
  });

  it('rejects metadata mutation revision gaps and Active-to-Active updates', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-updates'));
    const cases = [
      ['protocol', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        protocolId: 'different-protocol',
      }],
      ['protocol-version', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        protocolVersion: 'protocol-2',
      }],
      ['experiment', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        experimentId: 'study-b',
        experimentVersion: 2,
      }],
      ['assignment', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        assignmentId: 'experiment-assignment:assessment-cloud-2',
      }],
      ['cohort-consent', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        cohort: 'control',
        consentVersion: 2,
        consentDecidedAtUtcMs: 4499,
      }],
      ['instrument', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        instrumentId: 'instrument-secondary',
        instrumentVersion: 'instrument-v2',
      }],
      ['form', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        formId: 'form-b',
        formVersion: 'form-v2',
      }],
      ['checksum', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        formChecksumSha256: assessmentRunInstrumentChecksum,
      }],
      ['build-schema', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        appVersion: '1.0.1',
        buildId: 'task-12-sync-2',
        databaseSchemaVersion: 16,
      }],
      ['content-policy', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        contentRevision: 'assessment-content-v2',
        evidencePolicyVersion: 'learning-evidence-v2',
      }],
      ['feature-contract', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        featureContractRevision: '2.0.0',
        featureContractHash: assessmentRunInstrumentChecksum,
      }],
      ['session-cycle-phase', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        learningSessionId: 'different-session',
        studyCycleId: 'different-cycle',
        phase: 'post',
      }],
      ['start-time', 2, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
        startedAtUtcMs: assessmentRunStartedAtUtcMs - 1,
      }],
      ['revision-gap', 3, 1, {
        state: 'completed',
        completedAtUtcMs: assessmentRunCompletedAtUtcMs,
      }],
      ['active-to-active', 2, 1, {}],
    ];
    for (const [name, revision, baseRevision, override] of cases) {
      const entityId = `assessment-run-update-${name}`;
      await seedFieldAssessmentRun({ entityId });
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:${revision}`,
          revision,
          baseRevision,
          clientUpdatedAtUtcMs:
            override.completedAtUtcMs ?? assessmentRunStartedAtUtcMs,
          payload: fieldAssessmentRunPayload({ runId: entityId, ...override }),
        }),
      );
    }
  });

  it('rejects terminal reopen swap timestamp mutation and delete', async () => {
    const db = authDb();
    await assertSucceeds(writeAssessmentAssignment(db, 'assessment-terminal'));
    const completedPayload = fieldAssessmentRunPayload({
      runId: 'assessment-run-terminal',
      state: 'completed',
      completedAtUtcMs: assessmentRunCompletedAtUtcMs,
    });
    const terminalCases = [
      ['reopen', {
        state: 'active',
        completedAtUtcMs: null,
      }],
      ['swap', {
        state: 'abandoned',
        completedAtUtcMs: null,
        abandonedAtUtcMs: assessmentRunCompletedAtUtcMs,
      }],
      ['timestamp', {
        completedAtUtcMs: assessmentRunCompletedAtUtcMs + 1,
      }],
      ['metadata', { contentRevision: 'different-content' }],
    ];
    for (const [name, override] of terminalCases) {
      const entityId = `assessment-run-terminal-${name}`;
      await seedFieldAssessmentRun({
        entityId,
        revision: 2,
        payload: { ...completedPayload, runId: entityId },
      });
      const payload = {
        ...completedPayload,
        runId: entityId,
        ...override,
      };
      await assertFails(
        writeFieldAssessmentRun(db, {
          entityId,
          operationId: `assessmentRun:${entityId}:3`,
          revision: 3,
          baseRevision: 2,
          clientUpdatedAtUtcMs:
            payload.completedAtUtcMs ?? payload.abandonedAtUtcMs ??
            assessmentRunStartedAtUtcMs,
          payload,
        }),
      );
    }

    await seedFieldAssessmentRun({ entityId: 'assessment-run-delete' });
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'assessment_runs',
      'assessment-run-delete',
    )));
  });
});

describe('saved_learning_items exact mutable intent contract', () => {
  it('allows an owner save followed by a revisioned tombstone', async () => {
    const db = authDb();
    const entityId = fieldSavedLearningItemEntityId();
    await assertSucceeds(writeFieldSavedLearningItem(db, { entityId }));
    await assertSucceeds(getDoc(doc(
      db, 'field_users', alice, 'saved_learning_items', entityId,
    )));
    await assertSucceeds(writeFieldSavedLearningItem(db, {
      entityId,
      operationId: 'saved-operation-2',
      revision: 2,
      baseRevision: 1,
      payload: fieldSavedLearningItemPayload({
        updatedAtUtcMs: 6000,
        isDeleted: true,
      }),
    }));
    await assertFails(writeFieldSavedLearningItem(db, {
      entityId,
      operationId: 'saved-operation-identity-mutation',
      revision: 3,
      baseRevision: 2,
      payload: fieldSavedLearningItemPayload({
        contentId: 'word:different',
        updatedAtUtcMs: 7000,
      }),
    }));
    await assertFails(writeFieldSavedLearningItem(db, {
      entityId,
      operationId: 'saved-operation-saved-time-mutation',
      revision: 3,
      baseRevision: 2,
      payload: fieldSavedLearningItemPayload({
        savedAtUtcMs: 5001,
        updatedAtUtcMs: 7000,
        isDeleted: true,
      }),
    }));
  });

  it('denies cross-owner writes and physical deletion', async () => {
    await assertFails(writeFieldSavedLearningItem(authDb(bob), { uid: alice }));
    const db = authDb();
    await assertSucceeds(writeFieldSavedLearningItem(db));
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'saved_learning_items',
      fieldSavedLearningItemEntityId(),
    )));
  });

  it('rejects non-exact keys types identity revisions and timestamps', async () => {
    const db = authDb();
    const canonical = fieldSavedLearningItemPayload();
    const missingRevision = { ...canonical };
    delete missingRevision.contentRevision;
    const cases = [
      { ...canonical, extra: true },
      missingRevision,
      { ...canonical, contentType: 'unknown' },
      { ...canonical, contentId: '  ' },
      { ...canonical, contentRevision: 0 },
      { ...canonical, savedAtUtcMs: -1 },
      { ...canonical, updatedAtUtcMs: 4999 },
      { ...canonical, isDeleted: 'false' },
    ];
    for (const [index, payload] of cases.entries()) {
      await assertFails(writeFieldSavedLearningItem(db, {
        entityId: fieldSavedLearningItemEntityId(payload),
        operationId: `saved-invalid-operation-${index}`,
        payload,
      }));
    }
    await assertFails(writeFieldSavedLearningItem(db, {
      operationId: 'saved-v2-operation',
      schemaVersion: 2,
    }));
    await assertFails(writeFieldSavedLearningItem(db, {
      entityId: 'device-local-id',
      operationId: 'saved-noncanonical-id-operation',
    }));
  });
});

describe('content_quality_reports exact immutable consent-bound contract', () => {
  it('allows one exact owner report including a null optional comment', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldContentQualityReport(db));
    const nullComment = fieldContentQualityReportPayload({
      reportId: 'report:station:text',
      reasonCode: 'text',
      comment: null,
      submittedAtUtcMs: 7001,
    });
    await assertSucceeds(writeFieldContentQualityReport(db, {
      payload: nullComment,
      operationId: fieldContentQualityReportOperationId(nullComment),
    }));
  });

  it('allows canonical redacted labels while rejecting raw secret values', async () => {
    const db = authDb();
    const canonicalComments = [
      'providerToken=[redacted]',
      'Audio issue; deviceId=[redacted]',
      'providerSecret:[redacted]; deviceIdentifier=[redacted]',
      'provider providerKey=[redacted] Token=ordinary',
      'xproviderToken=[redacted]',
    ];
    for (const [index, comment] of canonicalComments.entries()) {
      const payload = fieldContentQualityReportPayload({
        reportId: `report:redacted:${index}`,
        comment,
        submittedAtUtcMs: 7010 + index,
      });
      await assertSucceeds(writeFieldContentQualityReport(db, {
        payload,
        operationId: fieldContentQualityReportOperationId(payload),
      }));
    }

    for (const [index, comment] of [
      'providerToken=raw-provider-secret',
      'Audio issue; deviceId=raw-device-secret',
      'providerSecret:[redacted]; deviceIdentifier=raw-device-secret',
      'providerToken=[redacted]raw-suffix',
      'providerToken = [redacted]',
      'providerToken= [redacted]',
      'providerToken=[REDACTED]',
      'DEVICEID=[Redacted]',
    ].entries()) {
      const payload = fieldContentQualityReportPayload({
        reportId: `report:raw-secret:${index}`,
        comment,
        submittedAtUtcMs: 7020 + index,
      });
      await assertFails(writeFieldContentQualityReport(db, {
        payload,
        operationId: fieldContentQualityReportOperationId(payload),
      }));
    }
  });

  it('denies cross-owner writes physical deletion revision and tombstone', async () => {
    await assertFails(writeFieldContentQualityReport(authDb(bob), { uid: alice }));
    const db = authDb();
    const entityId = fieldContentQualityReportEntityId();
    await assertSucceeds(writeFieldContentQualityReport(db, { entityId }));
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'content_quality_reports',
      entityId,
    )));
    await assertFails(writeFieldContentQualityReport(db, {
      entityId,
      operationId: fieldContentQualityReportOperationId(),
      revision: 2,
      baseRevision: 1,
    }));
    const tombstone = fieldContentQualityReportPayload({ isDeleted: true });
    await assertFails(writeFieldContentQualityReport(db, {
      payload: tombstone,
      operationId: fieldContentQualityReportOperationId(tombstone),
    }));
  });

  it('rejects non-exact identity reason comment time and secret payloads', async () => {
    const db = authDb();
    const canonical = fieldContentQualityReportPayload();
    const missingRevision = { ...canonical };
    delete missingRevision.contentRevision;
    const cases = [
      { ...canonical, extra: true },
      missingRevision,
      { ...canonical, reportId: ' report:station:audio' },
      { ...canonical, reportId: 'report:\nstation:audio' },
      { ...canonical, contentType: 'unknown' },
      { ...canonical, contentId: ' word:station' },
      { ...canonical, contentId: 'word:\tstation' },
      { ...canonical, contentRevision: 0 },
      { ...canonical, reasonCode: 'other' },
      { ...canonical, comment: '' },
      { ...canonical, comment: ' padded ' },
      { ...canonical, comment: 'line one\nline two' },
      { ...canonical, comment: 'interior\tcontrol' },
      { ...canonical, comment: 'interior\u0085control' },
      { ...canonical, comment: 'ก'.repeat(501) },
      { ...canonical, comment: 'providerToken=provider-secret-SENTINEL' },
      { ...canonical, comment: 'PROVIDERTOKEN=provider-secret-SENTINEL' },
      { ...canonical, comment: 'deviceId=device-secret-SENTINEL' },
      { ...canonical, submittedAtUtcMs: -1 },
      { ...canonical, isDeleted: 'false' },
    ];
    for (const [index, payload] of cases.entries()) {
      await assertFails(writeFieldContentQualityReport(db, {
        payload,
        entityId: fieldContentQualityReportEntityId(payload),
        operationId: fieldContentQualityReportOperationId(payload),
      }));
    }
    await assertFails(writeFieldContentQualityReport(db, {
      clientUpdatedAtUtcMs: canonical.submittedAtUtcMs + 1,
      operationId: fieldContentQualityReportOperationId(canonical),
    }));
    await assertFails(writeFieldContentQualityReport(db, {
      entityId: 'device-local-report-id',
      operationId: fieldContentQualityReportOperationId(canonical),
    }));
    await assertFails(writeFieldContentQualityReport(db, {
      schemaVersion: 2,
      operationId: fieldContentQualityReportOperationId(canonical),
    }));
    await assertFails(writeFieldContentQualityReport(db, {
      operationId: 'device-local-operation-id',
    }));
    await assertFails(writeFieldContentQualityReport(db, {
      operationId: `content-quality-operation:${'0'.repeat(64)}`,
    }));
  });
});

describe('learning_time_segments exact immutable active-effort contract', () => {
  it('allows exact owner create with wall rollback and monotonic duration', async () => {
    const db = authDb();
    const payload = fieldLearningTimePayload();
    await assertSucceeds(writeFieldLearningTime(db, { payload }));
    await assertSucceeds(getDoc(doc(
      db,
      'field_users',
      alice,
      'learning_time_segments',
      payload.segmentId,
    )));
  });

  it('denies cross-owner mutation deletion replay and noncanonical identity', async () => {
    await assertFails(writeFieldLearningTime(authDb(bob), { uid: alice }));
    const db = authDb();
    const payload = fieldLearningTimePayload({
      sessionId: 'session:immutable',
    });
    await assertSucceeds(writeFieldLearningTime(db, { payload }));
    await assertFails(updateDoc(doc(
      db,
      'field_users',
      alice,
      'learning_time_segments',
      payload.segmentId,
    ), { clientUpdatedAtUtcMs: 9999 }));
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'learning_time_segments',
      payload.segmentId,
    )));
    await assertFails(writeFieldLearningTime(db, {
      payload,
      revision: 2,
      baseRevision: 1,
    }));
    await assertFails(writeFieldLearningTime(db, {
      payload,
      entityId: 'device-local-time-id',
      operationId: fieldLearningTimeOperationId('device-local-time-id'),
    }));
  });

  it('rejects non-exact keys ranges timezone source and envelope time', async () => {
    const db = authDb();
    const canonical = fieldLearningTimePayload({
      sessionId: 'session:invalid-cases',
    });
    const missingDuration = { ...canonical };
    delete missingDuration.activeDurationMs;
    const cases = [
      { ...canonical, extra: true },
      missingDuration,
      fieldLearningTimePayload({ sessionId: ' session:bad' }),
      fieldLearningTimePayload({ activeStartOffsetMs: -1 }),
      fieldLearningTimePayload({ activeStartOffsetMs: 315576000001 }),
      fieldLearningTimePayload({ activeDurationMs: 0 }),
      fieldLearningTimePayload({ activeDurationMs: 300001 }),
      fieldLearningTimePayload({ startedAtUtcMs: -1 }),
      fieldLearningTimePayload({ endedAtUtcMs: -1 }),
      fieldLearningTimePayload({ timezoneId: 'Asia Bangkok' }),
      fieldLearningTimePayload({ timezoneId: 'Asia' }),
      fieldLearningTimePayload({ timezoneId: 'Asia//Bangkok' }),
      fieldLearningTimePayload({ timezoneOffsetMinutes: 841 }),
      fieldLearningTimePayload({ captureSource: 'recreational' }),
    ];
    for (const [index, payload] of cases.entries()) {
      await assertFails(writeFieldLearningTime(db, {
        payload,
        entityId: payload.segmentId ?? canonical.segmentId,
        operationId: fieldLearningTimeOperationId(
          payload.segmentId ?? canonical.segmentId,
        ),
      }), `invalid learning-time case ${index}`);
    }
    await assertFails(writeFieldLearningTime(db, {
      payload: canonical,
      clientUpdatedAtUtcMs: canonical.endedAtUtcMs + 1,
    }));
    await assertFails(writeFieldLearningTime(db, {
      payload: canonical,
      operationId: `learning-time-operation:${'0'.repeat(64)}`,
    }));
  });
});

describe('learning_goals exact owner-scoped payload contract', () => {
  it('allows exact create and revisioned status update', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearningGoal(db));
    const payload = fieldLearningGoalPayload({
      status: 'completed',
      updatedAtUtcMs: 1787702400000,
    });
    await assertSucceeds(writeFieldLearningGoal(db, {
      payload,
      operationId: 'learningGoal:goal:ielts:2',
      revision: 2,
      baseRevision: 1,
    }));
  });

  it('rejects admission fields unknown enums bad time and cross owner', async () => {
    const db = authDb();
    const canonical = fieldLearningGoalPayload();
    const cases = [
      { ...canonical, admissionScore: 80 },
      { ...canonical, tcasProgramId: 'program:1' },
      { ...canonical, kind: 'universityAdmission' },
      { ...canonical, status: 'unknown' },
      { ...canonical, title: ' IELTS target' },
      { ...canonical, title: 'IELTS\u0085practice target' },
      { ...canonical, timezoneId: 'Asia Bangkok' },
      { ...canonical, timezoneOffsetMinutes: 841 },
      { ...canonical, updatedAtUtcMs: canonical.createdAtUtcMs - 1 },
    ];
    for (const payload of cases) {
      await assertFails(writeFieldLearningGoal(db, { payload }));
    }
    await assertFails(writeFieldLearningGoal(authDb(bob), { uid: alice }));
    await assertFails(writeFieldLearningGoal(db, {
      clientUpdatedAtUtcMs: canonical.updatedAtUtcMs + 1,
    }));
  });

  it('rejects C0 C1 and DEL controls in the canonical goal id', async () => {
    const db = authDb();
    const invalidGoalIds = [
      'goal:c0\u0001',
      'goal:c1\u0085',
      'goal:del\u007f',
    ];
    for (const [index, goalId] of invalidGoalIds.entries()) {
      await assertFails(writeFieldLearningGoal(db, {
        payload: fieldLearningGoalPayload({ goalId }),
        entityId: goalId,
        operationId: `learningGoal:control-case-${index}:1`,
      }));
    }
  });

  it('rejects direct deletion and preserves created-at identity on update', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearningGoal(db));
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'learning_goals',
      'goal:ielts',
    )));
    await assertFails(writeFieldLearningGoal(db, {
      payload: fieldLearningGoalPayload({
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1787702400000,
      }),
      operationId: 'learningGoal:goal:ielts:2',
      revision: 2,
      baseRevision: 1,
    }));
  });
});

describe('learner_preferences exact owner-scoped payload contract', () => {
  it('allows only the authenticated singleton-constrained read query', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearnerPreference(db));
    const preferences = collection(
      db,
      'field_users',
      alice,
      'learner_preferences',
    );
    await assertSucceeds(getDocs(query(
      preferences,
      where(documentId(), '==', 'current'),
    )));
    await assertFails(getDocs(preferences));
  });

  it('allows exact current create and revisioned editable override', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearnerPreference(db));
    await assertSucceeds(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({
        goal: 'conversationConfidence',
        availableMinutesPerDay: 30,
        activityPreference: 'speaking',
        homeExperience: 'adventure',
        updatedAtUtcMs: 1788134400000,
      }),
      revision: 2,
      baseRevision: 1,
    }));
  });

  it('binds same-revision operation receipts to the exact payload', async () => {
    const db = authDb();
    const first = fieldLearnerPreferencePayload();
    const second = fieldLearnerPreferencePayload({
      goal: 'conversationConfidence',
      availableMinutesPerDay: 30,
      activityPreference: 'speaking',
      homeExperience: 'adventure',
      updatedAtUtcMs: 1788048000001,
    });
    const firstOperationId = fieldLearnerPreferenceOperationId(first, 0, 1);
    const secondOperationId = fieldLearnerPreferenceOperationId(second, 0, 1);
    if (firstOperationId === secondOperationId) {
      throw new Error('Distinct preference payloads shared one operation id.');
    }
    await assertSucceeds(writeFieldLearnerPreference(db, { payload: first }));
    await assertFails(writeFieldLearnerPreference(db, {
      payload: second,
      operationId: firstOperationId,
    }));
  });

  it('rejects extra missing unknown out-of-range and cross-owner payloads', async () => {
    const db = authDb();
    const canonical = fieldLearnerPreferencePayload();
    const missing = { ...canonical };
    delete missing.activityPreference;
    const cases = [
      { ...canonical, learningStyle: 'visual' },
      { ...canonical, personality: 'competitive' },
      missing,
      { ...canonical, ownerId: bob },
      { ...canonical, preferenceVersion: 1 },
      { ...canonical, goal: 'visualLearner' },
      { ...canonical, availableMinutesPerDay: 0 },
      { ...canonical, availableMinutesPerDay: 241 },
      { ...canonical, activityPreference: 'personalityDriven' },
      { ...canonical, homeExperience: 'immersive' },
      { ...canonical, updatedAtUtcMs: -1 },
    ];
    for (const [index, payload] of cases.entries()) {
      await assertFails(writeFieldLearnerPreference(db, {
        payload,
        operationId: `learnerPreference:invalid:${index}`,
      }));
    }
    await assertFails(writeFieldLearnerPreference(authDb(bob), { uid: alice }));
    await assertFails(writeFieldLearnerPreference(db, {
      entityId: 'another-document',
      operationId: 'learnerPreference:another-document:1',
    }));
    await assertFails(writeFieldLearnerPreference(db, {
      clientUpdatedAtUtcMs: canonical.updatedAtUtcMs + 1,
    }));
    await assertFails(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({ preferenceVersion: 1 }),
    }));
  });

  it('cuts off v1 writes before they can overwrite stored v2 home experience', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({ homeExperience: 'adventure' }),
    }));
    await assertFails(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({
        preferenceVersion: 1,
        goal: 'conversationConfidence',
        updatedAtUtcMs: 1788134400000,
      }),
      revision: 2,
      baseRevision: 1,
    }));
    const stored = await assertSucceeds(getDoc(doc(
      db,
      'field_users',
      alice,
      'learner_preferences',
      'current',
    )));
    if (stored.data().payload.homeExperience !== 'adventure') {
      throw new Error('A legacy v1 write erased stored v2 home experience.');
    }
  });

  it('rejects revision gaps immutable owner changes and deletion', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearnerPreference(db));
    await assertFails(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({
        updatedAtUtcMs: 1788134400000,
      }),
      revision: 3,
      baseRevision: 1,
    }));
    await assertFails(writeFieldLearnerPreference(db, {
      payload: fieldLearnerPreferencePayload({
        ownerId: bob,
        updatedAtUtcMs: 1788134400000,
      }),
      revision: 2,
      baseRevision: 1,
    }));
    await assertFails(deleteDoc(doc(
      db,
      'field_users',
      alice,
      'learner_preferences',
      'current',
    )));
  });
});

