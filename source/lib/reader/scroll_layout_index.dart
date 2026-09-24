import 'package:flutter/foundation.dart';

/// 当前正文排版下，滚动像素与正文块之间的唯一映射表。
///
/// [itemExtents] 必须与实际 Sliver 子项高度完全一致。这样进度跳转、恢复
/// 阅读位置和滚动采样都能使用同一组前缀偏移，不依赖尚未稳定的
/// maxScrollExtent，也不需要猜测未挂载子项的位置。
@immutable
class ReaderScrollLayoutIndex {
  ReaderScrollLayoutIndex({
    required List<double> itemExtents,
    required this.leadingPadding,
  })  : itemExtents = List<double>.unmodifiable(
          itemExtents.map((value) => value.clamp(1.0, 100000.0).toDouble()),
        ),
        _prefixOffsets = _buildPrefix(itemExtents);

  final List<double> itemExtents;
  final double leadingPadding;
  final List<double> _prefixOffsets;

  static List<double> _buildPrefix(List<double> extents) {
    final result = <double>[0];
    for (final rawExtent in extents) {
      final extent = rawExtent.clamp(1.0, 100000.0).toDouble();
      result.add(result.last + extent);
    }
    return List<double>.unmodifiable(result);
  }

  int get length => itemExtents.length;
  bool get isEmpty => itemExtents.isEmpty;
  double get contentExtent => _prefixOffsets.last;
  double get scrollContentEnd => leadingPadding + contentExtent;

  double itemStart(int rawIndex) {
    if (isEmpty) return leadingPadding;
    final index = rawIndex.clamp(0, length - 1);
    return leadingPadding + _prefixOffsets[index];
  }

  double scrollOffsetForItem(int rawIndex, {double localOffset = 0}) {
    if (isEmpty) return leadingPadding;
    final index = rawIndex.clamp(0, length - 1);
    final safeLocal = localOffset.clamp(0.0, itemExtents[index]).toDouble();
    return itemStart(index) + safeLocal;
  }

  ReaderScrollLocation locate(double scrollOffset) {
    if (isEmpty) return const ReaderScrollLocation(index: 0, localOffset: 0);
    final contentOffset =
        (scrollOffset - leadingPadding).clamp(0.0, contentExtent).toDouble();
    if (contentOffset >= contentExtent) {
      return ReaderScrollLocation(
        index: length - 1,
        localOffset: itemExtents.last,
      );
    }

    var low = 0;
    var high = length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_prefixOffsets[mid + 1] <= contentOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return ReaderScrollLocation(
      index: low,
      localOffset: contentOffset - _prefixOffsets[low],
    );
  }
}

@immutable
class ReaderScrollLocation {
  const ReaderScrollLocation({
    required this.index,
    required this.localOffset,
  });

  final int index;
  final double localOffset;
}
