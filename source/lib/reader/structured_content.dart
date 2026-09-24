import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle, TextBox;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_open_chinese_convert/flutter_open_chinese_convert.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const double _rubyAnnotationFontSizeScale = 0.58;
const double _rubyMinimumLineHeight = 2.30;
const double _rubyAnnotationGapScale = 0.08;
const double _footnoteAnnotationScale = 0.8;
final RegExp _footnoteMarkerPattern = RegExp(r'\[\s*([^\]]+?)\s*\]');
final RegExp _bareFootnoteReferencePattern = RegExp(r'^[A-Za-z0-9_.:-]+$');
final RegExp _cssFontSizePattern =
    RegExp(r'^([+-]?(?:\d+\.?\d*|\.\d+))\s*(px|pt|em|rem|%)?$');

/// Resolve inherited typography before both measurement and rendering. In
/// particular, iOS accessibility bold must also reach the annotation painters.
TextStyle resolveStructuredTextStyle(
  BuildContext context,
  TextStyle style, {
  TextStyle? inheritedStyle,
}) {
  final inherited = inheritedStyle ?? DefaultTextStyle.of(context).style;
  return inherited.merge(style).copyWith(
        inherit: false,
        fontWeight: MediaQuery.boldTextOf(context)
            ? FontWeight.bold
            : (style.fontWeight ?? inherited.fontWeight ?? FontWeight.normal),
      );
}

String? _footnoteReference(String text, {bool allowBare = false}) {
  final bracketed = _footnoteMarkerPattern.firstMatch(text)?.group(1)?.trim();
  if (bracketed != null && bracketed.isNotEmpty) return bracketed;
  final bare = text.trim();
  return allowBare && _bareFootnoteReferencePattern.hasMatch(bare)
      ? bare
      : null;
}

/// 结构化正文块类型
enum StructuredBlockType {
  paragraph,
  heading,
  blockquote,
  listItem,
  divider,
  image,
}

enum StructuredVerticalAlignment { superscript, subscript }

/// 结构化行内样式片段
@immutable
class StructuredInlineRun {
  const StructuredInlineRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.color,
    this.fontSizeMultiplier,
    this.fontWeight,
    this.verticalAlignment,
    this.linkUrl,
    this.rubyText,
    this.rubyBaseText,
    this.isFootnote = false,
  });

  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrikethrough;
  final Color? color;
  final double? fontSizeMultiplier;
  final FontWeight? fontWeight;
  final StructuredVerticalAlignment? verticalAlignment;
  final String? linkUrl;
  final String? rubyText;
  final String? rubyBaseText;
  final bool isFootnote;

  StructuredInlineRun copyWith({
    String? text,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrikethrough,
    Color? color,
    double? fontSizeMultiplier,
    FontWeight? fontWeight,
    StructuredVerticalAlignment? verticalAlignment,
    String? linkUrl,
    String? rubyText,
    String? rubyBaseText,
    bool? isFootnote,
  }) {
    return StructuredInlineRun(
      text: text ?? this.text,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrikethrough: isStrikethrough ?? this.isStrikethrough,
      color: color ?? this.color,
      fontSizeMultiplier: fontSizeMultiplier ?? this.fontSizeMultiplier,
      fontWeight: fontWeight ?? this.fontWeight,
      verticalAlignment: verticalAlignment ?? this.verticalAlignment,
      linkUrl: linkUrl ?? this.linkUrl,
      rubyText: rubyText ?? this.rubyText,
      rubyBaseText: rubyBaseText ?? this.rubyBaseText,
      isFootnote: isFootnote ?? this.isFootnote,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StructuredInlineRun &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isBold == other.isBold &&
          isItalic == other.isItalic &&
          isUnderline == other.isUnderline &&
          isStrikethrough == other.isStrikethrough &&
          color == other.color &&
          fontSizeMultiplier == other.fontSizeMultiplier &&
          linkUrl == other.linkUrl &&
          fontWeight == other.fontWeight &&
          verticalAlignment == other.verticalAlignment &&
          rubyText == other.rubyText &&
          rubyBaseText == other.rubyBaseText &&
          isFootnote == other.isFootnote;

  @override
  int get hashCode => Object.hash(
        text,
        isBold,
        isItalic,
        isUnderline,
        isStrikethrough,
        color,
        fontSizeMultiplier,
        linkUrl,
        fontWeight,
        verticalAlignment,
        rubyText,
        rubyBaseText,
        isFootnote,
      );
}

/// 结构化正文块
@immutable
class StructuredBlock {
  const StructuredBlock({
    required this.type,
    required this.text,
    this.runs = const [],
    this.imageUrl,
    this.imageAspect,
    this.headingLevel = 0,
    this.align,
    this.indent = 0.0,
    this.anchorId,
    this.listNumber,
  });

  const StructuredBlock.divider()
      : type = StructuredBlockType.divider,
        text = '',
        runs = const [],
        imageUrl = null,
        imageAspect = null,
        headingLevel = 0,
        align = null,
        indent = 0.0,
        anchorId = null,
        listNumber = null;

  const StructuredBlock.image(
    this.imageUrl, {
    this.imageAspect,
    this.anchorId,
  })  : type = StructuredBlockType.image,
        text = '',
        runs = const [],
        headingLevel = 0,
        align = null,
        indent = 0.0,
        listNumber = null;

  final StructuredBlockType type;
  final String text;
  final List<StructuredInlineRun> runs;
  final String? imageUrl;
  final double? imageAspect;
  final int headingLevel;
  final TextAlign? align;
  final double indent;
  final String? anchorId;
  final int? listNumber;

  bool get isImage => type == StructuredBlockType.image;
  bool get isDivider => type == StructuredBlockType.divider;
  bool get isHeading => type == StructuredBlockType.heading;
  bool get isBlockquote => type == StructuredBlockType.blockquote;
  bool get isListItem => type == StructuredBlockType.listItem;

  /// 注音的正文字符范围。区间沿用 [text] 的 UTF-16 偏移，和分页、选区一致。
  List<StructuredRubyAnnotation> rubyAnnotations({
    required TextStyle baseStyle,
    required Color linkColor,
    required Color backgroundColor,
  }) {
    if (runs.isEmpty) return const [];
    final result = <StructuredRubyAnnotation>[];
    var offset = 0;
    for (final run in runs) {
      final ruby = run.rubyText;
      if (ruby != null && ruby.isNotEmpty) {
        final suffix = '($ruby)';
        if (run.text.endsWith(suffix)) {
          final baseText =
              run.text.substring(0, run.text.length - suffix.length);
          final isCompleteRuby = baseText.isNotEmpty &&
              (run.rubyBaseText == null || run.rubyBaseText == baseText);
          if (isCompleteRuby) {
            final style = _styleForRun(
              run,
              baseStyle: baseStyle,
              linkColor: linkColor,
              backgroundColor: backgroundColor,
            );
            final fontSize = style.fontSize ?? baseStyle.fontSize ?? 16.0;
            final annotationColor = style.color ?? baseStyle.color ?? Colors.black;
            result.add(StructuredRubyAnnotation(
              start: offset,
              end: offset + baseText.length,
              text: ruby,
              fontSize: fontSize,
              style: style.copyWith(
                fontSize: fontSize * _rubyAnnotationFontSizeScale,
                height: 1,
                letterSpacing: 0,
                wordSpacing: 0,
                color: annotationColor.withValues(
                  alpha: annotationColor.a * 0.92,
                ),
                decoration: TextDecoration.none,
              ),
            ));
          }
        }
      }
      offset += run.text.length;
    }
    return List.unmodifiable(result);
  }

  /// 上标、下标复用正文字符区间，分页、选择和复制仍使用原始文本偏移。
  List<StructuredVerticalAnnotation> verticalAnnotations({
    required TextStyle baseStyle,
    required Color linkColor,
    required Color backgroundColor,
  }) {
    if (runs.isEmpty) return const [];
    final result = <StructuredVerticalAnnotation>[];
    var offset = 0;
    for (final run in runs) {
      final alignment = run.verticalAlignment;
      if (alignment != null && run.text.isNotEmpty) {
        final footnoteReference = run.isFootnote
            ? _footnoteReference(run.text, allowBare: true)
            : null;
        final isClickableFootnote = footnoteReference != null;
        final style = _styleForRun(
          run,
          baseStyle: baseStyle,
          linkColor: linkColor,
          backgroundColor: backgroundColor,
        );
        result.add(StructuredVerticalAnnotation(
          start: offset,
          end: offset + run.text.length,
          text: run.text,
          alignment: alignment,
          footnoteReference: footnoteReference,
          style: style.copyWith(
            fontSize: isClickableFootnote
                ? (style.fontSize ?? baseStyle.fontSize ?? 16.0) *
                    _footnoteAnnotationScale
                : style.fontSize,
            color: isClickableFootnote ? linkColor : style.color,
            decoration: TextDecoration.none,
            height: 1.0,
            letterSpacing: 0,
            wordSpacing: 0,
          ),
        ));
      }
      offset += run.text.length;
    }
    return List.unmodifiable(result);
  }

  TextStyle _styleForRun(
    StructuredInlineRun run, {
    required TextStyle baseStyle,
    required Color linkColor,
    required Color backgroundColor,
  }) {
    TextStyle style = baseStyle;
    if (headingLevel > 0) {
      final mult = headingScale(headingLevel);
      style = style.copyWith(
        fontSize: (baseStyle.fontSize ?? 16.0) * mult,
        fontWeight: FontWeight.bold,
        height: 1.35,
      );
    } else if (isBlockquote) {
      style = style.copyWith(color: baseStyle.color?.withValues(alpha: 0.88));
    }
    if (run.isBold) style = style.copyWith(fontWeight: FontWeight.bold);
    if (run.fontWeight != null) {
      style = style.copyWith(fontWeight: run.fontWeight);
    }
    if (run.isItalic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (run.linkUrl != null) {
      style = style.copyWith(color: linkColor);
    } else if (run.color != null) {
      style = style.copyWith(
        color: ensureLegibleColor(run.color!, backgroundColor),
      );
    }
    if (run.fontSizeMultiplier != null) {
      style = style.copyWith(
        fontSize: (style.fontSize ?? baseStyle.fontSize ?? 16.0) *
            run.fontSizeMultiplier!,
      );
    }
    return style;
  }

  /// 从当前正文块的字符区间 [start, end) 裁剪生成新的结构化块。
  ///
  /// 保持所有内部 runs 的行内样式与相对字符边界，保证翻页模式跨页切分
  /// 不会发生样式截断或外溢。
  StructuredBlock slice(int start, int end) {
    if (isImage || isDivider) return this;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    if (safeStart >= safeEnd) {
      return StructuredBlock(
        type: type,
        text: '',
        runs: const [],
        headingLevel: headingLevel,
        align: align,
        indent: indent,
      );
    }

    final slicedRuns = <StructuredInlineRun>[];
    var currentOffset = 0;
    for (final run in runs) {
      final runStart = currentOffset;
      final runEnd = currentOffset + run.text.length;
      currentOffset = runEnd;

      if (runEnd <= safeStart || runStart >= safeEnd) {
        continue;
      }

      final sliceStart = (safeStart - runStart).clamp(0, run.text.length);
      final sliceEnd = (safeEnd - runStart).clamp(sliceStart, run.text.length);
      if (sliceEnd > sliceStart) {
        final subText = run.text.substring(sliceStart, sliceEnd);
        slicedRuns.add(run.copyWith(text: subText));
      }
    }

    final slicedText = text.substring(safeStart, safeEnd);
    return StructuredBlock(
      type: type,
      text: slicedText,
      runs: List.unmodifiable(slicedRuns),
      headingLevel: headingLevel,
      align: align,
      indent: indent,
      anchorId: safeStart == 0 ? anchorId : null,
      listNumber: safeStart == 0 ? listNumber : null,
    );
  }

  /// 计算在当前阅读背景色下的可读颜色，防止黑底黑字或白底白字。
  static Color ensureLegibleColor(Color color, Color backgroundColor) {
    final bgLuminance = backgroundColor.computeLuminance();
    final colorLuminance = color.computeLuminance();
    final l1 = math.max(bgLuminance, colorLuminance);
    final l2 = math.min(bgLuminance, colorLuminance);
    final contrast = (l1 + 0.05) / (l2 + 0.05);
    if (contrast >= 2.5) {
      return color;
    }

    final hsv = HSVColor.fromColor(color);
    if (bgLuminance < 0.5) {
      // 暗色背景：提升亮度，略降饱和度
      return hsv
          .withValue(math.max(hsv.value, 0.88))
          .withSaturation(math.min(hsv.saturation, 0.65))
          .toColor();
    } else {
      // 浅色背景：压低亮度加深颜色
      return hsv.withValue(math.min(hsv.value, 0.28)).toColor();
    }
  }

  /// 标题字号倍率
  static double headingScale(int level) {
    switch (level) {
      case 1:
        return 1.40;
      case 2:
        return 1.28;
      case 3:
        return 1.18;
      case 4:
        return 1.12;
      case 5:
        return 1.08;
      case 6:
        return 1.05;
      default:
        return 1.0;
    }
  }

  /// 根据阅读器当前排版上下文构建 TextSpan。
  ///
  /// [forMeasurement] 为 true 时，不创建 TapGestureRecognizer，
  /// 避免 TextPainter 测量阶段产生未释放手势对象。
  TextSpan buildTextSpan({
    required TextStyle baseStyle,
    required Color linkColor,
    required Color backgroundColor,
    void Function(String url)? onLinkTap,
    void Function(String reference)? onFootnoteTap,
    bool forMeasurement = false,
  }) {
    TextStyle blockStyle = baseStyle;
    if (headingLevel > 0) {
      final mult = headingScale(headingLevel);
      blockStyle = blockStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16.0) * mult,
        fontWeight: FontWeight.bold,
        height: 1.35,
      );
    } else if (isBlockquote) {
      blockStyle = blockStyle.copyWith(
        color: baseStyle.color?.withValues(alpha: 0.88),
      );
    }

    if (runs.isEmpty) {
      return TextSpan(text: text, style: blockStyle);
    }

    final spans = <InlineSpan>[];
    for (final run in runs) {
      TextStyle runStyle = blockStyle;

      if (run.isBold) {
        runStyle = runStyle.copyWith(fontWeight: FontWeight.bold);
      }
      if (run.fontWeight != null) {
        runStyle = runStyle.copyWith(fontWeight: run.fontWeight);
      }
      if (run.isItalic) {
        runStyle = runStyle.copyWith(fontStyle: FontStyle.italic);
      }

      if (run.linkUrl != null) {
        runStyle = runStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        );
      } else if (run.color != null) {
        runStyle = runStyle.copyWith(
          color: ensureLegibleColor(run.color!, backgroundColor),
        );
      }

      final hasUnderline = run.isUnderline || run.linkUrl != null;
      final hasStrikethrough = run.isStrikethrough;
      final effectiveDecColor =
          runStyle.color ?? blockStyle.color ?? baseStyle.color;

      if (hasUnderline && hasStrikethrough) {
        runStyle = runStyle.copyWith(
          decoration: TextDecoration.combine([
            TextDecoration.underline,
            TextDecoration.lineThrough,
          ]),
          decorationColor: effectiveDecColor,
          decorationThickness: 1.5,
        );
      } else if (hasUnderline) {
        runStyle = runStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: effectiveDecColor,
        );
      } else if (hasStrikethrough) {
        runStyle = runStyle.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: effectiveDecColor,
          decorationThickness: 1.5,
        );
      }

      if (run.fontSizeMultiplier != null) {
        final currentFontSize = runStyle.fontSize ?? baseStyle.fontSize ?? 16.0;
        runStyle = runStyle.copyWith(
          fontSize: currentFontSize * run.fontSizeMultiplier!,
        );
      }

      final footnoteReference = run.isFootnote && onFootnoteTap != null
          ? _footnoteReference(run.text, allowBare: true)
          : null;
      if (footnoteReference != null && footnoteReference.isNotEmpty) {
        runStyle = runStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.72),
          decorationThickness: 0.8,
        );
      }

      GestureRecognizer? recognizer;
      if (!forMeasurement && footnoteReference != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => onFootnoteTap!(footnoteReference);
      } else if (!forMeasurement && run.linkUrl != null && onLinkTap != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => onLinkTap(run.linkUrl!);
      }

      // 注音保留在 TextSpan 的文本中，维持 UTF-16 偏移与选中复制内容；
      // 实际字形由 StructuredRubyText 绘制到正文上方，不挤占正文行宽。
      // Ruby 行单独保留顶部空间，避免用户缩小行距后注音挤到上一行。
      if (run.rubyText != null && run.rubyText!.isNotEmpty) {
        final rt = run.rubyText!;
        final parenNote = '($rt)';
        if (run.text.endsWith(parenNote)) {
          final baseTextPart =
              run.text.substring(0, run.text.length - parenNote.length);
          final isCompleteRuby = baseTextPart.isNotEmpty &&
              (run.rubyBaseText == null || run.rubyBaseText == baseTextPart);
          if (isCompleteRuby) {
            spans.add(TextSpan(
              text: baseTextPart,
              style: runStyle.copyWith(
                height: math.max(
                  runStyle.height ?? 1.0,
                  _rubyMinimumLineHeight,
                ),
              ),
              recognizer: recognizer,
            ));
            final hiddenNoteStyle = runStyle.copyWith(
              fontSize: 0.01,
              height: 1.0,
              letterSpacing: 0,
              wordSpacing: 0,
              color: Colors.transparent,
              decoration: TextDecoration.none,
            );
            spans.add(TextSpan(
              text: parenNote,
              style: hiddenNoteStyle,
              recognizer: recognizer,
            ));
            continue;
          }
        }
      }

      final renderedStyle = run.verticalAlignment == null
          ? runStyle
          : runStyle.copyWith(
              color: Colors.transparent,
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
              // 占位与可见脚注使用完全相同的字形尺寸，保留原始字符索引。
              fontSize: run.isFootnote &&
                      run.verticalAlignment ==
                          StructuredVerticalAlignment.superscript
                  ? math.max(
                      1.0,
                      (runStyle.fontSize ?? blockStyle.fontSize ?? 16.0) *
                          _footnoteAnnotationScale,
                    )
                  : runStyle.fontSize,
              height: 1.0,
              letterSpacing: 0,
              wordSpacing: 0,
            );
      spans.add(TextSpan(
        text: run.text,
        style: renderedStyle,
        recognizer: recognizer,
      ));
    }

    return TextSpan(style: blockStyle, children: spans);
  }

  /// 提取用于旧版兼容或测试的超链接列表 (start, end, url)
  List<(int, int, String)> extractLinks() {
    final links = <(int, int, String)>[];
    var pos = 0;
    for (final run in runs) {
      final len = run.text.length;
      if (run.linkUrl != null && run.linkUrl!.isNotEmpty) {
        links.add((pos, pos + len, run.linkUrl!));
      }
      pos += len;
    }
    return links;
  }
}

@immutable
class StructuredRubyAnnotation {
  const StructuredRubyAnnotation({
    required this.start,
    required this.end,
    required this.text,
    required this.fontSize,
    required this.style,
  });

  final int start;
  final int end;
  final String text;
  final double fontSize;
  final TextStyle style;
}

@immutable
class StructuredVerticalAnnotation {
  const StructuredVerticalAnnotation({
    required this.start,
    required this.end,
    required this.text,
    required this.alignment,
    required this.style,
    this.footnoteReference,
  });

  final int start;
  final int end;
  final String text;
  final StructuredVerticalAlignment alignment;
  final TextStyle style;
  final String? footnoteReference;
}

// A very narrow line can force a marker to wrap even inside its brackets.
// Paint each laid-out fragment on its own line, retaining the same reference.
Iterable<StructuredVerticalAnnotation> _verticalAnnotationFragments(
  TextPainter paragraph,
  StructuredVerticalAnnotation annotation,
) sync* {
  if (annotation.start < 0 ||
      annotation.end > paragraph.plainText.length ||
      annotation.end <= annotation.start) {
    return;
  }
  var start = annotation.start;
  while (start < annotation.end) {
    final line = paragraph.getLineBoundary(TextPosition(offset: start));
    final end = math.min(annotation.end, math.max(start + 1, line.end));
    yield StructuredVerticalAnnotation(
      start: start,
      end: end,
      text: annotation.text.substring(
        start - annotation.start,
        end - annotation.start,
      ),
      alignment: annotation.alignment,
      style: annotation.style,
      footnoteReference: annotation.footnoteReference,
    );
    start = end;
  }
}

/// 绘制与点击热区共用同一坐标，避免小占位文本与可见脚注脱节。
Offset? _verticalAnnotationPosition({
  required TextPainter paragraph,
  required TextPainter notePainter,
  required StructuredVerticalAnnotation annotation,
  required Size size,
}) {
  if (annotation.start < 0 ||
      annotation.end <= annotation.start ||
      annotation.end > paragraph.plainText.length) {
    return null;
  }
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: annotation.start,
      extentOffset: annotation.end,
    ),
    boxHeightStyle: ui.BoxHeightStyle.tight,
    boxWidthStyle: ui.BoxWidthStyle.tight,
  );
  if (boxes.isEmpty) return null;
  final markerBox = boxes.first;

  ui.TextBox? precedingBox;
  if (annotation.alignment == StructuredVerticalAlignment.superscript &&
      annotation.start > 0 &&
      paragraph
              .getLineBoundary(TextPosition(offset: annotation.start))
              .start <
          annotation.start) {
    final preceding = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: annotation.start - 1,
        extentOffset: annotation.start,
      ),
      boxHeightStyle: ui.BoxHeightStyle.tight,
      boxWidthStyle: ui.BoxWidthStyle.tight,
    );
    if (preceding.isNotEmpty) precedingBox = preceding.last;
  }

  final isFootnote = annotation.footnoteReference != null;
  final left = markerBox.left;
  // Use the marker's own line, including when it wraps after the preceding
  // character. unscaledAscent excludes the user's extra line-height leading.
  final lines = isFootnote ? paragraph.computeLineMetrics() : null;
  final line = lines?.firstWhere(
    (line) =>
        (markerBox.top + markerBox.bottom) / 2 >= line.baseline - line.ascent &&
        (markerBox.top + markerBox.bottom) / 2 <= line.baseline + line.descent,
    orElse: () => lines.last,
  );
  final top = switch (annotation.alignment) {
    StructuredVerticalAlignment.superscript when isFootnote => line!.baseline -
        line.unscaledAscent * 0.5 -
        notePainter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    StructuredVerticalAlignment.superscript =>
      precedingBox?.top ?? markerBox.top,
    StructuredVerticalAlignment.subscript =>
      markerBox.bottom - notePainter.height * 0.78,
  };
  return Offset(
    left.clamp(0.0, math.max(0.0, size.width - notePainter.width)).toDouble(),
    top.clamp(0.0, math.max(0.0, size.height - notePainter.height)).toDouble(),
  );
}

/// 在不改变正文字符索引的前提下，把 ruby 注音及上/下标绘制在正文上。
/// RichText 与前景画笔使用同一个已解析字体的 TextSpan，保留选择与复制。
class StructuredRubyText extends StatelessWidget {
  const StructuredRubyText({
    super.key,
    this.textKey,
    required this.block,
    required this.span,
    required this.baseStyle,
    required this.linkColor,
    required this.backgroundColor,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.textAlign,
    this.onFootnoteTap,
  });

  final Key? textKey;
  final StructuredBlock block;
  final TextSpan span;
  final TextStyle baseStyle;
  final Color linkColor;
  final Color backgroundColor;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final TextAlign textAlign;
  final void Function(String reference)? onFootnoteTap;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = resolveStructuredTextStyle(context, baseStyle);
    final effectiveSpan = TextSpan(style: effectiveStyle, children: [span]);
    final annotations = block.rubyAnnotations(
      baseStyle: effectiveStyle,
      linkColor: linkColor,
      backgroundColor: backgroundColor,
    );
    final verticalAnnotations = block.verticalAnnotations(
      baseStyle: effectiveStyle,
      linkColor: linkColor,
      backgroundColor: backgroundColor,
    );
    // Text.rich would independently inherit typography and accessibility
    // overrides. RichText consumes the exact span measured by our painters.
    final text = RichText(
      key: textKey,
      text: effectiveSpan,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textAlign: textAlign,
      textWidthBasis: TextWidthBasis.parent,
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: DefaultSelectionStyle.of(context).selectionColor ??
          DefaultSelectionStyle.defaultColor,
    );
    if (annotations.isEmpty && verticalAnnotations.isEmpty) return text;
    final paintedText = CustomPaint(
      foregroundPainter: _StructuredRubyPainter(
        span: effectiveSpan,
        annotations: annotations,
        verticalAnnotations: verticalAnnotations,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        textAlign: textAlign,
      ),
      child: text,
    );
    if (onFootnoteTap == null ||
        !verticalAnnotations.any((annotation) =>
            annotation.footnoteReference != null)) {
      return paintedText;
    }

    // 缩小脚注的透明占位后，TextSpan 自身的命中区域也会变窄。
    // 在实际绘制位置覆盖独立点击区域，不牺牲正文的原始字符索引与复制内容。
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
        return paintedText;
      }
      final width = constraints.maxWidth;
      final paragraph = TextPainter(
        text: effectiveSpan,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        textAlign: textAlign,
        textWidthBasis: TextWidthBasis.parent,
      )..layout(maxWidth: width);
      final notePainter = TextPainter(
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      );
      final hitAreas = <Widget>[];
      for (final annotation in verticalAnnotations.expand((annotation) =>
          _verticalAnnotationFragments(paragraph, annotation))) {
        final reference = annotation.footnoteReference;
        if (reference == null) continue;
        notePainter.text = TextSpan(
          text: annotation.text,
          style: annotation.style,
        );
        notePainter.layout();
        final position = _verticalAnnotationPosition(
          paragraph: paragraph,
          notePainter: notePainter,
          annotation: annotation,
          size: Size(width, paragraph.height),
        );
        if (position == null) continue;
        final hitWidth = math.min(width, math.max(24.0, notePainter.width + 8));
        final hitHeight = math.min(
          paragraph.height,
          math.max(24.0, notePainter.height + 8),
        );
        hitAreas.add(Positioned(
          left: (position.dx - 4)
              .clamp(0.0, math.max(0.0, width - hitWidth))
              .toDouble(),
          top: (position.dy - 4)
              .clamp(0.0, math.max(0.0, paragraph.height - hitHeight))
              .toDouble(),
          width: hitWidth,
          height: hitHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onFootnoteTap!(reference),
          ),
        ));
      }
      notePainter.dispose();
      paragraph.dispose();
      return Stack(
        children: [SizedBox(width: width, child: paintedText), ...hitAreas],
      );
    });
  }
}

class _StructuredRubyPainter extends CustomPainter {
  const _StructuredRubyPainter({
    required this.span,
    required this.annotations,
    required this.verticalAnnotations,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.textAlign,
  });

  final TextSpan span;
  final List<StructuredRubyAnnotation> annotations;
  final List<StructuredVerticalAnnotation> verticalAnnotations;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final TextAlign textAlign;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 ||
        (annotations.isEmpty && verticalAnnotations.isEmpty)) {
      return;
    }
    final paragraph = TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textAlign: textAlign,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: size.width);
    final notePainter = TextPainter(
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textAlign: TextAlign.center,
    );

    for (final annotation in annotations) {
      if (annotation.start < 0 ||
          annotation.end <= annotation.start ||
          annotation.end > paragraph.plainText.length) {
        continue;
      }
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: annotation.start,
          extentOffset: annotation.end,
        ),
        boxHeightStyle: ui.BoxHeightStyle.tight,
        boxWidthStyle: ui.BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) continue;

      final left = boxes.map((box) => box.left).reduce(math.min);
      final right = boxes.map((box) => box.right).reduce(math.max);
      final firstTop = boxes.first.top;

      notePainter.text = TextSpan(
        text: annotation.text,
        style: annotation.style,
      );
      notePainter.layout();
      final center = (left + right) / 2;
      final dx = (center - notePainter.width / 2)
          .clamp(0.0, math.max(0.0, size.width - notePainter.width))
          .toDouble();
      final rubyGap = textScaler.scale(
        annotation.fontSize * _rubyAnnotationGapScale,
      );
      final dy = firstTop - notePainter.height - rubyGap;
      notePainter.paint(canvas, Offset(dx, dy));
    }
    for (final annotation in verticalAnnotations.expand(
        (annotation) => _verticalAnnotationFragments(paragraph, annotation))) {
      notePainter.text = TextSpan(
        text: annotation.text,
        style: annotation.style,
      );
      notePainter.layout();
      final position = _verticalAnnotationPosition(
        paragraph: paragraph,
        notePainter: notePainter,
        annotation: annotation,
        size: size,
      );
      if (position != null) notePainter.paint(canvas, position);
    }
    notePainter.dispose();
    paragraph.dispose();
  }

  @override
  bool shouldRepaint(covariant _StructuredRubyPainter oldDelegate) =>
      !identical(oldDelegate.span, span) ||
      oldDelegate.annotations != annotations ||
      oldDelegate.verticalAnnotations != verticalAnnotations ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.locale != locale ||
      oldDelegate.textAlign != textAlign;
}

/// 列表环境上下文跟踪
class _ActiveListContext {
  _ActiveListContext({required this.isOrdered});
  final bool isOrdered;
  int counter = 0;
}

/// 列表项前缀注入状态
class _LiState {
  _LiState(this.prefix);
  String? prefix;
}

/// 解析环境样式上下文
class _StyleScope {
  const _StyleScope({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.color,
    this.fontSizeMultiplier,
    this.fontWeight,
    this.verticalAlignment,
    this.linkUrl,
    this.headingLevel = 0,
    this.isBlockquote = false,
    this.isListItem = false,
    this.listNumber,
    this.align,
    this.indent = 0.0,
    this.isFootnote = false,
    this.liState,
  });

  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrikethrough;
  final Color? color;
  final double? fontSizeMultiplier;
  final FontWeight? fontWeight;
  final StructuredVerticalAlignment? verticalAlignment;
  final String? linkUrl;
  final int headingLevel;
  final bool isBlockquote;
  final bool isListItem;
  final int? listNumber;
  final TextAlign? align;
  final double indent;
  final bool isFootnote;
  final _LiState? liState;

  _StyleScope copyWith({
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrikethrough,
    Color? color,
    double? fontSizeMultiplier,
    FontWeight? fontWeight,
    StructuredVerticalAlignment? verticalAlignment,
    String? linkUrl,
    int? headingLevel,
    bool? isBlockquote,
    bool? isListItem,
    int? listNumber,
    TextAlign? align,
    double? indent,
    bool? isFootnote,
    _LiState? liState,
  }) {
    return _StyleScope(
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrikethrough: isStrikethrough ?? this.isStrikethrough,
      color: color ?? this.color,
      fontSizeMultiplier: fontSizeMultiplier ?? this.fontSizeMultiplier,
      fontWeight: fontWeight ?? this.fontWeight,
      verticalAlignment: verticalAlignment ?? this.verticalAlignment,
      linkUrl: linkUrl ?? this.linkUrl,
      headingLevel: headingLevel ?? this.headingLevel,
      isBlockquote: isBlockquote ?? this.isBlockquote,
      isListItem: isListItem ?? this.isListItem,
      listNumber: listNumber ?? this.listNumber,
      align: align ?? this.align,
      indent: indent ?? this.indent,
      isFootnote: isFootnote ?? this.isFootnote,
      liState: liState ?? this.liState,
    );
  }
}

/// 结构化正文解析器
class StructuredContentParser {
  StructuredContentParser._();

  static const int maxTextBlockLength = 8000;

  static final RegExp _resPlaceholderRe = RegExp(r'\[res\][^[]+\[/res\]');
  static final RegExp _imageWidthRe =
      RegExp(r'(?:img-width|width)\s*=\s*["\x27]?(\d+)["\x27]?', caseSensitive: false);
  static final RegExp _imageHeightRe =
      RegExp(r'(?:img-height|height)\s*=\s*["\x27]?(\d+)["\x27]?', caseSensitive: false);

  /// 解析 HTML 章节内容为结构化正文块列表
  static List<StructuredBlock> parseHtml(String html,
      {bool firstLineIndent = false}) {
    if (html.trim().isEmpty) return const [];

    final cleanHtml = html.replaceAll(_resPlaceholderRe, '');
    final fragment = html_parser.parseFragment(cleanHtml);

    final blocks = <StructuredBlock>[];
    final currentRuns = <StructuredInlineRun>[];
    final listStack = <_ActiveListContext>[];
    _StyleScope activeScope = const _StyleScope();

    void flushCurrentBlock() {
      if (currentRuns.isEmpty) return;
      var fullText = currentRuns.map((r) => r.text).join();
      final trimmed = fullText.trim();
      if (trimmed.isEmpty) {
        currentRuns.clear();
        return;
      }

      StructuredBlockType bType = StructuredBlockType.paragraph;
      if (activeScope.headingLevel > 0) {
        bType = StructuredBlockType.heading;
      } else if (activeScope.isBlockquote) {
        bType = StructuredBlockType.blockquote;
      } else if (activeScope.isListItem) {
        bType = StructuredBlockType.listItem;
      }

      if (bType == StructuredBlockType.paragraph) {
        if (firstLineIndent) {
          if (!fullText.startsWith('\u3000') && !fullText.startsWith('  ')) {
            currentRuns[0] = currentRuns[0].copyWith(
              text: '\u3000\u3000${currentRuns[0].text}',
            );
            fullText = '\u3000\u3000$fullText';
          }
        } else {
          // 不缩进：若正文开头有全角空格或普通空格，移除之以顶格显示
          if (fullText.startsWith('\u3000') || fullText.startsWith(' ')) {
            var stripCount = 0;
            while (stripCount < fullText.length &&
                (fullText[stripCount] == '\u3000' || fullText[stripCount] == ' ')) {
              stripCount++;
            }
            if (stripCount > 0) {
              var remainingStrip = stripCount;
              var runIndex = 0;
              while (remainingStrip > 0 && runIndex < currentRuns.length) {
                final run = currentRuns[runIndex];
                if (run.text.length <= remainingStrip) {
                  remainingStrip -= run.text.length;
                  currentRuns.removeAt(runIndex);
                } else {
                  currentRuns[runIndex] = run.copyWith(
                    text: run.text.substring(remainingStrip),
                  );
                  remainingStrip = 0;
                  break;
                }
              }
              fullText = fullText.substring(stripCount);
              if (fullText.trim().isEmpty || currentRuns.isEmpty) {
                currentRuns.clear();
                return;
              }
            }
          }
        }
      }

      final block = StructuredBlock(
        type: bType,
        text: fullText,
        runs: List.unmodifiable(currentRuns),
        headingLevel: activeScope.headingLevel,
        align: activeScope.align,
        indent: activeScope.indent,
        listNumber: activeScope.listNumber,
      );
      _appendSplitBlock(blocks, block);
      currentRuns.clear();
    }

    void walk(dom.Node node, _StyleScope scope) {
      if (node is dom.Text) {
        final raw = node.text;
        if (raw.isNotEmpty) {
          // 压缩并清理实体已在 DOM 解析完成后的纯文本中
          final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
          final parts = normalized.split('\n');
          for (var i = 0; i < parts.length; i++) {
            if (i > 0) {
              flushCurrentBlock();
            }
            final part = parts[i];
            if (part.isNotEmpty) {
              if (scope.liState?.prefix != null) {
                final pfx = scope.liState!.prefix!;
                scope.liState!.prefix = null;
                activeScope = scope;
                currentRuns.add(StructuredInlineRun(
                  text: pfx,
                  isBold: scope.isBold,
                  isItalic: scope.isItalic,
                  color: scope.color,
                ));
              }
              activeScope = scope;
              currentRuns.add(StructuredInlineRun(
                text: part,
                isBold: scope.isBold,
                isItalic: scope.isItalic,
                isUnderline: scope.isUnderline,
                isStrikethrough: scope.isStrikethrough,
                color: scope.color,
                fontSizeMultiplier: scope.fontSizeMultiplier,
                fontWeight: scope.fontWeight,
                verticalAlignment: scope.verticalAlignment,
                linkUrl: scope.linkUrl,
                isFootnote: scope.isFootnote,
              ));
            }
          }
        }
        return;
      }

      if (node is! dom.Element) return;

      final tagName = node.localName?.toLowerCase() ?? '';

      // 忽略有害或隐藏标签
      if (tagName == 'script' ||
          tagName == 'style' ||
          tagName == 'meta' ||
          tagName == 'link' ||
          tagName == 'title') {
        return;
      }

      // 换行
      if (tagName == 'br') {
        flushCurrentBlock();
        return;
      }

      // 水平分割线
      if (tagName == 'hr') {
        flushCurrentBlock();
        blocks.add(const StructuredBlock.divider());
        return;
      }

      // 插画
      if (tagName == 'img') {
        flushCurrentBlock();
        final src = (node.attributes['src'] ?? '').trim();
        final uri = Uri.tryParse(src);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) {
          final wAttr = node.attributes['img-width'] ??
              node.attributes['width'] ??
              _imageWidthRe.firstMatch(node.outerHtml)?.group(1);
          final hAttr = node.attributes['img-height'] ??
              node.attributes['height'] ??
              _imageHeightRe.firstMatch(node.outerHtml)?.group(1);
          final wi = int.tryParse(wAttr ?? '') ?? 0;
          final hi = int.tryParse(hAttr ?? '') ?? 0;
          blocks.add(StructuredBlock.image(
            src,
            imageAspect: (wi > 0 && hi > 0) ? wi / hi : null,
          ));
        }
        return;
      }

      // Ruby 注音处理
      if (tagName == 'ruby') {
        final rt = node.getElementsByTagName('rt');
        String rubyAnnotation = '';
        if (rt.isNotEmpty) {
          rubyAnnotation = rt.map((e) => e.text.trim()).join();
        }
        // 提取 base 汉字文本（排除 rt 和 rp）
        final baseBuf = StringBuffer();
        for (final child in node.nodes) {
          if (child is dom.Element &&
              (child.localName?.toLowerCase() == 'rt' ||
                  child.localName?.toLowerCase() == 'rp')) {
            continue;
          }
          baseBuf.write(child.text);
        }
        final baseText = baseBuf.toString().trim();
        if (baseText.isNotEmpty) {
          final fullText = rubyAnnotation.isNotEmpty
              ? '$baseText($rubyAnnotation)'
              : baseText;
          activeScope = scope;
          currentRuns.add(StructuredInlineRun(
            text: fullText,
            isBold: scope.isBold,
            isItalic: scope.isItalic,
            isUnderline: scope.isUnderline,
            isStrikethrough: scope.isStrikethrough,
            color: scope.color,
            fontSizeMultiplier: scope.fontSizeMultiplier,
            fontWeight: scope.fontWeight,
            verticalAlignment: scope.verticalAlignment,
            linkUrl: scope.linkUrl,
            rubyText: rubyAnnotation.isNotEmpty ? rubyAnnotation : null,
            rubyBaseText: rubyAnnotation.isNotEmpty ? baseText : null,
          ));
        }
        return;
      }

      // 计算当前元素应用的样式
      _StyleScope childScope = scope;

      // 标题
      if (tagName.length == 2 &&
          tagName.startsWith('h') &&
          int.tryParse(tagName.substring(1)) != null) {
        flushCurrentBlock();
        final lvl = int.parse(tagName.substring(1)).clamp(1, 6);
        childScope = childScope.copyWith(
          headingLevel: lvl,
          isBold: true,
          fontWeight: FontWeight.bold,
        );
      }

      // 引用
      if (tagName == 'blockquote') {
        flushCurrentBlock();
        childScope = childScope.copyWith(
          isBlockquote: true,
          indent: childScope.indent + 14.0,
        );
      }

      final isUl = tagName == 'ul';
      final isOl = tagName == 'ol';
      if (isUl) {
        listStack.add(_ActiveListContext(isOrdered: false));
      } else if (isOl) {
        listStack.add(_ActiveListContext(isOrdered: true));
      }

      // 列表项
      if (tagName == 'li') {
        flushCurrentBlock();
        final currentList = listStack.isNotEmpty ? listStack.last : null;
        final int? itemNum = currentList != null && currentList.isOrdered
            ? ++currentList.counter
            : null;
        final String prefix = currentList != null
            ? (currentList.isOrdered ? '$itemNum. ' : '• ')
            : '• ';

        childScope = childScope.copyWith(
          isListItem: true,
          listNumber: itemNum,
          indent: childScope.indent + 14.0,
          liState: _LiState(prefix),
        );
      }

      // 行内样式标签
      if (tagName == 'b' || tagName == 'strong') {
        childScope = childScope.copyWith(
          isBold: true,
          fontWeight: FontWeight.bold,
        );
      }
      if (tagName == 'i' || tagName == 'em') {
        childScope = childScope.copyWith(isItalic: true);
      }
      if (tagName == 'u' || tagName == 'ins') {
        childScope = childScope.copyWith(isUnderline: true);
      }
      if (tagName == 's' || tagName == 'del' || tagName == 'strike') {
        childScope = childScope.copyWith(isStrikethrough: true);
      }
      if (tagName == 'small' || tagName == 'sub') {
        childScope = childScope.copyWith(
          fontSizeMultiplier: (childScope.fontSizeMultiplier ?? 1.0) * 0.82,
        );
      }
      if (tagName == 'sub') {
        childScope = childScope.copyWith(
          verticalAlignment: StructuredVerticalAlignment.subscript,
        );
      }
      if (tagName == 'big') {
        childScope = childScope.copyWith(
          fontSizeMultiplier: (childScope.fontSizeMultiplier ?? 1.0) * 1.15,
        );
      }
      if (tagName == 'sup' || node.classes.contains('ln-footnote-ref')) {
        childScope = childScope.copyWith(
          fontSizeMultiplier: (childScope.fontSizeMultiplier ?? 1.0) * 0.75,
          isFootnote: childScope.isFootnote ||
              node.classes.contains('ln-footnote-ref') ||
              (tagName == 'sup' && _footnoteMarkerPattern.hasMatch(node.text)),
          verticalAlignment: StructuredVerticalAlignment.superscript,
        );
      }

      // 超链接
      if (tagName == 'a') {
        final href = node.attributes['href']?.trim();
        if (href != null && href.isNotEmpty) {
          childScope = childScope.copyWith(linkUrl: href);
        }
      }

      // font 标签属性
      if (tagName == 'font') {
        final colorAttr = node.attributes['color']?.trim();
        if (colorAttr != null && colorAttr.isNotEmpty) {
          final c = _parseCssColor(colorAttr);
          if (c != null) childScope = childScope.copyWith(color: c);
        }
      }

      // align 属性
      final alignAttr = node.attributes['align']?.toLowerCase().trim();
      if (alignAttr != null) {
        if (alignAttr == 'center') {
          childScope = childScope.copyWith(align: TextAlign.center);
        } else if (alignAttr == 'right') {
          childScope = childScope.copyWith(align: TextAlign.right);
        } else if (alignAttr == 'justify') {
          childScope = childScope.copyWith(align: TextAlign.justify);
        }
      }

      // style 内联 CSS 属性解析
      final styleAttr = node.attributes['style'];
      if (styleAttr != null && styleAttr.isNotEmpty) {
        childScope = _applyInlineStyle(styleAttr, childScope);
      }
      if (childScope.verticalAlignment ==
              StructuredVerticalAlignment.superscript &&
          _footnoteMarkerPattern.hasMatch(node.text)) {
        childScope = childScope.copyWith(isFootnote: true);
      }

      final isBlockElement = tagName == 'p' ||
          tagName == 'div' ||
          tagName == 'section' ||
          tagName == 'article' ||
          tagName == 'ul' ||
          tagName == 'ol' ||
          tagName == 'li' ||
          tagName == 'blockquote' ||
          (tagName.length == 2 && tagName.startsWith('h'));

      if (isBlockElement) {
        flushCurrentBlock();
      }

      for (final child in node.nodes) {
        walk(child, childScope);
      }

      if (isUl || isOl) {
        if (listStack.isNotEmpty) {
          listStack.removeLast();
        }
      }

      if (isBlockElement) {
        flushCurrentBlock();
      }
    }

    for (final topNode in fragment.nodes) {
      walk(topNode, const _StyleScope());
    }
    flushCurrentBlock();

    return blocks;
  }

  /// 纯文本回退解析（无 HTML 结构时）
  static List<StructuredBlock> parseText(String text,
      {bool firstLineIndent = false}) {
    if (text.trim().isEmpty) return const [];
    final rawLines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_resPlaceholderRe, '')
        .split('\n');

    final blocks = <StructuredBlock>[];
    for (final rawLine in rawLines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (firstLineIndent) {
        if (!line.startsWith('\u3000') && !line.startsWith('  ')) {
          line = '\u3000\u3000$line';
        }
      } else {
        while (line.startsWith('\u3000') || line.startsWith(' ')) {
          line = line.substring(1);
        }
        if (line.trim().isEmpty) continue;
      }
      final block = StructuredBlock(
        type: StructuredBlockType.paragraph,
        text: line,
        runs: [StructuredInlineRun(text: line)],
      );
      _appendSplitBlock(blocks, block);
    }
    return blocks;
  }

  /// 解析内联 CSS style
  static _StyleScope _applyInlineStyle(String style, _StyleScope current) {
    var updated = current;
    final declarations = style.split(';');
    for (final decl in declarations) {
      final kv = decl.split(':');
      if (kv.length < 2) continue;
      final key = kv[0].trim().toLowerCase();
      final val = kv.sublist(1).join(':').trim().toLowerCase();

      if (key == 'font-weight') {
        final weight = _parseCssFontWeight(val);
        if (weight != null) {
          updated = updated.copyWith(
            isBold: weight.value >= FontWeight.w600.value,
            fontWeight: weight,
          );
        }
      } else if (key == 'font-size') {
        final multiplier = _parseCssFontSizeMultiplier(val);
        if (multiplier != null) {
          final isRelative = val == 'smaller' ||
              val == 'larger' ||
              (val.endsWith('em') && !val.endsWith('rem')) ||
              val.endsWith('%');
          updated = updated.copyWith(
            fontSizeMultiplier:
                isRelative
                    ? (updated.fontSizeMultiplier ?? 1.0) * multiplier
                    : multiplier,
          );
        }
      } else if (key == 'vertical-align') {
        if (val == 'super') {
          updated = updated.copyWith(
            verticalAlignment: StructuredVerticalAlignment.superscript,
          );
        } else if (val == 'sub') {
          updated = updated.copyWith(
            verticalAlignment: StructuredVerticalAlignment.subscript,
          );
        }
      } else if (key == 'font-style') {
        if (val == 'italic' || val == 'oblique') {
          updated = updated.copyWith(isItalic: true);
        } else if (val == 'normal') {
          updated = updated.copyWith(isItalic: false);
        }
      } else if (key == 'text-decoration') {
        if (val.contains('underline')) {
          updated = updated.copyWith(isUnderline: true);
        }
        if (val.contains('line-through')) {
          updated = updated.copyWith(isStrikethrough: true);
        }
      } else if (key == 'color') {
        final parsedColor = _parseCssColor(val);
        if (parsedColor != null) {
          updated = updated.copyWith(color: parsedColor);
        }
      } else if (key == 'text-align') {
        if (val == 'center') {
          updated = updated.copyWith(align: TextAlign.center);
        } else if (val == 'right') {
          updated = updated.copyWith(align: TextAlign.right);
        } else if (val == 'justify') {
          updated = updated.copyWith(align: TextAlign.justify);
        } else if (val == 'left' || val == 'start') {
          updated = updated.copyWith(align: TextAlign.left);
        }
      }
    }
    return updated;
  }

  static FontWeight? _parseCssFontWeight(String value) {
    switch (value) {
      case 'normal':
      case 'lighter':
      case '400':
        return FontWeight.w400;
      case 'bold':
      case 'bolder':
      case '700':
        return FontWeight.w700;
      case '100':
        return FontWeight.w100;
      case '200':
        return FontWeight.w200;
      case '300':
        return FontWeight.w300;
      case '500':
        return FontWeight.w500;
      case '600':
        return FontWeight.w600;
      case '800':
        return FontWeight.w800;
      case '900':
        return FontWeight.w900;
      default:
        return null;
    }
  }

  static double? _parseCssFontSizeMultiplier(String value) {
    switch (value) {
      case 'xx-small':
        return 0.60;
      case 'x-small':
        return 0.75;
      case 'small':
      case 'smaller':
        return 0.83;
      case 'medium':
        return 1.0;
      case 'large':
      case 'larger':
        return 1.2;
      case 'x-large':
        return 1.5;
      case 'xx-large':
        return 2.0;
    }

    final match = _cssFontSizePattern.firstMatch(value);
    if (match == null) return null;
    final amount = double.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) return null;
    final unit = match.group(2) ?? 'px';
    final multiplier = switch (unit) {
      'px' => amount / 16.0,
      'pt' => amount * (4.0 / 3.0) / 16.0,
      'em' || 'rem' => amount,
      '%' => amount / 100.0,
      _ => null,
    };
    if (multiplier == null || !multiplier.isFinite) return null;
    return multiplier.clamp(0.25, 4.0).toDouble();
  }

  /// 支持 #RGB, #RRGGBB, #AARRGGBB, rgb(r, g, b), rgba(r, g, b, a) 以及标准颜色名
  static Color? _parseCssColor(String raw) {
    var v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    if (_namedColors.containsKey(v)) {
      return _namedColors[v];
    }

    if (v.startsWith('#')) {
      final hex = v.substring(1);
      if (hex.length == 3) {
        final r = int.tryParse('${hex[0]}${hex[0]}', radix: 16);
        final g = int.tryParse('${hex[1]}${hex[1]}', radix: 16);
        final b = int.tryParse('${hex[2]}${hex[2]}', radix: 16);
        if (r != null && g != null && b != null) {
          return Color.fromARGB(255, r, g, b);
        }
      } else if (hex.length == 6) {
        final numVal = int.tryParse(hex, radix: 16);
        if (numVal != null) {
          return Color(0xFF000000 | numVal);
        }
      } else if (hex.length == 8) {
        final numVal = int.tryParse(hex, radix: 16);
        if (numVal != null) {
          return Color(numVal);
        }
      }
      return null;
    }

    if (v.startsWith('rgb(') && v.endsWith(')')) {
      final inner = v.substring(4, v.length - 1);
      final parts = inner.split(',').map((e) => e.trim()).toList();
      if (parts.length == 3) {
        final r = int.tryParse(parts[0]);
        final g = int.tryParse(parts[1]);
        final b = int.tryParse(parts[2]);
        if (r != null && g != null && b != null) {
          return Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
        }
      }
    } else if (v.startsWith('rgba(') && v.endsWith(')')) {
      final inner = v.substring(5, v.length - 1);
      final parts = inner.split(',').map((e) => e.trim()).toList();
      if (parts.length == 4) {
        final r = int.tryParse(parts[0]);
        final g = int.tryParse(parts[1]);
        final b = int.tryParse(parts[2]);
        final a = double.tryParse(parts[3]);
        if (r != null && g != null && b != null && a != null) {
          return Color.fromARGB(
            (a * 255).round().clamp(0, 255),
            r.clamp(0, 255),
            g.clamp(0, 255),
            b.clamp(0, 255),
          );
        }
      }
    }

    return null;
  }

  static const Map<String, Color> _namedColors = {
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'gray': Colors.grey,
    'grey': Colors.grey,
    'cyan': Colors.cyan,
    'magenta': Colors.pinkAccent,
    'pink': Colors.pink,
    'brown': Colors.brown,
    'gold': Color(0xFFFFD700),
    'silver': Color(0xFFC0C0C0),
  };

  /// 针对超长段落按自然边界拆分，防止单段几十万字导致界面卡死或排版异常
  static void _appendSplitBlock(
      List<StructuredBlock> list, StructuredBlock block) {
    if (block.text.length <= maxTextBlockLength) {
      list.add(block);
      return;
    }

    var start = 0;
    while (start < block.text.length) {
      var end = (start + maxTextBlockLength).clamp(0, block.text.length).toInt();
      if (end < block.text.length) {
        for (var i = end; i > start + (maxTextBlockLength ~/ 2); i--) {
          final code = block.text.codeUnitAt(i - 1);
          if (code == 0x20 || code == 0x09) {
            end = i;
            break;
          }
        }
        if (end < block.text.length) {
          final prev = block.text.codeUnitAt(end - 1);
          if (prev >= 0xD800 && prev <= 0xDBFF) {
            end--;
          }
        }
      }
      if (end <= start) break;
      final sliced = block.slice(start, end);
      if (sliced.text.isNotEmpty) {
        list.add(sliced);
      }
      start = end;
    }
  }

  /// 仅转换结构化正文中的文本与注音，绝对不修改任何标签、属性、URL 与 CSS
  static Future<List<StructuredBlock>> convertBlocks(
    List<StructuredBlock> blocks,
    int mode,
  ) async {
    if (mode != 1 && mode != 2) return blocks;

    final result = <StructuredBlock>[];
    for (final block in blocks) {
      if (block.isImage || block.isDivider || block.runs.isEmpty) {
        result.add(block);
        continue;
      }

      final newRuns = <StructuredInlineRun>[];
      for (final run in block.runs) {
        final convText = mode == 1
            ? await ChineseConverter.convert(run.text, S2T())
            : await ChineseConverter.convert(run.text, T2S());
        String? convRuby;
        String? convRubyBase;
        if (run.rubyText != null && run.rubyText!.isNotEmpty) {
          convRuby = mode == 1
              ? await ChineseConverter.convert(run.rubyText!, S2T())
              : await ChineseConverter.convert(run.rubyText!, T2S());
          final rubyBase = run.rubyBaseText;
          if (rubyBase != null) {
            convRubyBase = mode == 1
                ? await ChineseConverter.convert(rubyBase, S2T())
                : await ChineseConverter.convert(rubyBase, T2S());
          }
        }
        newRuns.add(run.copyWith(
          text: convText,
          rubyText: convRuby,
          rubyBaseText: convRubyBase,
        ));
      }

      final fullText = newRuns.map((r) => r.text).join();
      result.add(StructuredBlock(
        type: block.type,
        text: fullText,
        runs: List.unmodifiable(newRuns),
        headingLevel: block.headingLevel,
        align: block.align,
        indent: block.indent,
        anchorId: block.anchorId,
        listNumber: block.listNumber,
      ));
    }
    return result;
  }
}
