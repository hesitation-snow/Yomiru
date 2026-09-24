import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// 翻页分栏模式
enum ReaderColumnMode {
  /// 智能自动判断（可用宽度与每栏文字容量足够时双栏，否则单栏）
  auto,

  /// 强制单栏
  single,

  /// 强制双栏（仅在翻页模式下生效）
  doubleColumn;

  String get label => switch (this) {
        ReaderColumnMode.auto => '自动',
        ReaderColumnMode.single => '单栏',
        ReaderColumnMode.doubleColumn => '双栏',
      };
}

/// 排版快捷预设
enum ReaderTypographyPreset {
  compact('紧凑'),
  standard('标准'),
  loose('宽松'),
  custom('自定义');

  final String label;
  const ReaderTypographyPreset(this.label);
}

/// 统一排版配置模型
@immutable
class ReaderTypography {
  /// 行间距倍率（例如 1.20 ~ 2.40，标准 1.70）
  final double lineHeight;

  /// 段落间距（单位 px，例如 0 ~ 32，标准 12.0）
  final double paragraphSpacing;

  /// 字符间距（单位 pt，例如 -0.5 ~ 3.0，标准 0.3）
  final double letterSpacing;

  /// 词间距（单位 pt，主要影响西文/空格分隔的词，标准 0.0）
  final double wordSpacing;

  /// 首行缩进字符数（例如 0、1、2 字符，标准 0）
  final double firstLineIndentChars;

  /// 两端对齐（仅作用于普通正文，段落末行不强制撑开）
  final bool justify;

  /// 是否启用自适应留白基线
  final bool autoMargin;

  /// 基础页边留白（左右联动调整，例如 8 ~ 48 dp，标准 20.0）
  final double marginHorizontal;

  /// 是否开启独立四周边距微调（高级模式）
  final bool customMargins;

  /// 独立上边距（默认 56.0）
  final double marginTop;

  /// 独立下边距（默认 70.0）
  final double marginBottom;

  /// 独立左边距（默认 20.0）
  final double marginLeft;

  /// 独立右边距（默认 20.0）
  final double marginRight;

  /// 分栏模式（自动 / 单栏 / 双栏）
  final ReaderColumnMode columnMode;

  const ReaderTypography({
    this.lineHeight = 1.70,
    this.paragraphSpacing = 12.0,
    this.letterSpacing = 0.3,
    this.wordSpacing = 0.0,
    this.firstLineIndentChars = 0.0,
    this.justify = false,
    this.autoMargin = true,
    this.marginHorizontal = 20.0,
    this.customMargins = false,
    this.marginTop = 56.0,
    this.marginBottom = 70.0,
    this.marginLeft = 20.0,
    this.marginRight = 20.0,
    this.columnMode = ReaderColumnMode.auto,
  });

  /// 标准预设（默认配置）
  factory ReaderTypography.standard() => const ReaderTypography();

  /// 紧凑预设
  factory ReaderTypography.compact() => const ReaderTypography(
        lineHeight: 1.45,
        paragraphSpacing: 6.0,
        letterSpacing: 0.0,
        wordSpacing: 0.0,
        firstLineIndentChars: 0.0,
        justify: true,
        autoMargin: true,
        marginHorizontal: 14.0,
        customMargins: false,
        marginTop: 46.0,
        marginBottom: 56.0,
        marginLeft: 14.0,
        marginRight: 14.0,
        columnMode: ReaderColumnMode.auto,
      );

  /// 宽松预设
  factory ReaderTypography.loose() => const ReaderTypography(
        lineHeight: 2.00,
        paragraphSpacing: 20.0,
        letterSpacing: 0.8,
        wordSpacing: 1.5,
        firstLineIndentChars: 0.0,
        justify: false,
        autoMargin: true,
        marginHorizontal: 28.0,
        customMargins: false,
        marginTop: 66.0,
        marginBottom: 84.0,
        marginLeft: 28.0,
        marginRight: 28.0,
        columnMode: ReaderColumnMode.auto,
      );

  /// 判断当前所匹配的预设
  ReaderTypographyPreset get currentPreset {
    if (_isClose(lineHeight, 1.70) &&
        _isClose(paragraphSpacing, 12.0) &&
        _isClose(letterSpacing, 0.3) &&
        _isClose(wordSpacing, 0.0) &&
        _isClose(firstLineIndentChars, 0.0) &&
        justify == false &&
        _isClose(marginHorizontal, 20.0) &&
        !customMargins) {
      return ReaderTypographyPreset.standard;
    }
    if (_isClose(lineHeight, 1.45) &&
        _isClose(paragraphSpacing, 6.0) &&
        _isClose(letterSpacing, 0.0) &&
        _isClose(wordSpacing, 0.0) &&
        _isClose(firstLineIndentChars, 0.0) &&
        justify == true &&
        _isClose(marginHorizontal, 14.0) &&
        !customMargins) {
      return ReaderTypographyPreset.compact;
    }
    if (_isClose(lineHeight, 2.00) &&
        _isClose(paragraphSpacing, 20.0) &&
        _isClose(letterSpacing, 0.8) &&
        _isClose(wordSpacing, 1.5) &&
        _isClose(firstLineIndentChars, 0.0) &&
        justify == false &&
        _isClose(marginHorizontal, 28.0) &&
        !customMargins) {
      return ReaderTypographyPreset.loose;
    }
    return ReaderTypographyPreset.custom;
  }

  static bool _isClose(double a, double b) => (a - b).abs() < 0.02;

  ReaderTypography copyWith({
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    double? wordSpacing,
    double? firstLineIndentChars,
    bool? justify,
    bool? autoMargin,
    double? marginHorizontal,
    bool? customMargins,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
    ReaderColumnMode? columnMode,
  }) {
    return ReaderTypography(
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      firstLineIndentChars: firstLineIndentChars ?? this.firstLineIndentChars,
      justify: justify ?? this.justify,
      autoMargin: autoMargin ?? this.autoMargin,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      customMargins: customMargins ?? this.customMargins,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
      columnMode: columnMode ?? this.columnMode,
    );
  }

  /// 自适应计算排版内边距
  ///
  /// [screenWidth] 当前视口宽度
  /// [screenHeight] 当前视口高度
  /// [isDoubleColumn] 当前是否生效双栏
  EdgeInsets computePadding({
    required double screenWidth,
    required double screenHeight,
    bool isDoubleColumn = false,
  }) {
    if (customMargins) {
      // 高级模式：使用用户独立设置的四周边距，并确保不压迫顶部指示器与底部状态栏
      final safeTop = math.max(marginTop, 44.0);
      final safeBottom = math.max(marginBottom, 50.0);
      final safeLeft = math.max(marginLeft, 8.0);
      final safeRight = math.max(marginRight, 8.0);
      return EdgeInsets.fromLTRB(safeLeft, safeTop, safeRight, safeBottom);
    }

    // 普通联动模式：
    // 1. 垂直边距：预留顶部章节名（>= 44dp）和底部时间进度（>= 50dp）
    const baseTop = 56.0;
    const baseBottom = 70.0;

    // 2. 水平边距：自适应基线计算
    double effectiveHoriz = marginHorizontal;
    if (autoMargin) {
      if (!isDoubleColumn && screenWidth >= 640.0) {
        // 平板或宽屏单栏时：限制正文舒适阅读最大宽度为 680dp，避免单行横跨整个大屏导致阅读疲劳
        const maxContentWidth = 680.0;
        final extraSide = math.max(0.0, (screenWidth - maxContentWidth) / 2.0);
        effectiveHoriz = marginHorizontal + extraSide;
      }
    }

    return EdgeInsets.fromLTRB(
      effectiveHoriz,
      baseTop,
      effectiveHoriz,
      baseBottom,
    );
  }

  Map<String, dynamic> toJson() => {
        'line_height': lineHeight,
        'paragraph_spacing': paragraphSpacing,
        'letter_spacing': letterSpacing,
        'word_spacing': wordSpacing,
        'first_line_indent': firstLineIndentChars,
        'justify': justify,
        'auto_margin': autoMargin,
        'margin_horizontal': marginHorizontal,
        'custom_margins': customMargins,
        'margin_top': marginTop,
        'margin_bottom': marginBottom,
        'margin_left': marginLeft,
        'margin_right': marginRight,
        'column_mode': columnMode.name,
      };

  factory ReaderTypography.fromJson(Map<String, dynamic> json) {
    return ReaderTypography(
      lineHeight: (json['line_height'] as num?)?.toDouble() ?? 1.70,
      paragraphSpacing:
          (json['paragraph_spacing'] as num?)?.toDouble() ?? 12.0,
      letterSpacing: (json['letter_spacing'] as num?)?.toDouble() ?? 0.3,
      wordSpacing: (json['word_spacing'] as num?)?.toDouble() ?? 0.0,
      firstLineIndentChars:
          (json['first_line_indent'] as num?)?.toDouble() ?? 0.0,
      justify: json['justify'] == true,
      autoMargin: json['auto_margin'] != false,
      marginHorizontal:
          (json['margin_horizontal'] as num?)?.toDouble() ?? 20.0,
      customMargins: json['custom_margins'] == true,
      marginTop: (json['margin_top'] as num?)?.toDouble() ?? 56.0,
      marginBottom: (json['margin_bottom'] as num?)?.toDouble() ?? 70.0,
      marginLeft: (json['margin_left'] as num?)?.toDouble() ?? 20.0,
      marginRight: (json['margin_right'] as num?)?.toDouble() ?? 20.0,
      columnMode: ReaderColumnMode.values.firstWhere(
        (m) => m.name == json['column_mode'],
        orElse: () => ReaderColumnMode.auto,
      ),
    );
  }
}
