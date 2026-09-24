import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/widgets/instant_page_swipe.dart';

void main() {
  testWidgets('short swipe works over selectable text without moving the page',
      (tester) async {
    final turns = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: InstantPageSwipe(
            enabled: true,
            onTurn: turns.add,
            child: const SelectionArea(
                child: Center(child: Text('Selectable text'))))));
    await tester.drag(find.byType(InstantPageSwipe), const Offset(-120, 0));
    expect(turns, [true]);
    await tester.drag(find.byType(InstantPageSwipe), const Offset(120, 0));
    expect(turns, [true, false]);
    await tester.tap(find.byType(InstantPageSwipe));
    await tester.drag(find.byType(InstantPageSwipe), const Offset(5, 150));
    expect(turns, [true, false]);
  });

  testWidgets('long press and multiple fingers never turn a page',
      (tester) async {
    final turns = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: InstantPageSwipe(
            enabled: true, onTurn: turns.add, child: const SizedBox.expand())));
    final hold = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 700));
    await hold.moveBy(const Offset(-120, 0),
        timeStamp: const Duration(milliseconds: 710));
    await hold.up(timeStamp: const Duration(milliseconds: 720));
    expect(turns, isEmpty);
    final one = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final two = await tester.startGesture(const Offset(220, 220), pointer: 2);
    await one.moveBy(const Offset(-120, 0));
    await one.up();
    await two.up();
    expect(turns, isEmpty);
  });

  testWidgets('a slowly completed drag works if it started before long press',
      (tester) async {
    final turns = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: InstantPageSwipe(
            enabled: true, onTurn: turns.add, child: const SizedBox.expand())));
    final drag = await tester.startGesture(const Offset(200, 200));
    await drag.moveBy(const Offset(-40, 0),
        timeStamp: const Duration(milliseconds: 100));
    await drag.moveBy(const Offset(-80, 0),
        timeStamp: const Duration(milliseconds: 900));
    await drag.up(timeStamp: const Duration(seconds: 1));
    expect(turns, [true]);
  });
}
