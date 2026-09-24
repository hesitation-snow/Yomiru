import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/reader/scroll_layout_index.dart';

void main() {
  test('maps item-local offsets to one stable scroll coordinate', () {
    final index = ReaderScrollLayoutIndex(
      itemExtents: const [100, 250, 50],
      leadingPadding: 56,
    );

    expect(index.scrollOffsetForItem(0), 56);
    expect(index.scrollOffsetForItem(1, localOffset: 75), 231);
    expect(index.scrollOffsetForItem(2, localOffset: 50), 456);
  });

  test('finds the visible item with a binary prefix lookup', () {
    final index = ReaderScrollLayoutIndex(
      itemExtents: const [100, 250, 50],
      leadingPadding: 56,
    );

    expect(index.locate(55).index, 0);
    expect(index.locate(56).localOffset, 0);
    expect(index.locate(231).index, 1);
    expect(index.locate(231).localOffset, 75);
    expect(index.locate(999).index, 2);
    expect(index.locate(999).localOffset, 50);
  });

  test('normalizes invalid extents before building prefix offsets', () {
    final index = ReaderScrollLayoutIndex(
      itemExtents: const [0, -10, 20],
      leadingPadding: 0,
    );

    expect(index.itemExtents, const [1, 1, 20]);
    expect(index.contentExtent, 22);
  });
}
