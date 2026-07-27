const { after, before, beforeEach, describe, it } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'demo-lexiquest-rules-test';
const alice = 'alice_uid';
const productId = 'wallpaper_neon';
const purchaseId = `${alice}_${productId}`;
let testEnv;

function authDb(uid = alice) {
  return testEnv.authenticatedContext(uid).firestore();
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
