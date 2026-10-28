# Task 3 Report: Replace Supabase wallpaper URL construction with truthful artwork

## Implementation summary

- Added the sealed `ProductArtwork` model and `resolveProductArtwork` resolver.
- Resolver accepts only trimmed HTTPS URLs with an authority and no user info; every other product payload, including legacy `image_name`, resolves to the built-in default.
- Replaced wallpaper screen Supabase URL construction with the resolver while retaining Firebase Firestore reads and state writes.
- The wallpaper selector now models default and network artwork explicitly, stores `null` for the default selection, and renders both sealed variants.

## RED/GREEN evidence

- RED: `flutter test test/shop/product_artwork_test.dart` exited 1 because `lib/shop/product_artwork.dart` and its resolver symbols did not exist.
- GREEN: `flutter test test/shop/product_artwork_test.dart test/screens/setting_screen_test.dart` exited 0 with 3 passing tests.
- Final focused verification after the review correction repeated the same command and exited 0 with 3 passing tests.

## Commands and results

| Command | Result |
| --- | --- |
| `dart format lib/shop/product_artwork.dart lib/screens/select_wallpaper_screen.dart test/shop/product_artwork_test.dart` | Completed successfully. |
| `flutter test test/shop/product_artwork_test.dart` | RED (expected missing-module compilation failure). |
| `flutter test test/shop/product_artwork_test.dart test/screens/setting_screen_test.dart` | GREEN: 3 tests passed. |
| `rg -n "Supabase|supabase|getPublicUrl" lib` | No matches. |
| `flutter test` | Passed: 696 tests. |
| `git diff --check` | No whitespace errors. |

## Files

- Created: `lib/shop/product_artwork.dart`
- Created: `test/shop/product_artwork_test.dart`
- Modified: `lib/screens/select_wallpaper_screen.dart`

## Self-review

- Focused review found no critical or important behavioral defects after restoring the original Thai UTF-8 text literals.
- Confirmed no Supabase import, API call, or `getPublicUrl` call remains in production `lib/`.
- Confirmed only a valid HTTPS `image_url` can become network artwork; `image_name` is never turned into a URL.
- Confirmed Firebase query and persistence paths are retained, and asynchronous UI changes are guarded by `mounted`.

## Concerns

- `supabase_flutter` remains listed in `pubspec.yaml` intentionally; the handoff specifies it remains until Task 4.
- Flutter reported 15 available dependency updates, which are outside this task's scope.
