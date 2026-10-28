const { after, before, beforeEach, describe, it } = require('node:test');
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
} = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'field_users', uid, 'words', entityId), {
    schemaVersion: 1,
    entityId,
    payload: {
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
    schemaVersion: 1,
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
    schemaVersion: 1,
    entityId,
    payload: resolvedPayload,
    revision: 1,
    isDeleted: false,
    clientUpdatedAtUtcMs: 2000,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion: 1,
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

function writeFieldRewardTransaction(db, {
  uid = alice,
  entityId = 'reward-1',
  operationId = 'reward-operation-1',
  payload,
} = {}) {
  return writeFieldLearningEvent(db, {
    uid,
    collection: 'reward_transactions',
    entityType: 'rewardTransaction',
    entityId,
    operationId,
    payload: payload ?? {
      idempotencyKey: 'purchase-tap-1',
      transactionType: 'purchase',
      amount: -80,
      itemId: 'theme_ocean',
      slot: 'theme',
      catalogVersion: 1,
      sourceEventId: null,
      occurredAtUtcMs: 4000,
    },
  });
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
          catalogVersion: 1,
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
          catalogVersion: 1,
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
          catalogVersion: 1,
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
});

