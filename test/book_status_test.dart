import 'package:flutter_test/flutter_test.dart';

import 'package:yomiru/api/models.dart';

void main() {
  test('serializing is displayed as 连载', () {
    expect(bookStatusLabel(LKBook(serialStatus: 'serializing')), '连载');
  });

  test('completed status is displayed as 完结', () {
    expect(bookStatusLabel(LKBook(serialStatus: 'completed')), '完结');
  });
}
