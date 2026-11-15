/// Closes the on-screen keyboard when the user taps outside a text field.
///
/// Flutter keeps a field focused (and the keyboard up) on a tap elsewhere on
/// phones. Android users can press Back, but iPhone has no Back key and its
/// number pad has no Done key, so the keyboard got stuck. Wrapped around the
/// whole app; buttons and fields still get their taps first (they win the
/// gesture arena over this outer recognizer).
library;

import 'package:flutter/widgets.dart';

class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
