import 'package:flutter/foundation.dart';

/// 排版无关的正文位置。
///
/// 文本块使用 UTF-16 字符偏移（与 Flutter 的 TextPosition 保持一致），
/// 插画块使用 0~1 的块内比例。滚动和翻页模式都只能通过这个模型交换
/// 阅读位置，不能直接交换像素或页码。
@immutable
class ReadingPosition {
  const ReadingPosition(this.blockIndex, this.blockFraction, {this.textOffset});

  final int blockIndex;
  final int? textOffset;
  final double blockFraction;

  const ReadingPosition.text({
    required int blockIndex,
    required int offset,
  }) : this(blockIndex, 0, textOffset: offset);

  const ReadingPosition.image({
    required int blockIndex,
    double fraction = 0,
  }) : this(blockIndex, fraction);

  /// 翻页模式中的插画固定独占一整页。该页没有可继续细分的滚动位置，
  /// 因此用块中点代表“正在阅读这张插画”，避免翻入插画页时进度被压回
  /// 图片块起点。
  const ReadingPosition.imagePage({
    required int blockIndex,
  }) : this(blockIndex, 0.5);

  ReadingPosition copyWith({
    int? blockIndex,
    int? textOffset,
    double? blockFraction,
    bool clearTextOffset = false,
  }) {
    return ReadingPosition(
      blockIndex ?? this.blockIndex,
      blockFraction ?? this.blockFraction,
      textOffset: clearTextOffset ? null : (textOffset ?? this.textOffset),
    );
  }

  Map<String, Object?> toJson() => {
        'block_index': blockIndex,
        if (textOffset != null) 'text_offset': textOffset,
        'block_fraction': blockFraction,
      };

  static ReadingPosition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final blockIndex = (raw['block_index'] as num?)?.toInt();
    if (blockIndex == null || blockIndex < 0) return null;
    final offset = (raw['text_offset'] as num?)?.toInt();
    final fraction = (raw['block_fraction'] as num?)?.toDouble() ?? 0;
    return ReadingPosition(
      blockIndex,
      fraction.clamp(0.0, 1.0).toDouble(),
      textOffset: offset == null || offset < 0 ? null : offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.blockIndex == blockIndex &&
      other.textOffset == textOffset &&
      other.blockFraction == blockFraction;

  @override
  int get hashCode => Object.hash(blockIndex, textOffset, blockFraction);
}

/// 阅读位置的唯一写入口，并为排版切换提供过渡令牌。
///
/// 进入过渡后，旧模式的异步回调没有令牌就不能覆盖新位置；目标模式
/// 完成布局后必须使用同一个令牌提交最终位置。
class ReadingPositionController extends ValueNotifier<ReadingPosition?> {
  ReadingPositionController() : super(null);

  int _transitionId = 0;
  bool _transitioning = false;

  bool get transitioning => _transitioning;
  int get transitionId => _transitionId;

  int beginTransition() {
    _transitionId++;
    _transitioning = true;
    return _transitionId;
  }

  bool update(ReadingPosition position, {int? transitionId}) {
    if (_transitioning && transitionId != _transitionId) return false;
    value = position;
    return true;
  }

  bool completeTransition(int transitionId, ReadingPosition position) {
    if (transitionId != _transitionId) return false;
    value = position;
    _transitioning = false;
    return true;
  }

  void cancelTransition(int transitionId) {
    if (transitionId == _transitionId) _transitioning = false;
  }
}
