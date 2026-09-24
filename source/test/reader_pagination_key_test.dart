import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/reader/pagination_key.dart';

void main() {
  test('pagination completion does not invalidate the same content and layout',
      () {
    final content = ['paragraph', 'illustration'];
    ReaderPaginationKey? builtKey;
    var paginationCount = 0;
    for (var frame = 0; frame < 5; frame++) {
      final key = ReaderPaginationKey(content: content, layout: '390|844|18');
      if (key != builtKey) {
        builtKey = key;
        paginationCount++;
      }
    }
    expect(paginationCount, 1);
  });

  test('new content triggers pagination even when its length is unchanged', () {
    final first = ReaderPaginationKey(
        content: List<String>.of(['a']), layout: 'portrait');
    final second = ReaderPaginationKey(
        content: List<String>.of(['a']), layout: 'portrait');
    expect(first, isNot(second));
  });

  test('viewport, typography and inset changes invalidate pagination', () {
    final content = ['paragraph'];
    final first =
        ReaderPaginationKey(content: content, layout: (390, 844, 18, 34));
    for (final layout in [
      (844, 390, 18, 34),
      (390, 844, 20, 34),
      (390, 844, 18, 0)
    ]) {
      expect(
          ReaderPaginationKey(content: content, layout: layout), isNot(first));
    }
  });
}
