# Adaptive UX contract

Meal Queue follows PLAN.md strategy A. Use `lib/app/adaptive.dart` for every
screen's page chrome, buttons, fields, dialogs, selection controls and routes.
Keep repositories, quantity calculations, snapshots, persistence and widget IDs
independent of platform selection. No new dependencies were needed: the existing
`fluent_ui` package provides Windows controls and their focus/hover behavior.

- iOS: Cupertino large navigation titles on top-level pages, tab bar on compact
  windows, sidebar on wider windows, Cupertino fields/dialogs, destructive action
  sheets, safe areas and Cupertino routes with edge swipe-back for recipe details,
  editors and stock. Use the system typography and text scaling.
- Android: Material 3, NavigationBar below 720 logical pixels and NavigationRail
  above it, standard page routes/back and Material dialogs.
- Windows: Fluent NavigationView (compact pane in narrow windows, open pane above
  720 pixels), title and page command bars, Fluent fields/buttons/dialogs. Recipe
  rows provide secondary-click and Shift+F10 Edit/Delete menus. Visible actions
  provide the same operations without a mouse.

At 720 logical pixels and above, recipe browsing keeps the library beside its
detail/editor. Smaller windows push separate routes. Forms and lists scroll;
actions and ingredient fields wrap rather than assuming a fixed phone width.
Do not clamp text scaling. Cupertino uses dynamic system colors; Android supplies
Material high-contrast color schemes; Fluent strengthens text, control borders
and focus outlines when the system requests high contrast. New content controls must have a readable label and a minimum 48-pixel target;
native navigation/title-bar controls keep their OS metrics. Checkbox/switch
labels identify the item they change. Preserve native focus
indicators and use reading-order focus traversal.

Keyboard: Tab/Shift+Tab move focus, Enter/Space activate native buttons,
Escape cancels dialogs or returns from a detail/editor, Ctrl+1/2/3 select Recipes,
Planner and Shopping, Ctrl+N invokes the page's new/edit command, and Ctrl+S saves
recipe and stock editors. Commands call the same validation and persistence
callbacks as the visible controls. Dialogs retain explicit Cancel actions.

`test/adaptive_widget_test.dart` covers all three target platforms at 390, 768
and 1280 logical pixels, at 100% and 200% text with high contrast enabled. It
renders recipe details/editors, stock, planner and shopping pages and dialogs, checks
native widget families, labeled shopping selection controls, iOS edge swipe and
action sheets, persisted checkbox changes, and Windows keyboard/menu/save journeys. Existing behavior tests
remain the persistence regression suite. These host widget tests do not certify
native Windows or iOS compilation, real device accessibility or OS window chrome.
