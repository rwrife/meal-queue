# Meal Queue - build plan

## Scope and architecture

Flutter 3.47.7 stable / Dart 3.13.5, one codebase with `windows/`, `android/`,
and `ios/` enabled in the first application-code issue. Windows 10/11 is the
primary CI/release target; Android phone/tablet and iOS/iPad are first-class
compilation targets. The app is fully offline; no backend, login, or network
permission required. Data lives in a local SQLite database, pictures as local
files. Plain Dart pure functions handle ingredient normalization, exact rational
serving scale, unit-aware aggregation, stock allocation, and list ordering;
presentation must not mutate those computations. Never subtract across unit
families or silently convert ambiguous items ("one bunch" vs grams); retain
separate lines and let user reconcile. Only user-checked stock affects a shopping
list, and generated lists freeze a snapshot so subsequent recipe edits cannot
rewrite an active trip.

## UX strategy: A - platform-native adaptive

Choose platform-native adaptive widgets, not a single themed phone UI. Use a
small adaptive-widget layer for shared screens:

- iPhone/iPad: Cupertino navigation, back gestures, action sheets, SF-style
  typography; tablet gets sidebar + detail; honor safe areas and Dynamic Type.
- Android: Material 3 with Android back, navigation bar and appropriate dialogs;
  tablet gets list/detail instead of blown-up phone cards.
- Windows: Fluent controls (`fluent_ui` if package is warranted), NavigationView,
  native title/command bars, context menu, hover and keyboard shortcuts; no
  faux mobile bottom nav. Review installed dependencies before adding packages.

Platform switching stays behind `AdaptiveScaffold`, `AdaptiveButton`, and
`AdaptiveDialog`, not repeated in domain code. Accessible focus order,
semantic labels on all checkboxes, high contrast, scalable text, and complete
keyboard navigation on Windows are required. Touch and keyboard/mouse actions
must reach the same plan/list behaviors. Native file pickers and platform
permissions only when invoked.

## Local model and backup

Tables: Recipe, Ingredient (quantity as numerator/denominator + unit + normalized
item key + display name), PlannedMeal (date, slot, servings, recipe ID or
leftovers/eat-out), StockLot (item, quantity/unit, location, optional date),
ShoppingList/ShoppingLine (frozen generation snapshot + checked + manual flag),
CookEvent. No telemetry fields. Store photos under app-owned storage, linked by
relative filenames; export a versioned ZIP with JSON plus image files; import
validates schema, path traversal, size and counts before replacing state, with a
recoverable backup of existing data. MVP may instead export JSON without photos
ONLY if UI and docs clearly label the omission before export. No automatic
cloud backup. Import/export acceptance tests include malformed data, round trip,
and no silent loss of check states.

## Milestones and dependencies

1. Flutter skeleton + `.github/workflows/ci.yml`: pinned stable version;
   windows/android/ios projects enabled; Windows `flutter test` +
   `flutter build windows --release` on `windows-latest`; Linux/Docker static
   checks and Android `flutter build apk --debug` in CI. Verify IDs.
2. Pure Dart recipe/ingredient/plan/list types and scale+merge tests.
3. Local persistence, CRUD, migration + recipe library and stock log.
4. Week planner, serving overrides, copy-week, cook history.
5. Shopping list snapshot, manual extras, aisle groups, checked-state recovery,
   conservative stock suggestions.
6. Adaptive OS-specific UI, golden/widget tests at phone/tablet/desktop sizes,
   semantic labels and keyboard journeys. App icon and listing copy review.
7. Backup/import with data-loss guard, Windows release Action, Android/iOS
   compilation; store submissions are later opt-in milestones.

## Testing strategy

- Pure Dart unit tests for quantity normalization, incompatible unit separation,
  rational scaling, deterministic stable sorting, snapshot immutability, stock
  allocation and migration/round-trip import.
- Widget/golden checks render key screens under `TargetPlatform.iOS`,
  `TargetPlatform.android`, `TargetPlatform.windows` at 390px, 768px, and 1280px
  widths respectively. No Material on iOS, no Cupertino on Android, no phone UI
  on Windows. Verify touch targets, full keyboard traversal, semantics, large
  text and high contrast.
- CI: Windows runner test/analyze/release build, Linux runner Android debug APK,
  host-side Linux probes in Docker. iOS simulator build later on macOS; until
  then, do not claim iOS compile green. No CI/hardware tests exist at scaffold.

## Packaging and distribution

Identifier `com.infinityball.mealqueue`: Android applicationId, iOS bundle ID,
Windows/MSIX identity derived from same prefix. ASC bundle registration:
`CREATED com.infinityball.mealqueue` (2026-10-24). Four GitHub Actions secret
names are `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`; values
never enter repository. `.github/workflows/release.yml` is an issue deliverable:
`v*` tag or manual dispatch -> `windows-latest` Flutter release build -> zipped
portable Windows artifact attached to GitHub release. App Store TestFlight and
Google Play submission are opt-in later milestones, not MVP gates.

Store copy starts in `AppStore/description.txt`, adjusted as features land. Real
`AppStore/icon.png` must be generated via OpenAI Images API with `spark-media
--project meal-queue image` after skeleton exists and inspected before wiring
Windows `.ico`, Android launcher/adaptive icons and iOS asset catalog. No
placeholder icon accepted as complete.

## Risks and explicit non-goals

- Alias/unit math can silently underbuy; conservative no-merge behavior wins.
- Local data can be lost on device failure; verified export/import and clear
  backup reminder before uninstall matter. Do not promise seamless sync.
- Adaptive layer can drift; per-platform golden tests are a release gate.
- No native Swift/Xcode-only app, React Native, Expo, Kotlin Multiplatform,
  .NET MAUI, Unity, Flutter web-only shell, hosted database, nutrition advice,
  grocery commerce, or AI recipe generation.
- No medical claims. Meal Queue does not diagnose, treat, or prescribe.
