import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yomiru/api/models.dart';
import 'package:yomiru/api/store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('local shelf can add and remove the first book', () async {
    final book = LKBook(bookId: 123, title: '测试作品');

    await LKStore.setLocalShelf(book, true);
    expect((await LKStore.localShelf()).map((item) => item.bookId), [123]);

    await LKStore.setLocalShelf(book, false);
    expect(await LKStore.localShelf(), isEmpty);
  });
}
