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

async function seedDeletionFence(uid = alice) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'account_deletion_operations', uid),
      { operationId: 'delete-operation-1', firebaseUid: uid },
    );
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
  schemaVersion = 1,
  operationSchemaVersion = schemaVersion,
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
    clientUpdatedAtUtcMs: 2000,
    serverUpdatedAt: serverTimestamp(),
    lastOperationId: operationId,
  });
  batch.set(doc(db, 'field_users', uid, 'operations', operationId), {
    schemaVersion: operationSchemaVersion,
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

function ordinaryAttemptEvidence(overrides = {}) {
  return {
    schemaVersion: 1,
    evidenceClass: 'recognition',
    skillId: 'word-meaning',
    hintLevel: 0,
    policyVersion: 'learning-evidence-v1',
    contentRevision: 'synthetic-content-v1',
    featureContractRevision: '1.3.0',
    featureContractHash: '41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4',
    classificationSource: 'declared',
    rolloutMode: 'legacy',
    protocolId: null,
    protocolVersion: null,
    experimentId: null,
    experimentVersion: null,
    assignmentId: null,
    cohort: null,
    researchConsentVersion: null,
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

function evidenceAttemptPayload(context = ordinaryAttemptEvidence()) {
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

describe('account deletion owner-write fence', () => {
  it('keeps ordinary owner writes working before a tombstone exists', async () => {
    const db = authDb();
    await assertSucceeds(
      setDoc(doc(db, 'state', alice), { totalPoints: 100 }),
    );
    await assertSucceeds(
      setDoc(doc(db, 'categories', 'before-delete'), {
        category_name: 'Travel',
        created_at: serverTimestamp(),
        uid: alice,
      }),
    );
    await assertSucceeds(
      writeFieldCategory(db, {
        entityId: 'before-delete',
        operationId: 'before-delete-operation',
      }),
    );
  });

  it('denies every owner write surface after tombstone but preserves reads', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'users', alice), {
        first_name: 'Alice',
        last_name: '',
        email: 'alice@example.test',
        age: 20,
        createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'state', alice), { totalPoints: 100 });
      await setDoc(doc(db, 'categories', 'existing-category'), {
        category_name: 'Existing',
        created_at: serverTimestamp(),
        uid: alice,
      });
      await setDoc(
        doc(db, 'categories', 'existing-category', 'words', 'existing-word'),
        {
          word: 'cat',
          meaning: 'แมว',
          part_of_speech: 'noun',
          user_id: alice,
          is_global: false,
          created_at: serverTimestamp(),
        },
      );
      await setDoc(doc(db, 'products', productId), {
        name: 'Neon',
        price: 50,
        image_name: 'wallpaper_neon.png',
      });
    });
    const db = authDb();
    await assertSucceeds(
      writeFieldCategory(db, {
        entityId: 'existing-field-category',
        operationId: 'existing-field-operation',
      }),
    );
    await seedDeletionFence();

    await assertSucceeds(getDoc(doc(db, 'users', alice)));
    await assertSucceeds(
      getDoc(doc(db, 'categories', 'existing-category')),
    );
    await assertSucceeds(
      getDoc(
        doc(
          db,
          'field_users',
          alice,
          'categories',
          'existing-field-category',
        ),
      ),
    );

    await assertFails(updateDoc(doc(db, 'users', alice), { points: 1 }));
    await assertFails(updateDoc(doc(db, 'state', alice), { totalPoints: 99 }));
    await assertFails(
      setDoc(doc(db, 'categories', 'blocked-category'), {
        category_name: 'Blocked',
        created_at: serverTimestamp(),
        uid: alice,
      }),
    );
    await assertFails(deleteDoc(doc(db, 'categories', 'existing-category')));
    await assertFails(
      setDoc(
        doc(db, 'categories', 'existing-category', 'words', 'blocked-word'),
        {
          word: 'dog',
          meaning: 'สุนัข',
          part_of_speech: 'noun',
          user_id: alice,
          is_global: false,
          created_at: serverTimestamp(),
        },
      ),
    );
    await assertFails(
      updateDoc(
        doc(db, 'categories', 'existing-category', 'words', 'existing-word'),
        { meaning: 'แมวบ้าน' },
      ),
    );
    await assertFails(
      deleteDoc(
        doc(db, 'categories', 'existing-category', 'words', 'existing-word'),
      ),
    );
    await assertFails(
      setDoc(doc(db, 'vocabulary', 'blocked-private'), {
        word: 'dog',
        meaning: 'สุนัข',
        part_of_speech: 'noun',
        uid: alice,
      }),
    );
    await assertFails(
      writeFieldCategory(db, {
        entityId: 'blocked-field-category',
        operationId: 'blocked-field-operation',
      }),
    );

    const purchase = writeBatch(db);
    purchase.update(doc(db, 'state', alice), { totalPoints: 50 });
    purchase.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(),
    );
    await assertFails(purchase.commit());
  });

  it('does not fence other owners but rejects uid-less legacy writes', async () => {
    await seedDeletionFence();
    await assertSucceeds(
      setDoc(doc(authDb(bob), 'state', bob), { totalPoints: 5 }),
    );
    await assertFails(
      setDoc(doc(authDb(), 'vocabulary', 'shared-after-delete'), {
        word: 'bird',
        meaning: 'นก',
        part_of_speech: 'noun',
      }),
    );
    await assertFails(
      setDoc(doc(authDb(bob), 'vocabulary', 'spoof-alice'), {
        word: 'fish',
        meaning: 'ปลา',
        part_of_speech: 'noun',
        uid: alice,
      }),
    );
  });

  it('keeps the tombstone inaccessible to clients', async () => {
    await seedDeletionFence();
    const ref = doc(authDb(), 'account_deletion_operations', alice);
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { operationId: 'replace' }));
    await assertFails(updateDoc(ref, { operationId: 'replace' }));
    await assertFails(deleteDoc(ref));
  });
});

describe('retired shared dictionary client writes', () => {
  it('denies vocabulary and dictionary writes with or without an owner field', async () => {
    for (const anonymous of [false, true]) {
      const db = authDb(alice, anonymous);
      for (const owner of [{}, { uid: alice }]) {
        await assertFails(
          setDoc(doc(db, 'vocabulary', 'retired-vocabulary'), {
            word: 'cat',
            meaning: 'synthetic meaning',
            part_of_speech: 'noun',
            ...owner,
          }),
        );
      }
      await assertFails(
        setDoc(doc(db, 'global_words', 'cat'), {
          word: 'cat',
          meaning: 'synthetic meaning',
          partOfSpeech: 'noun',
          createdAt: serverTimestamp(),
        }),
      );
    }
  });

  it('preserves signed-in reads of administrator-seeded dictionaries', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      for (const collection of ['vocabulary', 'global_words']) {
        await setDoc(doc(context.firestore(), collection, 'seeded-cat'), {
          word: 'cat',
          meaning: 'synthetic meaning',
        });
      }
    });
    for (const collection of ['vocabulary', 'global_words']) {
      await assertSucceeds(getDoc(doc(authDb(), collection, 'seeded-cat')));
      await assertFails(
        getDoc(doc(testEnv.unauthenticatedContext().firestore(), collection, 'seeded-cat')),
      );
      await assertFails(updateDoc(doc(authDb(), collection, 'seeded-cat'), { meaning: 'changed' }));
      await assertFails(deleteDoc(doc(authDb(), collection, 'seeded-cat')));
    }
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
    for (const [featureContractRevision, featureContractHash] of [
      ['1.0.0', 'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0'],
      ['1.1.0', '40e587aa5605d066e67aee81f3254671ea5484beca04dbb41fccbfd3ddb2af27'],
      ['1.2.0', 'c6a772993afa6cc2d78f3eb11687d615192ef6ff52581fa882826180f90afee7'],
    ]) {
      await assertSucceeds(writeFieldLearningEvent(db, {
        schemaVersion: 2,
        entityId: `retained-${featureContractRevision}`,
        operationId: `retained-operation-${featureContractRevision}`,
        payload: evidenceAttemptPayload(ordinaryAttemptEvidence({ featureContractRevision, featureContractHash })),
      }));
    }
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

  for (const type of ['creditQuizCorrectV1', 'creditLegacyCarryV1']) {
    it(`denies positive ${type} mint in the purchase/equip-only protocol`, async () => {
      await assertFails(writeFieldRewardTransaction(authDb(), {
        entityId: `denied-${type}`,
        operationId: `denied-${type}`,
        payload: {
          idempotencyKey: `denied-${type}`,
          transactionType: type,
          amount: 1,
          itemId: null,
          slot: null,
          catalogVersion: 0,
          sourceEventId: 'synthetic-attempt',
          occurredAtUtcMs: 4000,
        },
      }));
    });
  }

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

describe('ordinary answer evidence v2 contract', () => {
  it('accepts declared ordinary metadata with matching immutable operation schema', async () => {
    const db = authDb();
    await assertSucceeds(writeFieldLearningEvent(db, {
      schemaVersion: 2,
      payload: evidenceAttemptPayload(),
    }));
    const ref = doc(db, 'field_users', alice, 'attempts', 'attempt-1');
    await assertSucceeds(getDoc(ref));
    await assertFails(updateDoc(ref, { 'payload.evidenceContext.skillId': 'different-skill' }));
    await assertFails(deleteDoc(ref));
    await assertFails(getDoc(doc(authDb(bob), 'field_users', alice, 'attempts', 'attempt-1')));
  });

  it('requires strict map metadata and matching class, policy and feature identity', async () => {
    const context = ordinaryAttemptEvidence();
    const valid = evidenceAttemptPayload(context);
    const missing = { ...valid };
    delete missing.evidenceClass;
    const malformed = [
      missing,
      { ...valid, evidenceClass: 'independentRecall' },
      { ...valid, evidenceContext: JSON.stringify(context) },
      { ...valid, evidenceContext: { ...context, privateText: 'PRIVATE_SYNTHETIC_CANARY' } },
      evidenceAttemptPayload({ ...context, schemaVersion: 2 }),
      evidenceAttemptPayload({ ...context, policyVersion: 'unknown-policy' }),
      evidenceAttemptPayload({ ...context, featureContractHash: '0'.repeat(64) }),
      evidenceAttemptPayload({ ...context, hintLevel: -1 }),
      evidenceAttemptPayload({ ...context, evidenceClass: 'unknown-class' }),
      evidenceAttemptPayload({ ...context, classificationSource: 'legacyInferred' }),
    ];
    for (const [index, payload] of malformed.entries()) {
      await assertFails(writeFieldLearningEvent(authDb(), {
        schemaVersion: 2,
        entityId: `malformed-${index}`,
        operationId: `malformed-operation-${index}`,
        payload,
      }));
    }
  });

  it('rejects every research pin even on a declared legacy rollout', async () => {
    const pins = {
      protocolId: 'synthetic-protocol', protocolVersion: '1',
      experimentId: 'synthetic-experiment', experimentVersion: 1,
      assignmentId: 'synthetic-assignment', cohort: 'synthetic-cohort',
      researchConsentVersion: 1, instrumentId: 'synthetic-instrument',
      instrumentVersion: '1', formId: 'synthetic-form', formVersion: '1',
      assessmentItemId: 'synthetic-item', assessmentResponseCode: 'correct',
      scoringRuleVersion: '1',
    };
    for (const [field, value] of Object.entries(pins)) {
      await assertFails(writeFieldLearningEvent(authDb(), {
        schemaVersion: 2,
        entityId: `research-${field}`,
        operationId: `research-operation-${field}`,
        payload: evidenceAttemptPayload(ordinaryAttemptEvidence({ [field]: value })),
      }));
    }
    for (const rolloutMode of ['shadow', 'enforced']) {
      await assertFails(writeFieldLearningEvent(authDb(), {
        schemaVersion: 2,
        entityId: `research-${rolloutMode}`,
        operationId: `research-operation-${rolloutMode}`,
        payload: evidenceAttemptPayload(ordinaryAttemptEvidence({ ...pins, rolloutMode })),
      }));
    }
  });

  it('requires matching versions on the operation and its attempt', async () => {
    await assertFails(writeFieldLearningEvent(authDb(), {
      schemaVersion: 2, operationSchemaVersion: 1,
      payload: evidenceAttemptPayload(),
    }));
    await assertFails(writeFieldLearningEvent(authDb(), {
      schemaVersion: 1, operationSchemaVersion: 2,
      entityId: 'legacy-attempt', operationId: 'legacy-attempt-operation',
    }));
    await assertFails(writeFieldLearningEvent(authDb(), {
      schemaVersion: 3,
      entityId: 'future-attempt', operationId: 'future-attempt-operation',
      payload: evidenceAttemptPayload(),
    }));
  });

  it('does not widen reading events to v2', async () => {
    const payload = {
      documentId: 'document-1', documentRevision: 1,
      eventType: 'checkpoint', position: 1, occurredAtUtcMs: 2000,
    };
    await assertSucceeds(writeFieldLearningEvent(authDb(), {
      collection: 'reading_events', entityType: 'readingEvent',
      entityId: 'reading-v1', operationId: 'reading-v1-operation', payload,
    }));
    await assertFails(writeFieldLearningEvent(authDb(), {
      collection: 'reading_events', entityType: 'readingEvent', schemaVersion: 2,
      entityId: 'reading-v2', operationId: 'reading-v2-operation', payload,
    }));
  });

  it('keeps the account-deletion fence closed for v2 evidence', async () => {
    await seedDeletionFence();
    await assertFails(writeFieldLearningEvent(authDb(), {
      schemaVersion: 2, payload: evidenceAttemptPayload(),
    }));
  });
});

