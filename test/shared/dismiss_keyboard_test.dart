/// A tap outside a text field closes the keyboard (unfocuses the field);
/// buttons and other fields still get their taps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/shared/widgets/dismiss_keyboard.dart';

void main() {
  testWidgets('tapping outside unfocuses; buttons still work', (
    WidgetTester tester,
  ) async {
    int pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, Widget? child) => DismissKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const TextField(key: Key('a')),
              const TextField(key: Key('b')),
              TextButton(
                onPressed: () => pressed++,
                child: const Text('press'),
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
    EditableTextState field(String k) => tester.state<EditableTextState>(
      find.descendant(
        of: find.byKey(Key(k)),
        matching: find.byType(EditableText),
      ),
    );

    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(field('a').widget.focusNode.hasFocus, isTrue);

    // Another field takes focus normally.
    await tester.tap(find.byKey(const Key('b')));
    await tester.pump();
    expect(field('b').widget.focusNode.hasFocus, isTrue);

    // A button still gets its tap.
    await tester.tap(find.text('press'));
    await tester.pump();
    expect(pressed, 1);

    // Empty space closes the keyboard.
    await tester.tapAt(const Offset(400, 550));
    await tester.pump();
    expect(field('b').widget.focusNode.hasFocus, isFalse);
  });
}
