import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/api/models.dart';

void main() {
  test('pure dynamic target id is not treated as a book id', () {
    final item = LKDynamicItem.fromJson({
      'dynamic_id': 3627,
      'event_type': 'short_post_published',
      'summary': '纯动态',
      'target_brief': {
        'target_type': 'short_post',
        'target_id': 49,
        'title': '纯动态标题',
        'cover_url': '',
      },
      'media': [
        {'url': 'https://example.com/image.jpg', 'width': 1973, 'height': 1600},
      ],
    });

    expect(item.bookId, 0);
    expect(item.isWorkPost, isFalse);
    expect(item.bookTitle, '纯动态标题');
    expect(item.media, hasLength(1));
    expect(item.media.single.width, 1973);
  });

  test('book target keeps book id and card fields', () {
    final item = LKDynamicItem.fromJson({
      'dynamic_id': 3558,
      'event_type': 'book_created',
      'target_brief': {
        'target_type': 'book',
        'target_id': 31592,
        'title': '书名',
        'cover_url': 'https://example.com/cover.jpg',
      },
    });

    expect(item.bookId, 31592);
    expect(item.isWorkPost, isTrue);
    expect(item.bookTitle, '书名');
    expect(item.bookCover, 'https://example.com/cover.jpg');
  });
}
