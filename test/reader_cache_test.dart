import 'package:flutter_test/flutter_test.dart';

import 'package:yomiru/api/models.dart';

void main() {
  test('chapter detail cache serialization preserves readable content', () {
    const html = '<p>第一段</p><p>第二段</p>';
    final source = LKChapterDetail(
      chapterId: 12,
      volumeId: 3,
      title: '测试章节',
      bookTitle: '测试作品',
      bodyText: '第一段\n第二段',
      bodyHtml: html,
      nextChapterId: 13,
      nextTitle: '下一章',
      nextVolumeId: 3,
    );

    final restored = LKChapterDetail.fromCacheJson(source.toCacheJson());

    expect(restored.chapterId, source.chapterId);
    expect(restored.volumeId, source.volumeId);
    expect(restored.title, source.title);
    expect(restored.bodyText, source.bodyText);
    expect(restored.bodyHtml, html);
    expect(restored.nextChapterId, 13);
    expect(restored.hasSameContent(source), isTrue);
  });

  test('unlocked state is retained for paid chapter cache entries', () {
    final source = LKChapterDetail(
      chapterId: 21,
      bodyText: '已解锁正文',
      locked: true,
      unlocked: true,
      coinPrice: 5,
    );

    final restored = LKChapterDetail.fromCacheJson(source.toCacheJson());

    expect(restored.locked, isTrue);
    expect(restored.unlocked, isTrue);
    expect(restored.coinPrice, 5);
  });
}
