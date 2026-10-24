# Meal Queue

Offline weekly meal planner and shopping-list generator for home cooks who keep
their own recipes and want the week's shopping done from what they actually own.

**Pitch:** Home cooks who plan meals by hand use bloated recipe platforms with
accounts, subscriptions, and imported junk; Meal Queue keeps your own recipes
locally, lets you lay out a week on phone, tablet, or Windows, and turns that
plan into one merged, scaled shopping list that nudges you to use up what is
already in the pantry and freezer first - no accounts, no cloud.

## Motivation

Meal-planning apps mostly solve the wrong problem. They push recipe discovery,
ads, and subscription paywalls, then ask you to log into them. The actual weekly
chore is narrower: pick meals you already know your household eats, notice what
you already have, and produce a shopping list that is not missing half an
ingredient and does not tell you to buy garlic again. That loop works fine on a
phone in the shop, better on a tablet at the counter, and best on a desktop when
you are dragging a month of dinners together. It also should not require an
account, a tracker, or a network connection.

## Target users

- Households that cook from their own recurring recipes and rotate them weekly.
- People who shop from a phone and want one merged list, not one list per recipe.
- Anyone tracking freezer and pantry stock who wants "use this first" prompts
  instead of duplicate purchases.
- Users who refuse cloud-only food apps and want portable, exportable data.

## Concrete use cases

1. **Sunday plan.** Open the planner on the tablet, drag last week's dinners into
   the week grid, add two leftovers slots, adjust servings from 2 to 5.
2. **One list.** Tap *Make list*: ingredients merge across meals by item and unit,
   scale with servings, and sort by aisle group you defined once.
3. **Shop.** On the phone at the store, tick items off; the list stays checked and
   survives the app being killed mid-aisle.
4. **Eat and record.** Mark a meal cooked from the plan; the meal gains a
   "cooked N times, last on <date>" history line for future rotation.
5. **Use-first nudge.** Half a bag of frozen peas is logged in the freezer; the
   plan shows a badge on meals that would consume it, before you buy more.

## How to use (intended workflow)

1. Add your recipes once (name, ingredients with quantity + unit, free-form
   steps, tags, optional photo). No import service, no scraping.
2. Log pantry/freezer stock loosely - item, quantity, unit, optional location and
   date. Optional, but it unlocks the use-first nudges and duplicate warnings.
3. Build a week: pick recipes into day slots (breakfast/lunch/dinner), set
   servings per meal, add "leftovers" or "eat out" slots.
4. Generate the shopping list; review the merged lines, edit or add extras, then
   shop with checkboxes.
5. Mark cooked meals. Repeat next week - last week's plan is a one-tap starting
   template.

## MVP features

- Local recipe library: title, ingredients (quantity/unit/item), steps, tags,
  photo, servings. Search and tag filter.
- Week planner with per-meal recipe assignment, servings override, leftovers and
  eat-out slots, copy-previous-week.
- Shopping list: ingredient merge by item + unit, serving-scale math, manual
  extra lines, aisle grouping, checkboxes with durable check state.
- Pantry/freezer stock log with optional expiry/freezer dates; use-first badges
  on meals and "already have" markers on list lines.
- Cook history per recipe (count, last cooked) and simple week archive.
- Adaptive layout for phone, tablet, and desktop windows; touch plus full
  keyboard/mouse control on Windows.
- JSON export/import of all data (recipes, plans, lists, stock, history).
- Platform-native look per OS (see UX strategy in PLAN.md).

## Non-goals

- No recipe import from websites, no barcode/OCR scanning, no photo recipe OCR.
- No nutrition, calorie, allergen, or diet analysis.
- No health, medical, or dietary-advice claims; this is a planning tool, not
  medical or nutrition guidance.
- No accounts, cloud sync, collaboration, or shared household servers.
- No grocery ordering, price tracking, store APIs, or payment integration.
- No recommendation engine, no AI-generated recipes, no ads or trackers.

## Privacy, permissions, and data storage

- **No network requests.** The app performs none; there is no analytics or ad SDK.
- All data lives in a local SQLite database inside app storage. Backups are
  user-initiated file exports (JSON), restored only by explicit user import.
- **Permissions:** photo/camera access only if the user adds a recipe photo (and
  only on mobile where a picker is required); file save/open for export and
  import via the platform picker. No location, contacts, camera roll browsing,
  notifications beyond optional local plan reminders, no background activity.
- Recipe photos are stored in app storage, never uploaded, and deleted with the
  recipe and on export opt-out.
- Uninstall or delete-data removes everything; export first if you want to keep it.

## Current status

Flutter skeleton in place (windows/android/ios, empty adaptive shell, CI). No
features yet; the milestone list and backlog live in PLAN.md and the issue
tracker.

1. **M0 Scaffold (done):** Flutter project (windows/android/ios), CI, toolchain pins.
2. **M1 Domain:** local database, repository/stock/history entities + tests.
3. **M2 Recipes:** library CRUD, search, photos.
4. **M3 Planner:** week grid, slots, servings, copy-week.
5. **M4 List:** merge/scale/aisle/checkboxes, stock interplay.
6. **M5 Polish:** adaptive per-OS UX verification, accessibility, backup/restore.
7. **M6 Release:** Windows build on a `v*` GitHub release.

## Quickstart (development)

```bash
flutter --version            # pinned 3.47.7 stable, see toolchain.json
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
flutter build apk --debug
```

Host-side Linux checks run inside Docker (`dart:stable` for analyzer/unit-test
smoke checks; a pinned Flutter image where the Windows lanes cannot substitute).
See PLAN.md for CI layout and packaging.

## Identifier

Android applicationId, iOS bundle identifier, and Windows/MSIX identity derive
from `com.infinityball.mealqueue` (App Store Connect registration: `CREATED
com.infinityball.mealqueue`, 2026-10-24).

## License

MIT - see LICENSE.
