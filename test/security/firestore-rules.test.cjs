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
  deleteField,
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
const bob = 'bob_uid';
const anonymousUid = 'anon_123';
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

function profileData(overrides = {}) {
  return {
    first_name: 'Alice',
    last_name: 'Learner',
    email: 'alice@example.com',
    age: 20,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function categoryData(uid = alice, name = 'Core words') {
  return {
    category_name: name,
    created_at: serverTimestamp(),
    uid,
  };
}

function wordData(uid = alice, word = 'lexicon') {
  return {
    word,
    meaning: 'A vocabulary',
    part_of_speech: 'noun',
    user_id: uid,
    is_global: false,
    created_at: serverTimestamp(),
  };
}

function vocabularyData(word = 'abate') {
  return {
    word,
    meaning: 'Become less intense',
    part_of_speech: 'verb',
  };
}

function globalWordData(word = 'resilient') {
  return {
    word,
    meaning: 'Able to recover quickly',
    partOfSpeech: 'adjective',
    createdAt: serverTimestamp(),
  };
}

async function seedDocuments(entries) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [documentPath, data] of entries) {
      await setDoc(doc(db, documentPath), data);
    }
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

describe('registered profile authority contract', () => {
  it('allows a registered owner to create and read a validated profile', async () => {
    const db = authDb();
    const profileRef = doc(db, 'users', alice);

    await assertSucceeds(setDoc(profileRef, profileData()));
    const profile = await assertSucceeds(getDoc(profileRef));
    if (profile.data().email !== 'alice@example.com') {
      throw new Error('Registered owner profile was not preserved.');
    }
  });

  for (const field of ['points', 'totalPoints', 'gamesPlayed']) {
    it(`denies an owner adding legacy counter ${field}`, async () => {
      await seedDocuments([
        [`users/${alice}`, profileData()],
      ]);
      const db = authDb();

      await assertFails(
        updateDoc(doc(db, 'users', alice), { [field]: 1 }),
      );
    });

    it(`denies an owner changing legacy counter ${field}`, async () => {
      await seedDocuments([
        [`users/${alice}`, profileData({ [field]: 10 })],
      ]);
      const db = authDb();

      await assertFails(
        updateDoc(doc(db, 'users', alice), { [field]: 11 }),
      );
    });

    it(`denies an owner removing legacy counter ${field}`, async () => {
      await seedDocuments([
        [`users/${alice}`, profileData({ [field]: 10 })],
      ]);
      const db = authDb();

      await assertFails(
        updateDoc(doc(db, 'users', alice), { [field]: deleteField() }),
      );
    });
  }

  it('allows validated profile updates while preserving legacy counters', async () => {
    await seedDocuments([
      [
        `users/${alice}`,
        profileData({
          points: 10,
          totalPoints: 20,
          gamesPlayed: 3,
        }),
      ],
    ]);
    const db = authDb();

    await assertSucceeds(
      updateDoc(doc(db, 'users', alice), {
        first_name: 'Alicia',
        last_name: 'Reader',
        email: 'alicia@example.com',
        age: 21,
      }),
    );

    const profile = await assertSucceeds(
      getDoc(doc(db, 'users', alice)),
    );
    const data = profile.data();
    if (
      data.first_name !== 'Alicia'
      || data.last_name !== 'Reader'
      || data.email !== 'alicia@example.com'
      || data.age !== 21
      || data.points !== 10
      || data.totalPoints !== 20
      || data.gamesPlayed !== 3
    ) {
      throw new Error('Profile update changed immutable legacy counters.');
    }
  });

  it('rejects an invalid resulting profile', async () => {
    await seedDocuments([
      [`users/${alice}`, profileData({ points: 10 })],
    ]);
    const db = authDb();

    await assertFails(
      updateDoc(doc(db, 'users', alice), { first_name: '' }),
    );
  });

  it('denies cross-owner profile reads and updates', async () => {
    await seedDocuments([
      [`users/${alice}`, profileData()],
    ]);
    const db = authDb(bob);

    await assertFails(getDoc(doc(db, 'users', alice)));
    await assertFails(
      updateDoc(doc(db, 'users', alice), { first_name: 'Mallory' }),
    );
  });
});

describe('registered private learning record contract', () => {
  it('allows owner category CRUD while denying cross-owner access', async () => {
    const db = authDb();
    const categoryRef = doc(db, 'categories', 'alice_category');
    const wordRef = doc(
      db,
      'categories',
      'alice_category',
      'words',
      'alice_word',
    );

    await assertSucceeds(setDoc(categoryRef, categoryData()));
    await assertSucceeds(setDoc(wordRef, wordData()));
    await assertSucceeds(getDoc(categoryRef));
    await assertSucceeds(getDoc(wordRef));
    await assertSucceeds(
      updateDoc(wordRef, { meaning: 'A collection of words' }),
    );

    const bobDb = authDb(bob);
    await assertFails(
      getDoc(doc(bobDb, 'categories', 'alice_category')),
    );
    await assertFails(
      getDoc(
        doc(
          bobDb,
          'categories',
          'alice_category',
          'words',
          'alice_word',
        ),
      ),
    );

    await assertSucceeds(deleteDoc(wordRef));
    await assertSucceeds(deleteDoc(categoryRef));
  });
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
  it('denies anonymous profile read, create, update, and delete', async () => {
    await seedDocuments([
      [`users/${anonymousUid}`, profileData()],
    ]);
    const db = authDb(anonymousUid, true);
    const existingRef = doc(db, 'users', anonymousUid);
    const createDb = authDb('anon_create_profile', true);

    await assertFails(getDoc(existingRef));
    await assertFails(
      setDoc(
        doc(createDb, 'users', 'anon_create_profile'),
        profileData({ email: 'anon@example.com' }),
      ),
    );
    await assertFails(updateDoc(existingRef, { first_name: 'Guest' }));
    await assertFails(deleteDoc(existingRef));
  });

  it('denies anonymous state read, create, update, and delete', async () => {
    await seedDocuments([
      [
        `state/${anonymousUid}`,
        { totalPoints: 100, selectedWallpaper: null },
      ],
    ]);
    const db = authDb(anonymousUid, true);
    const existingRef = doc(db, 'state', anonymousUid);
    const createDb = authDb('anon_create_state', true);

    await assertFails(getDoc(existingRef));
    await assertFails(
      setDoc(
        doc(createDb, 'state', 'anon_create_state'),
        { selectedWallpaper: null },
      ),
    );
    await assertFails(
      updateDoc(existingRef, {
        selectedWallpaper: 'wallpaper_neon.png',
      }),
    );
    await assertFails(deleteDoc(existingRef));
  });

  it('denies anonymous purchase read, create, update, and delete', async () => {
    const anonymousPurchaseId = `${anonymousUid}_${productId}`;
    await seedDocuments([
      [
        `purchased_items/${anonymousPurchaseId}`,
        {
          user_id: anonymousUid,
          product_id: productId,
          total_price: 50,
          created_at: serverTimestamp(),
        },
      ],
    ]);
    const db = authDb(anonymousUid, true);
    const existingRef = doc(db, 'purchased_items', anonymousPurchaseId);

    await assertFails(getDoc(existingRef));
    await assertFails(
      setDoc(
        doc(db, 'purchased_items', `${anonymousPurchaseId}_new`),
        {
          user_id: anonymousUid,
          product_id: 'wallpaper_other',
          total_price: 10,
          created_at: serverTimestamp(),
        },
      ),
    );
    await assertFails(updateDoc(existingRef, { total_price: 1 }));
    await assertFails(deleteDoc(existingRef));
  });

  it('denies anonymous category read, create, update, and delete', async () => {
    await seedDocuments([
      [`categories/anon_category`, categoryData(anonymousUid)],
    ]);
    const db = authDb(anonymousUid, true);
    const existingRef = doc(db, 'categories', 'anon_category');

    await assertFails(getDoc(existingRef));
    await assertFails(
      setDoc(
        doc(db, 'categories', 'anon_category_new'),
        categoryData(anonymousUid, 'Guest words'),
      ),
    );
    await assertFails(
      updateDoc(existingRef, { category_name: 'Changed' }),
    );
    await assertFails(deleteDoc(existingRef));
  });

  it('denies anonymous category word read, create, update, and delete', async () => {
    await seedDocuments([
      [`categories/anon_category`, categoryData(anonymousUid)],
      [
        `categories/anon_category/words/existing_word`,
        wordData(anonymousUid),
      ],
    ]);
    const db = authDb(anonymousUid, true);
    const existingRef = doc(
      db,
      'categories',
      'anon_category',
      'words',
      'existing_word',
    );

    await assertFails(getDoc(existingRef));
    await assertFails(
      setDoc(
        doc(
          db,
          'categories',
          'anon_category',
          'words',
          'new_word',
        ),
        wordData(anonymousUid, 'mnemonic'),
      ),
    );
    await assertFails(
      updateDoc(existingRef, wordData(anonymousUid, 'lexicon')),
    );
    await assertFails(deleteDoc(existingRef));
  });

  it('denies anonymous user from creating telemetry events or writing to shared collections', async () => {
    const anonDb = authDb(anonymousUid, true);
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
    const db = authDb(bob);

    await assertFails(
      updateDoc(
        doc(db, 'state', alice),
        { selectedWallpaper: 'wallpaper_neon.png' },
      ),
    );
  });
});

describe('admin-seeded shared content contract', () => {
  for (const [identity, isAnonymous] of [
    ['registered', false],
    ['anonymous', true],
  ]) {
    for (const [collectionName, existingId, createId, dataFactory] of [
      ['vocabulary', 'seeded_vocab', 'client_vocab', vocabularyData],
      ['global_words', 'seeded_word', 'client_word', globalWordData],
    ]) {
      it(`denies ${identity} client mutations to ${collectionName}`, async () => {
        await seedDocuments([
          [`${collectionName}/${existingId}`, dataFactory()],
        ]);
        const uid = isAnonymous ? anonymousUid : alice;
        const db = authDb(uid, isAnonymous);
        const existingRef = doc(db, collectionName, existingId);

        await assertFails(
          setDoc(
            doc(db, collectionName, createId),
            dataFactory('client-created'),
          ),
        );
        await assertFails(
          setDoc(existingRef, dataFactory('client-overwrite')),
        );
        await assertFails(deleteDoc(existingRef));
      });
    }

    it(`allows ${identity} signed-in reads of admin-seeded shared content`, async () => {
      await seedDocuments([
        ['vocabulary/seeded_vocab', vocabularyData()],
        ['global_words/seeded_word', globalWordData()],
      ]);
      const uid = isAnonymous ? anonymousUid : alice;
      const db = authDb(uid, isAnonymous);

      const vocabulary = await assertSucceeds(
        getDoc(doc(db, 'vocabulary', 'seeded_vocab')),
      );
      const globalWord = await assertSucceeds(
        getDoc(doc(db, 'global_words', 'seeded_word')),
      );
      if (!vocabulary.exists() || !globalWord.exists()) {
        throw new Error('Admin-seeded shared content was not readable.');
      }
    });
  }

  it('keeps unknown and research collections recursively denied', async () => {
    const db = authDb();

    await assertFails(
      setDoc(doc(db, 'research_events', 'event_1'), {
        outcome: 'correct',
      }),
    );
    await assertFails(getDoc(doc(db, 'unknown_collection', 'document_1')));
  });
});
