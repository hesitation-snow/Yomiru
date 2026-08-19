import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/api/lk_client.dart';
import 'package:yomiru/api/models.dart';

void main() {
  test('chapter access type identifies brave-only chapters', () {
    final brave = LKChapter.fromJson({
      'chapter_id': 262364,
      'title': '勇者权限章节',
      'access_type': 'brave',
    });
    final publicChapter = LKChapter.fromJson({
      'chapter_id': 1,
      'title': '公开章节',
      'access_type': 'public',
    });

    expect(brave.braveOnly, isTrue);
    expect(publicChapter.braveOnly, isFalse);

    final webStyle = LKChapter.fromJson({'accessType': 'brave'});
    expect(webStyle.braveOnly, isTrue);
  });

  test('access-restricted errors are distinguishable from parse errors', () {
    final restricted = LKException(403, '需要登录或相应权限', accessRestricted: true);
    final parseError = LKException(-1, '响应格式错误');

    expect(restricted.accessRestricted, isTrue);
    expect(parseError.accessRestricted, isFalse);
  });
}
