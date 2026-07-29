# Firestore Client Access Inventory

Updated: 2026-07-28

## Scope summary

- This inventory catalogs every Firestore collection, document, and field
  read or written by the Flutter client under `lib/`, so that captured
  production security rules can be validated field-by-field before deploy.
- `firestore.rules` and `firebase.json` now capture the proposed repository
  policy. This inventory remains the compatibility baseline for emulator tests
  and comparison with the currently deployed project rules before release.
- The Node seed script `lib/add_default_categories.js` runs under the
  Firebase Admin SDK and bypasses security rules; it is out of client-rule
  scope. Note it writes a different category shape (`name` + `words` array)
  than the client reads (`category_name` + `words` subcollection), so its
  output is not consumable by the app regardless of rules.

## Identity model

All Firestore access follows a Firebase Auth sign-in (`FirebaseAuth.instance`).
Firebase anonymous authentication is used to enter the product shell and may
read shared, admin-seeded content. An anonymous Firebase identity is a guest,
not a registered owner: it cannot read or persist remote profile, state,
purchase, category, category-word, or telemetry records. Guest learning data
must remain local. Ownership is expressed inconsistently across collections,
which is the dominant compatibility risk for any ownership rule.

## Per-collection access

### `users/{uid}` — owned by document id
- Write `set` (AuthService.registerUser): `first_name`, `last_name`,
  `email`, `age`, `createdAt` (server timestamp).
- Unused legacy helper `UserService.saveUserData` attempts `first_name`,
  `last_name`, `email`, and `points`; it omits required `age` and `createdAt`,
  so current create rules reject the payload.
- No active quiz path writes `points`, `totalPoints`, or `gamesPlayed`.
  Existing legacy counter fields remain readable for compatibility but cannot
  be added, changed, or removed by a client. They remain non-authoritative
  until the trusted-writer migration reconciles them.
- Read (UserService.getUserData, SettingScreen): `first_name`, `last_name`,
  `email`, `age`, `points`.
- **Rule note:** no owner field is stored. A rule must key on the path
  wildcard `match /users/{userId}` with `userId == request.auth.uid`.

### `state/{uid}` — owned by document id; NO stored owner field
- ScoreScreen no longer writes this collection; completed-session progress is
  stored locally through `ProgressRepository`.
- Write `update` (SelectWallpaperScreen._setWallpaper): `selectedWallpaper`
  (nullable; may be written as null).
- Dormant legacy write: ShopPage._buyProduct attempts a negative
  `totalPoints` increment. `RemoteEconomyPolicy` closes the screen and
  Firestore rules deny the write.
- Read (dormant ShopPage, UserService.getTotalPointsFromState,
  quiz_screen._loadBackground): `totalPoints`, `selectedWallpaper`.
- **Rule note:** the document carries no `uid`/`user_id`. A rule anchored on
  a stored owner field rejects every access. The repository rule keys owner
  reads on `state/{userId}`, denies client create/delete and counter changes,
  and permits only a `selectedWallpaper`-only update. The wallpaper write uses
  `.update()` and therefore requires a pre-existing legacy or trusted-writer
  document.

### `categories/{categoryId}` — owned by stored `uid`
- Write `set` (CategoryService.addCategory / addCategoryForUser /
  addDefaultCategoriesForNewUser): `category_name`, `created_at`
  (**client** `Timestamp.now()`, not server), `uid`.
- Read (CategoryService.getCategoriesStream, SelectCategoryForQuiz):
  `.where('uid', isEqualTo: user.uid)`; field `category_name`.
- Delete (CategoryService.deleteCategory): by id, no client ownership
  verification.
- **Rule note:** `created_at` is client time; a rule asserting a server
  timestamp rejects creates. Delete must be owner-gated server-side.

### `categories/{categoryId}/words/{wordId}` — owned by stored `user_id`
- Write `set` via Word.toMap (WordService.addWord / addMultipleWords,
  CategoryService.addWord / addCategoryForUser / addDefaultCategoriesForNewUser):
  `word`, `meaning`, `part_of_speech`, `user_id`, `is_global`, `created_at`
  (client). Datamuse variants additionally write a camelCase `userId: ""`,
  producing dead duplicate data alongside `user_id`.
- Reads are **unfiltered** collection scans (WordService.getWordsStream /
  getAllWords / canAddMoreWords / deleteAllWords; VocabService.getVocabFromCategory;
  CategoriesPage.getWordCount; SelectCategoryForQuiz `.count()`).
- Update (WordService.updateWord): full `Word.toMap()`.
- **Rule note:** a list rule on `resource.data.user_id` rejects the
  unfiltered reads. A viable least-privilege design gates word access on the
  parent category's `uid` via `get(/databases/(db)/documents/categories/$(categoryId))`,
  which is a per-query constant and therefore satisfiable for list queries.

### `vocabulary/{vocabId}` — shared, admin-seeded read-only content
- Legacy client write attempt `add` (main_vocabulary): `word`, `meaning`,
  `part_of_speech`. **No `uid` field.** Repository rules intentionally deny
  this path; only a controlled Firebase Admin import may seed the collection.
- Read (VocabService.getRandomVocab): `.where('uid', isEqualTo: user.uid)`.
- Read (QuizService.generateQuizQuestions, choose_mode_screen):
  `.get()` with **no** filter.
- **Rule note:** signed-in registered and anonymous identities may read the
  shared pool. Client create, update, and delete are denied. The inconsistent
  filtered reader remains a client/data-model defect; do not resolve it by
  granting a client write path.

### `quiz/{quizId}` — denied legacy global append
- Legacy write attempt `add` (QuizService.saveQuestionToFirestore): `word`,
  `options` (array), `correctAnswer`, `createdAt` (server timestamp). No `uid`.
- No client reads.
- **Rule note:** all client access remains denied because the writer is dead
  code and has no owner scope. A future quiz bank must use a controlled import.

### `global_words/{word}` — shared, admin-seeded read-only dictionary
- Read (GlobalWordService.findWordInDatabase): get by doc id (= word).
- Legacy client write attempt `set` (GlobalWordService.addWordToDatabase):
  `word`, `meaning`,
  `partOfSpeech` (camelCase), `createdAt` (server timestamp). No `uid`;
  repository rules intentionally deny this cache-miss path.
- **Rule note:** signed-in registered and anonymous identities may read.
  Client create, update, and delete are denied; controlled Admin import is the
  only seeding path.

### `products/{productId}` — signed-in read-only catalog
- Read (ShopPage._fetchProducts): unfiltered `.get()`; `name`, `price`,
  `image_name`, `image_url`.
- Read (SelectWallpaperScreen): get by id; `image_url`, `image_name`.
- Legacy write attempt `set merge` (ShopPage._seedDefaultProducts, triggered
  on empty products and via the restore button): `name`, `image_name`,
  `image_url`, `price`, `createdAt` (server timestamp). No ownership.
- **Rule note:** signed-in reads are allowed and all client writes are denied.
  Product seeding is an Admin operation; dormant client seeding falls back to
  in-app defaults.

### `purchased_items/{purchaseId}` — owned by stored `user_id`
- Dormant legacy write: ShopPage._buyProduct attempts a transactional `set`
  with `user_id`, `product_id`, `total_price`, and `created_at`; repository
  rules deny every client write.
- Read (ShopPage._buyProduct): `.where('user_id', isEqualTo: uid).where(
  'product_id', isEqualTo: productId)`.
- Read (SelectWallpaperScreen): `.where('user_id', isEqualTo: uid)`; `product_id`.
- **Rule note:** owner reads remain satisfiable for these filtered queries;
  create, update, and delete are denied until a trusted server writer exists.

### `voice_telemetry_events/{eventId}` — global append, no owner in payload
- Write `add` (FirestoreVoiceTelemetrySink): the VoiceTelemetryEvent.toMap
  allowlist (`schemaVersion`, `outcome`, `mode`, `requestedEngine`,
  `actualEngine`, `usedFallback`, `fallbackReason`, `failureCategory`,
  `cacheHit`, `latencyMs`, `contentId`, `contentType`, `requestId`,
  `modelVersion`, `occurredAtUtc` ISO-8601 UTC). No `uid`/`user_id`.
- No reads. Write failures are swallowed by design.
- **Rule note:** registered-user create is allowed with no payload ownership
  field. Anonymous creates and every client read/update/delete are denied.

## Required production verification

Export and version-control the deployed Firestore rules, then reconcile
against this inventory. Confirm that:

- `users`, `state`, and `products` reads are keyed on document id (path
  wildcard), not a stored owner field;
- anonymous guests retain shared `vocabulary`, `global_words`, and `products`
  reads but cannot access or persist remote private learning records;
- legacy `users` counters are preserved unchanged during validated profile
  updates and cannot be added, changed, or removed by clients;
- `state` denies client creation and counter mutation while preserving only
  owner reads and `selectedWallpaper`-only updates;
- `purchased_items` preserves owner-filtered legacy reads and denies every
  client write;
- `categories/words` list rules are satisfiable for the unfiltered client
  reads (parent-category lookup) without leaking cross-user words;
- `vocabulary` and `global_words` remain client-read-only and are populated
  only by an inventoried, controlled Admin SDK import;
- `quiz` remains denied, `products` remains client-read-only, and
  `voice_telemetry_events` remains registered-user create-only;
- client-time `created_at` writes are not rejected by a server-timestamp
  assertion;
- every deployed Firebase Admin SDK or other privileged writer that bypasses
  client rules is inventoried and reconciled with this policy.
