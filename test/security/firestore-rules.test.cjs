const { after, before, beforeEach, describe, it } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'demo-lexiquest-rules-test';
const alice = 'alice_uid';
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

describe('Release A remote economy lockdown', () => {
  it('denies an owner creating remote economy state', async () => {
    const db = authDb();

    await assertFails(
      setDoc(doc(db, 'state', alice), { totalPoints: 100 }),
    );
  });

  it('denies an owner creating wallpaper-only state', async () => {
    const db = authDb();

    await assertFails(
      setDoc(
        doc(db, 'state', alice),
        { selectedWallpaper: 'wallpaper_neon.png' },
      ),
    );
  });

  for (const [field, value] of [
    ['totalPoints', 150],
    ['totalCorrectAnswers', 1],
    ['totalWrongAnswers', 1],
    ['gamesPlayed', 1],
  ]) {
    it(`denies an owner changing remote economy counter ${field}`, async () => {
      await seedStateAndProduct();
      const db = authDb();

      await assertFails(
        updateDoc(doc(db, 'state', alice), { [field]: value }),
      );
    });
  }

  it('denies mixing a wallpaper preference with an economy mutation', async () => {
    await seedStateAndProduct();
    const db = authDb();

    await assertFails(
      updateDoc(doc(db, 'state', alice), {
        selectedWallpaper: 'wallpaper_neon.png',
        totalPoints: 150,
      }),
    );
  });

  it('allows an owner to update only the wallpaper preference', async () => {
    await seedStateAndProduct();
    const db = authDb();

    await assertSucceeds(
      updateDoc(doc(db, 'state', alice), {
        selectedWallpaper: 'wallpaper_neon.png',
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db, 'state', alice), { selectedWallpaper: null }),
    );

    const state = await assertSucceeds(getDoc(doc(db, 'state', alice)));
    if (
      state.data().totalPoints !== 100
      || state.data().selectedWallpaper !== null
    ) {
      throw new Error('Wallpaper-only update changed remote economy state.');
    }
  });

  it('denies an exact-price purchase even with an atomic debit', async () => {
    await seedStateAndProduct();
    const db = authDb();
    const batch = writeBatch(db);
    batch.update(doc(db, 'state', alice), { totalPoints: 50 });
    batch.set(
      doc(db, 'purchased_items', purchaseId),
      purchaseData(),
    );

    await assertFails(batch.commit());
  });

  it('denies direct creation of a purchased item', async () => {
    await seedStateAndProduct();
    const db = authDb();

    await assertFails(
      setDoc(doc(db, 'purchased_items', purchaseId), purchaseData()),
    );
  });

  it('keeps purchased items immutable to clients', async () => {
    await seedStateAndProduct();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'purchased_items', purchaseId),
        purchaseData(),
      );
    });
    const db = authDb();
    const purchaseRef = doc(db, 'purchased_items', purchaseId);

    await assertFails(updateDoc(purchaseRef, { total_price: 1 }));
    await assertFails(deleteDoc(purchaseRef));
  });

  it('keeps legacy owner state and purchase records readable', async () => {
    await seedStateAndProduct();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'purchased_items', purchaseId),
        purchaseData(),
      );
    });
    const db = authDb();

    const state = await assertSucceeds(getDoc(doc(db, 'state', alice)));
    const purchase = await assertSucceeds(
      getDoc(doc(db, 'purchased_items', purchaseId)),
    );
    const purchases = await assertSucceeds(
      getDocs(
        query(
          collection(db, 'purchased_items'),
          where('user_id', '==', alice),
        ),
      ),
    );
    const bobDb = authDb('bob_uid');
    await assertFails(getDoc(doc(bobDb, 'state', alice)));
    await assertFails(
      getDoc(doc(bobDb, 'purchased_items', purchaseId)),
    );
    if (
      state.data().totalPoints !== 100
      || purchase.data().product_id !== productId
      || purchases.size !== 1
    ) {
      throw new Error('Legacy owner records were not preserved.');
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
    await seedStateAndProduct();
    const db = authDb('bob_uid');

    await assertFails(
      updateDoc(
        doc(db, 'state', alice),
        { selectedWallpaper: 'wallpaper_neon.png' },
      ),
    );
  });
});
