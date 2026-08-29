const { after, before, beforeEach, describe, it } = require('node:test');
const { createHash } = require('node:crypto');
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
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'demo-lexiquest-rules-test';
const alice = 'alice_uid';
const bob = 'bob_uid';
const productId = 'wallpaper_neon';
const purchaseId = `${alice}_${productId}`;
let testEnv;

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
const assessmentRunContractHash =
  'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0';

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
    featureContractRevision: '1.0.0',
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

  it('accepts assessment evidence pinned to current database schema v19', async () => {
    const db = authDb();
    const assignmentId = 'experiment-assignment:assessment-cloud-v16';
    await assertSucceeds(
      writeFieldExperimentAssignment(db, {
        entityId: assignmentId,
        operationId: 'experiment-assignment-operation-assessment-v16',
        payload: fieldExperimentAssignmentPayload({
          assignmentId,
          assignedAtUtcMs: 4600,
        }),
      }),
    );
    await assertSucceeds(
      writeFieldAssessmentRun(db, {
        entityId: 'assessment-run-v16',
        operationId: 'assessmentRun:assessment-run-v16:1',
        payload: fieldAssessmentRunPayload({
          runId: 'assessment-run-v16',
          assignmentId,
          databaseSchemaVersion: 19,
        }),
      }),
    );
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

