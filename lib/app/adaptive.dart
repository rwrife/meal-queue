import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/cupertino.dart' show showCupertinoDialog;
import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;

/// Choose native dialog host without imposing Material on Cupertino/Fluent.
Future<T?> showAdaptiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS || TargetPlatform.macOS:
      return showCupertinoDialog<T>(context: context, builder: builder);
    case TargetPlatform.windows || TargetPlatform.linux:
      return fluent.showDialog<T>(context: context, builder: builder);
    case TargetPlatform.android || TargetPlatform.fuchsia:
      return material.showDialog<T>(context: context, builder: builder);
  }
}

/// Keep native widget choices in one place as feature screens arrive.
class Adaptively extends StatelessWidget {
  const Adaptively({
    required this.ios,
    required this.android,
    required this.windows,
    super.key,
  });

  final WidgetBuilder ios;
  final WidgetBuilder android;
  final WidgetBuilder windows;

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS || TargetPlatform.macOS:
        return ios(context);
      case TargetPlatform.android || TargetPlatform.fuchsia:
        return android(context);
      case TargetPlatform.windows || TargetPlatform.linux:
        return windows(context);
    }
  }
}
