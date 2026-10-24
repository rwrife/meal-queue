import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
