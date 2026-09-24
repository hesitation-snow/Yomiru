import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/reader/reading_position.dart';

void main() {
  group('ReadingPosition', () {
    test('round-trips an exact text offset', () {
      const original = ReadingPosition.text(blockIndex: 12, offset: 345);

      final restored = ReadingPosition.fromJson(original.toJson());

      expect(restored, original);
      expect(restored!.textOffset, 345);
      expect(restored.blockFraction, 0);
    });

    test('clamps malformed persisted values', () {
      final restored = ReadingPosition.fromJson({
        'block_index': 3,
        'text_offset': -9,
        'block_fraction': 4.2,
      });

      expect(restored, const ReadingPosition(3, 1));
      expect(restored!.textOffset, isNull);
    });

    test('an image page uses one stable atomic-page anchor', () {
      const position = ReadingPosition.imagePage(blockIndex: 8);

      expect(position.blockIndex, 8);
      expect(position.textOffset, isNull);
      expect(position.blockFraction, 0.5);
      expect(ReadingPosition.fromJson(position.toJson()), position);
    });

    test('rejects malformed persisted positions', () {
      expect(ReadingPosition.fromJson(null), isNull);
      expect(ReadingPosition.fromJson({'block_index': -1}), isNull);
      expect(ReadingPosition.fromJson({'block_fraction': 0.5}), isNull);
    });
  });

  group('ReadingPositionController', () {
    test('rejects stale writes during a mode transition', () {
      final controller = ReadingPositionController();
      const oldPosition = ReadingPosition.text(blockIndex: 1, offset: 20);
      const newPosition = ReadingPosition.text(blockIndex: 7, offset: 80);
      controller.update(oldPosition);

      final transitionId = controller.beginTransition();

      expect(controller.update(oldPosition), isFalse);
      expect(
        controller.update(newPosition, transitionId: transitionId),
        isTrue,
      );
      expect(controller.completeTransition(transitionId, newPosition), isTrue);
      expect(controller.value, newPosition);
      expect(controller.transitioning, isFalse);

      controller.dispose();
    });

    test('a superseded transition cannot complete', () {
      final controller = ReadingPositionController();
      final first = controller.beginTransition();
      final second = controller.beginTransition();
      const position = ReadingPosition.image(blockIndex: 2, fraction: 0.4);

      expect(controller.completeTransition(first, position), isFalse);
      expect(controller.transitioning, isTrue);
      expect(controller.completeTransition(second, position), isTrue);
      expect(controller.value, position);

      controller.dispose();
    });
  });
}
