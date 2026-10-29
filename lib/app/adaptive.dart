import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Platform selection belongs in this layer, never in domain code.
class Adaptively extends StatelessWidget {
  const Adaptively({
    required this.ios,
    required this.android,
    required this.windows,
    super.key,
  });
  final WidgetBuilder ios, android, windows;
  @override
  Widget build(BuildContext context) => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => ios(context),
    TargetPlatform.android || TargetPlatform.fuchsia => android(context),
    TargetPlatform.windows || TargetPlatform.linux => windows(context),
  };
}

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
    child: Adaptively(
      ios: (_) => selected
          ? cupertino.CupertinoButton.filled(
              onPressed: onPressed,
              child: Text(label),
            )
          : cupertino.CupertinoButton(onPressed: onPressed, child: Text(label)),
      android: (_) => selected
          ? material.FilledButton(onPressed: onPressed, child: Text(label))
          : material.TextButton(onPressed: onPressed, child: Text(label)),
      windows: (_) => selected
          ? fluent.FilledButton(onPressed: onPressed, child: Text(label))
          : fluent.Button(onPressed: onPressed, child: Text(label)),
    ),
  );
}

class AdaptiveField extends StatelessWidget {
  const AdaptiveField({
    required this.label,
    this.controller,
    this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    super.key,
  });
  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Semantics(
      label: label,
      child: Adaptively(
        ios: (_) => cupertino.CupertinoTextField(
          controller: controller,
          placeholder: label,
          onChanged: onChanged,
          maxLines: maxLines,
          keyboardType: keyboardType,
        ),
        android: (_) => material.TextField(
          controller: controller,
          decoration: material.InputDecoration(labelText: label),
          onChanged: onChanged,
          maxLines: maxLines,
          keyboardType: keyboardType,
        ),
        windows: (_) => fluent.TextBox(
          controller: controller,
          placeholder: label,
          onChanged: onChanged,
          maxLines: maxLines,
          keyboardType: keyboardType,
        ),
      ),
    ),
  );
}

/// A scrollable native dialog. Escape always cancels, including on iOS.
class AdaptiveDialog extends StatefulWidget {
  const AdaptiveDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.controllers = const [],
    super.key,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;
  final List<TextEditingController> controllers;
  @override
  State<AdaptiveDialog> createState() => _AdaptiveDialogState();
}

class _AdaptiveDialogState extends State<AdaptiveDialog> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final content = widget.content;
    final actions = widget.actions;
    final scroll = SingleChildScrollView(child: content);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Adaptively(
        ios: (_) => cupertino.CupertinoAlertDialog(
          title: Text(title),
          content: scroll,
          actions: [
            for (final action in actions)
              if (action is AdaptiveButton)
                cupertino.CupertinoDialogAction(
                  key: action.key,
                  onPressed: action.onPressed,
                  isDefaultAction: action.label == 'Save',
                  child: Text(action.label),
                )
              else
                action,
          ],
        ),
        android: (_) => material.AlertDialog(
          title: Text(title),
          content: scroll,
          actions: actions,
          scrollable: true,
        ),
        windows: (_) => fluent.ContentDialog(
          title: Text(title),
          content: scroll,
          actions: actions,
        ),
      ),
    );
  }
}

Future<T?> showAdaptiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS =>
    cupertino.showCupertinoDialog<T>(context: context, builder: builder),
  TargetPlatform.windows || TargetPlatform.linux => fluent.showDialog<T>(
    context: context,
    builder: builder,
  ),
  TargetPlatform.android || TargetPlatform.fuchsia => material.showDialog<T>(
    context: context,
    builder: builder,
  ),
};

/// Destructive choices use an iOS action sheet and native dialogs elsewhere.
Future<bool?> confirmAdaptiveDelete(BuildContext context, String title) {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return cupertino.showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => cupertino.CupertinoActionSheet(
        title: Text(title),
        actions: [
          cupertino.CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
  return showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AdaptiveDialog(
      title: title,
      content: const Text('This cannot be undone.'),
      actions: [
        AdaptiveButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AdaptiveButton(
          label: 'Delete',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
}

Route<T> adaptivePageRoute<T>(WidgetBuilder builder) =>
    switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => cupertino.CupertinoPageRoute<T>(builder: builder),
      TargetPlatform.windows ||
      TargetPlatform.linux => fluent.FluentPageRoute<T>(builder: builder),
      _ => material.MaterialPageRoute<T>(builder: builder),
    };

/// Native page chrome, safe areas, focus traversal, and page command shortcuts.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.onBack,
    this.actionLabel,
    this.onAction,
    this.largeTitle = false,
    super.key,
  });
  final String title;
  final Widget body;
  final VoidCallback? onBack, onAction;
  final String? actionLabel;
  final bool largeTitle;
  @override
  Widget build(BuildContext context) {
    final content = FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: body,
    );
    final action = onAction == null
        ? null
        : AdaptiveButton(
            key: const Key('page-action'),
            label: actionLabel!,
            onPressed: onAction,
          );
    final iosAction = onAction == null
        ? null
        : Semantics(
            key: const Key('page-action'),
            label: actionLabel,
            button: true,
            child: cupertino.CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAction,
              child: Icon(
                actionLabel == 'Edit recipe'
                    ? cupertino.CupertinoIcons.pencil
                    : cupertino.CupertinoIcons.add,
              ),
            ),
          );
    final page = Adaptively(
      ios: (_) => largeTitle
          ? cupertino.CupertinoPageScaffold(
              child: SafeArea(
                top: false,
                child: CustomScrollView(
                  slivers: [
                    cupertino.CupertinoSliverNavigationBar(
                      largeTitle: Text(title),
                      trailing: iosAction,
                    ),
                    SliverFillRemaining(hasScrollBody: true, child: content),
                  ],
                ),
              ),
            )
          : cupertino.CupertinoPageScaffold(
              navigationBar: cupertino.CupertinoNavigationBar(
                middle: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: onBack == null
                    ? null
                    : cupertino.CupertinoNavigationBarBackButton(
                        key: const Key('page-back'),
                        onPressed: onBack,
                      ),
                trailing: iosAction,
              ),
              child: SafeArea(child: content),
            ),
      android: (_) => material.Scaffold(
        appBar: material.AppBar(
          title: Text(title),
          leading: onBack == null
              ? null
              : material.BackButton(
                  key: const Key('page-back'),
                  onPressed: onBack,
                ),
          actions: [?action],
        ),
        body: SafeArea(child: content),
      ),
      windows: (_) => fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: Text(title),
          commandBar: fluent.CommandBar(
            overflowBehavior: fluent.CommandBarOverflowBehavior.wrap,
            isCompact:
                MediaQuery.sizeOf(context).width < 720 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.5,
            primaryItems: [
              if (onBack != null)
                fluent.CommandBarButton(
                  key: const Key('page-back'),
                  tooltip: 'Back',
                  icon: const Icon(fluent.FluentIcons.back),
                  label: const Text('Back'),
                  onPressed: onBack,
                ),
              if (onAction != null)
                fluent.CommandBarButton(
                  key: const Key('page-action'),
                  tooltip: actionLabel,
                  icon: Icon(
                    actionLabel == 'Edit recipe'
                        ? fluent.FluentIcons.edit
                        : fluent.FluentIcons.add,
                  ),
                  label: Text(actionLabel!),
                  onPressed: onAction,
                ),
            ],
          ),
        ),
        content: SafeArea(child: content),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            ?onAction,
        const SingleActivator(LogicalKeyboardKey.escape): ?onBack,
      },
      child: Focus(autofocus: true, child: page),
    );
  }
}

/// Native Windows secondary-click menu; actions remain reachable by keyboard.
class AdaptiveContextMenu extends StatefulWidget {
  const AdaptiveContextMenu({
    required this.child,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });
  final Widget child;
  final VoidCallback onEdit, onDelete;
  @override
  State<AdaptiveContextMenu> createState() => _AdaptiveContextMenuState();
}

class _AdaptiveContextMenuState extends State<AdaptiveContextMenu> {
  final controller = fluent.FlyoutController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void showMenu() => controller.showFlyout(
    builder: (ctx) => fluent.MenuFlyout(
      items: [
        fluent.MenuFlyoutItem(
          text: const Text('Edit'),
          onPressed: () {
            Navigator.pop(ctx);
            widget.onEdit();
          },
        ),
        fluent.MenuFlyoutItem(
          text: const Text('Delete'),
          onPressed: () {
            Navigator.pop(ctx);
            widget.onDelete();
          },
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Adaptively(
    ios: (_) => widget.child,
    android: (_) => widget.child,
    windows: (_) => fluent.FlyoutTarget(
      controller: controller,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): showMenu,
        },
        child: GestureDetector(
          onSecondaryTapUp: (_) => showMenu(),
          child: widget.child,
        ),
      ),
    ),
  );
}

class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({
    required this.index,
    required this.onChanged,
    required this.child,
    super.key,
  });
  final int index;
  final ValueChanged<int> onChanged;
  final Widget child;
  static const labels = ['Recipes', 'Planner', 'Shopping'];
  static const ids = ['recipes', 'planner', 'shopping'];
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (var i = 0; i < labels.length; i++)
        SingleActivator(
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
          ][i],
          control: true,
        ): () =>
            onChanged(i),
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Adaptively(
          ios: (_) => wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 168,
                      child: SafeArea(
                        child: cupertino.CupertinoListSection(
                          children: [
                            for (var i = 0; i < labels.length; i++)
                              AdaptiveButton(
                                key: Key('nav-${ids[i]}'),
                                label: labels[i],
                                selected: i == index,
                                onPressed: () => onChanged(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: child),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: child),
                    cupertino.CupertinoTabBar(
                      currentIndex: index,
                      onTap: onChanged,
                      items: [
                        for (var i = 0; i < labels.length; i++)
                          cupertino.BottomNavigationBarItem(
                            icon: Icon(
                              [
                                cupertino.CupertinoIcons.book,
                                cupertino.CupertinoIcons.calendar,
                                cupertino.CupertinoIcons.cart,
                              ][i],
                              key: Key('nav-${ids[i]}'),
                            ),
                            label: labels[i],
                          ),
                      ],
                    ),
                  ],
                ),
          android: (_) => wide
              ? Row(
                  children: [
                    material.NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: onChanged,
                      labelType: material.NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          material.NavigationRailDestination(
                            icon: Icon(
                              [
                                material.Icons.menu_book,
                                material.Icons.calendar_month,
                                material.Icons.shopping_cart,
                              ][i],
                              key: Key('nav-${ids[i]}'),
                            ),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                    Expanded(child: child),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: child),
                    material.NavigationBar(
                      selectedIndex: index,
                      onDestinationSelected: onChanged,
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          material.NavigationDestination(
                            key: Key('nav-${ids[i]}'),
                            icon: Icon(
                              [
                                material.Icons.menu_book,
                                material.Icons.calendar_month,
                                material.Icons.shopping_cart,
                              ][i],
                            ),
                            label: labels[i],
                          ),
                      ],
                    ),
                  ],
                ),
          windows: (_) => fluent.NavigationView(
            titleBar: const fluent.TitleBar(title: Text('Meal Queue')),
            pane: fluent.NavigationPane(
              displayMode: wide
                  ? fluent.PaneDisplayMode.expanded
                  : fluent.PaneDisplayMode.compact,
              selected: index,
              onChanged: onChanged,
              items: [
                for (var i = 0; i < labels.length; i++)
                  fluent.PaneItem(
                    key: Key('nav-${ids[i]}'),
                    icon: Icon(
                      [
                        fluent.FluentIcons.library,
                        fluent.FluentIcons.calendar,
                        fluent.FluentIcons.shopping_cart,
                      ][i],
                    ),
                    title: Text(labels[i]),
                    body: const SizedBox.shrink(),
                  ),
              ],
            ),
            paneBodyBuilder: (_, _) => child,
          ),
        );
      },
    ),
  );
}

class AdaptiveCheckbox extends StatelessWidget {
  const AdaptiveCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Adaptively(
        ios: (_) =>
            cupertino.CupertinoSwitch(value: value, onChanged: onChanged),
        android: (_) => material.Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
        windows: (_) => fluent.Checkbox(
          checked: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
      ),
    ),
  );
}

/// Ctrl+S shares the same validated save callback as the visible button.
class AdaptiveSaveRegion extends StatelessWidget {
  const AdaptiveSaveRegion({
    required this.onSave,
    required this.child,
    super.key,
  });
  final VoidCallback onSave;
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
    },
    child: child,
  );
}

/// Fluent exposes contrast resources rather than a highContrastTheme app slot.
Widget fluentContrastBuilder(BuildContext context, Widget? child) {
  if (!MediaQuery.highContrastOf(context)) return child!;
  final theme = fluent.FluentTheme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final foreground = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  final background = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  final resources = dark
      ? const fluent.ResourceDictionary.dark(
          textFillColorPrimary: Color(0xFFFFFFFF),
          textFillColorSecondary: Color(0xFFFFFFFF),
          textFillColorTertiary: Color(0xFFFFFFFF),
          controlStrokeColorDefault: Color(0xFFFFFFFF),
          controlStrokeColorSecondary: Color(0xFFFFFFFF),
          controlStrongStrokeColorDefault: Color(0xFFFFFFFF),
          focusStrokeColorOuter: Color(0xFFFFFFFF),
          focusStrokeColorInner: Color(0xFF000000),
        )
      : const fluent.ResourceDictionary.light(
          textFillColorPrimary: Color(0xFF000000),
          textFillColorSecondary: Color(0xFF000000),
          textFillColorTertiary: Color(0xFF000000),
          controlStrokeColorDefault: Color(0xFF000000),
          controlStrokeColorSecondary: Color(0xFF000000),
          controlStrongStrokeColorDefault: Color(0xFF000000),
          focusStrokeColorOuter: Color(0xFF000000),
          focusStrokeColorInner: Color(0xFFFFFFFF),
        );
  return fluent.FluentTheme(
    data: theme.copyWith(
      resources: resources,
      scaffoldBackgroundColor: background,
      menuColor: background,
      inactiveColor: foreground,
    ),
    child: child!,
  );
}
