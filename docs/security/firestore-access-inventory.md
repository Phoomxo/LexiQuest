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
There is no anonymous-data path. Ownership is expressed inconsistently across
collections, which is the dominant compatibility risk for any ownership rule.

## Per-collection access

### `users/{uid}` — owned by document id
- Write `set` (AuthService.registerUser): `first_name`, `last_name`,
  `email`, `age`, `createdAt` (server timestamp).
- Unused legacy helper `UserService.saveUserData` attempts `first_name`,
  `last_name`, `email`, and `points`; it omits required `age` and `createdAt`,
  so current create rules reject the payload.
- No active quiz path writes `points`, `totalPoints`, or `gamesPlayed`.
  Firestore rules still accept some legacy owner counter updates, so these
  fields remain non-authoritative until the trusted-writer migration.
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

### `vocabulary/{vocabId}` — inconsistent ownership
- Write `add` (main_vocabulary): `word`, `meaning`, `part_of_speech`.
  **No `uid` field.**
- Read (VocabService.getRandomVocab): `.where('uid', isEqualTo: user.uid)`.
- Read (QuizService.generateQuizQuestions, choose_mode_screen):
  `.get()` with **no** filter.
- **Rule note:** no single ownership rule satisfies all three paths.
  Keying on `uid` blocks both the unfiltered reads and the writes. This is a
  data-model defect; do not resolve it by widening public access.

### `quiz/{quizId}` — global append, no ownership
- Write `add` (QuizService.saveQuestionToFirestore): `word`, `options`
  (array), `correctAnswer`, `createdAt` (server timestamp). No `uid`.
- No client reads.
- **Rule note:** must allow authenticated create with no ownership, or quiz
  generation silently drops (failure is caught and swallowed).

### `global_words/{word}` — global read/write cache, no ownership
- Read (GlobalWordService.findWordInDatabase): get by doc id (= word).
- Write `set` (GlobalWordService.addWordToDatabase): `word`, `meaning`,
  `partOfSpeech` (camelCase), `createdAt` (server timestamp). No `uid`;
  any user may overwrite any word.
- **Rule note:** must allow authenticated read and create/update, or the
  dictionary-cache path errors.

### `products/{productId}` — public read, client-initiated seed
- Read (ShopPage._fetchProducts): unfiltered `.get()`; `name`, `price`,
  `image_name`, `image_url`.
- Read (SelectWallpaperScreen): get by id; `image_url`, `image_name`.
- Write `set merge` (ShopPage._seedDefaultProducts, triggered on empty
  products and via the restore button): `name`, `image_name`, `image_url`,
  `price`, `createdAt` (server timestamp). No ownership.
- **Rule note:** must allow authenticated read and merge-write, or shop
  seeding silently fails (falls back to in-app defaults) and shop/wallpaper
  reads degrade to defaults.

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
- **Rule note:** must allow authenticated create with no ownership
  requirement, or telemetry is silently dropped.

## Required production verification

Export and version-control the deployed Firestore rules, then reconcile
against this inventory. Confirm that:

- `users`, `state`, and `products` reads are keyed on document id (path
  wildcard), not a stored owner field;
- `state` denies client creation and counter mutation while preserving only
  owner reads and `selectedWallpaper`-only updates;
- `purchased_items` preserves owner-filtered legacy reads and denies every
  client write;
- `categories/words` list rules are satisfiable for the unfiltered client
  reads (parent-category lookup) without leaking cross-user words;
- `quiz`, `global_words`, `products` (seed), and `voice_telemetry_events`
  retain authenticated no-ownership access, or accept the corresponding
  client-path regressions explicitly;
- the `vocabulary` ownership contradiction is resolved in the data model
  before any ownership rule is applied to it;
- client-time `created_at` writes are not rejected by a server-timestamp
  assertion.
