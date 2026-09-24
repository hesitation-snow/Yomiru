import 'package:flutter/material.dart';
import '../reader/reader_typography.dart';

/// 借鉴 Apple Books 风格的排版设置面板
class ReaderTypographySheet extends StatefulWidget {
  final ReaderTypography initialTypography;
  final double fontSize;
  final ValueChanged<double>? onFontSizeChanged;
  final Color textColor;
  final Color backgroundColor;
  final Color linkColor;
  final bool isDark;
  final ValueChanged<ReaderTypography> onPreviewChange;
  final ValueChanged<ReaderTypography> onCommit;

  const ReaderTypographySheet({
    super.key,
    required this.initialTypography,
    required this.fontSize,
    this.onFontSizeChanged,
    required this.textColor,
    required this.backgroundColor,
    required this.linkColor,
    required this.isDark,
    required this.onPreviewChange,
    required this.onCommit,
  });

  @override
  State<ReaderTypographySheet> createState() => ReaderTypographySheetState();
}

class ReaderTypographySheetState extends State<ReaderTypographySheet> {
  late ReaderTypography _current;
  late double _fontSize;
  bool _moreExpanded = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialTypography;
    _fontSize = widget.fontSize;
  }

  @override
  void didUpdateWidget(ReaderTypographySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fontSize != oldWidget.fontSize) {
      _fontSize = widget.fontSize;
    }
  }

  /// 供外部在关闭面板前确认最后一次提交
  void commitCurrent() {
    widget.onCommit(_current);
  }

  void _updatePreview(ReaderTypography updated) {
    setState(() => _current = updated);
    widget.onPreviewChange(updated);
  }

  void _commitChange(ReaderTypography updated) {
    setState(() => _current = updated);
    widget.onCommit(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTileTheme(
      data: const ListTileThemeData(
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
        contentPadding: EdgeInsets.zero,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 1. 顶部排版实时预览卡片
          _buildPreviewCard(scheme),
          const SizedBox(height: 16),

          // 2. 快捷预设胶囊
          _buildPresetBar(scheme),
          const SizedBox(height: 16),

          // 3. 常用排版滑杆分组
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 字号大小
                  _buildSliderRow(
                    label: '字号大小',
                    value: _fontSize,
                    min: 12.0,
                    max: 28.0,
                    divisions: 16,
                    valueText: '${_fontSize.toStringAsFixed(0)} pt',
                    defaultValue: 17.0,
                    onChanged: (v) {
                      setState(() => _fontSize = v);
                      widget.onFontSizeChanged?.call(v);
                    },
                    onChangeEnd: (v) {
                      widget.onFontSizeChanged?.call(v);
                    },
                  ),
                  const Divider(height: 16, thickness: 0.5),

                  // 行间距
                  _buildSliderRow(
                    label: '行间距',
                    value: _current.lineHeight,
                    min: 1.20,
                    max: 2.40,
                    divisions: 24,
                    valueText: _current.lineHeight.toStringAsFixed(2),
                    defaultValue: 1.70,
                    onChanged: (v) =>
                        _updatePreview(_current.copyWith(lineHeight: v)),
                    onChangeEnd: (v) =>
                        _commitChange(_current.copyWith(lineHeight: v)),
                  ),
                  const Divider(height: 16, thickness: 0.5),

                  // 段落间距
                  _buildSliderRow(
                    label: '段落间距',
                    value: _current.paragraphSpacing,
                    min: 0.0,
                    max: 32.0,
                    divisions: 16,
                    valueText: '${_current.paragraphSpacing.round()} px',
                    defaultValue: 12.0,
                    onChanged: (v) =>
                        _updatePreview(_current.copyWith(paragraphSpacing: v)),
                    onChangeEnd: (v) =>
                        _commitChange(_current.copyWith(paragraphSpacing: v)),
                  ),
                  const Divider(height: 16, thickness: 0.5),

                  // 字符间距
                  _buildSliderRow(
                    label: '字符间距',
                    value: _current.letterSpacing,
                    min: -0.5,
                    max: 2.5,
                    divisions: 30,
                    valueText:
                        '${_current.letterSpacing >= 0 ? '+' : ''}${_current.letterSpacing.toStringAsFixed(1)} pt',
                    defaultValue: 0.3,
                    onChanged: (v) =>
                        _updatePreview(_current.copyWith(letterSpacing: v)),
                    onChangeEnd: (v) =>
                        _commitChange(_current.copyWith(letterSpacing: v)),
                  ),
                  const Divider(height: 16, thickness: 0.5),

                  // 页边留白（左右联动）
                  _buildSliderRow(
                    label: '页边留白',
                    value: _current.marginHorizontal,
                    min: 8.0,
                    max: 48.0,
                    divisions: 20,
                    valueText: '${_current.marginHorizontal.round()} dp',
                    defaultValue: 20.0,
                    enabled: !_current.customMargins,
                    onChanged: (v) =>
                        _updatePreview(_current.copyWith(marginHorizontal: v)),
                    onChangeEnd: (v) =>
                        _commitChange(_current.copyWith(marginHorizontal: v)),
                  ),
                  const Divider(height: 16, thickness: 0.5),

                  // 两端对齐开关
                  _buildSwitchTile(
                    title: '两端对齐',
                    subtitle: '段内文字平整铺满，段末行保持自然',
                    value: _current.justify,
                    onChanged: (v) {
                      final updated = _current.copyWith(justify: v);
                      _commitChange(updated);
                    },
                    scheme: scheme,
                  ),
                  const Divider(height: 16, thickness: 0.5),

                // 分栏模式
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '分栏模式',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '仅对翻页模式生效',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SegmentedButton<ReaderColumnMode>(
                      segments: const [
                        ButtonSegment(
                          value: ReaderColumnMode.auto,
                          label: Text('自动', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: ReaderColumnMode.single,
                          label: Text('单栏', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: ReaderColumnMode.doubleColumn,
                          label: Text('双栏', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {_current.columnMode},
                      onSelectionChanged: (set) {
                        final updated = _current.copyWith(columnMode: set.first);
                        _commitChange(updated);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4. 折叠的「更多设置」
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() => _moreExpanded = !_moreExpanded);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _moreExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '更多排版设置',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _current.customMargins ? '高级边距已开启' : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_moreExpanded) ...[
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1, thickness: 0.5),
                      const SizedBox(height: 12),

                      // 词间距
                      _buildSliderRow(
                        label: '词间距',
                        value: _current.wordSpacing,
                        min: 0.0,
                        max: 8.0,
                        divisions: 16,
                        valueText:
                            '${_current.wordSpacing.toStringAsFixed(1)} pt',
                        defaultValue: 0.0,
                        onChanged: (v) =>
                            _updatePreview(_current.copyWith(wordSpacing: v)),
                        onChangeEnd: (v) =>
                            _commitChange(_current.copyWith(wordSpacing: v)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(
                          '仅对空格分隔的外文/数字单词生效，纯中文无空格不影响',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const Divider(height: 16, thickness: 0.5),

                      // 首行缩进
                      _buildSwitchTile(
                        title: '首行缩进',
                        subtitle: '普通正文段落首行缩进两字符宽',
                        value: _current.firstLineIndentChars > 0,
                        onChanged: (v) {
                          final updated = _current.copyWith(
                            firstLineIndentChars: v ? 2.0 : 0.0,
                          );
                          _commitChange(updated);
                        },
                        scheme: scheme,
                      ),
                      const Divider(height: 16, thickness: 0.5),

                      // 独立调整四周边距开关
                      _buildSwitchTile(
                        title: '独立四周边距',
                        subtitle: _current.customMargins
                            ? '当前使用下方独立边距'
                            : '开启后可独立微调上、下、左、右边距',
                        value: _current.customMargins,
                        onChanged: (v) {
                          final updated = _current.copyWith(customMargins: v);
                          _commitChange(updated);
                        },
                        scheme: scheme,
                      ),

                      if (_current.customMargins) ...[
                        const SizedBox(height: 8),
                        _buildSliderRow(
                          label: '上边距',
                          value: _current.marginTop,
                          min: 44.0,
                          max: 120.0,
                          divisions: 38,
                          valueText: '${_current.marginTop.round()} dp',
                          defaultValue: 56.0,
                          onChanged: (v) =>
                              _updatePreview(_current.copyWith(marginTop: v)),
                          onChangeEnd: (v) =>
                              _commitChange(_current.copyWith(marginTop: v)),
                        ),
                        const SizedBox(height: 8),
                        _buildSliderRow(
                          label: '下边距',
                          value: _current.marginBottom,
                          min: 50.0,
                          max: 140.0,
                          divisions: 45,
                          valueText: '${_current.marginBottom.round()} dp',
                          defaultValue: 70.0,
                          onChanged: (v) => _updatePreview(
                              _current.copyWith(marginBottom: v)),
                          onChangeEnd: (v) =>
                              _commitChange(_current.copyWith(marginBottom: v)),
                        ),
                        const SizedBox(height: 8),
                        _buildSliderRow(
                          label: '左边距',
                          value: _current.marginLeft,
                          min: 8.0,
                          max: 60.0,
                          divisions: 26,
                          valueText: '${_current.marginLeft.round()} dp',
                          defaultValue: 20.0,
                          onChanged: (v) =>
                              _updatePreview(_current.copyWith(marginLeft: v)),
                          onChangeEnd: (v) =>
                              _commitChange(_current.copyWith(marginLeft: v)),
                        ),
                        const SizedBox(height: 8),
                        _buildSliderRow(
                          label: '右边距',
                          value: _current.marginRight,
                          min: 8.0,
                          max: 60.0,
                          divisions: 26,
                          valueText: '${_current.marginRight.round()} dp',
                          defaultValue: 20.0,
                          onChanged: (v) =>
                              _updatePreview(_current.copyWith(marginRight: v)),
                          onChangeEnd: (v) =>
                              _commitChange(_current.copyWith(marginRight: v)),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // 恢复默认排版按钮
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final std = ReaderTypography.standard();
                            _commitChange(std);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('恢复默认排版'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

  /// 统一的开关行（去除深色独立卡片底色，与排版卡片无缝融合）
  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme scheme,
  }) {
    return SwitchListTile(
      tileColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            )
          : null,
      value: value,
      onChanged: onChanged,
    );
  }

  /// 顶部实时排版预览卡片
  Widget _buildPreviewCard(ColorScheme scheme) {
    final previewIndent = _current.firstLineIndentChars * _fontSize;
    final textStyle = TextStyle(
      fontSize: _fontSize.clamp(13.0, 18.0),
      height: _current.lineHeight,
      color: widget.textColor,
      letterSpacing: _current.letterSpacing,
      wordSpacing: _current.wordSpacing > 0 ? _current.wordSpacing : null,
    );

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.remove_red_eye_outlined,
                  size: 14, color: widget.textColor.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                '排版预览',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.textColor.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              Text(
                '${_current.currentPreset.label} · 行高 ${_current.lineHeight.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11,
                  color: widget.textColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '第一章 晨光初启',
            style: textStyle.copyWith(
              fontSize: textStyle.fontSize! * 1.15,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          SizedBox(height: _current.paragraphSpacing * 0.6),
          Text.rich(
            TextSpan(
              children: [
                if (previewIndent > 0)
                  WidgetSpan(
                    child: SizedBox(width: previewIndent, height: 1.0),
                  ),
                const TextSpan(
                  text: '微风轻柔地拂过静谧的平原，晨曦将远方的山岚染成一片浅金。旅人背好行囊，向着地平线迈出坚定的步伐。',
                ),
              ],
              style: textStyle,
            ),
            textAlign: _current.justify ? TextAlign.justify : TextAlign.start,
          ),
          SizedBox(height: _current.paragraphSpacing * 0.6),
          Text.rich(
            TextSpan(
              children: [
                if (previewIndent > 0)
                  WidgetSpan(
                    child: SizedBox(width: previewIndent, height: 1.0),
                  ),
                const TextSpan(
                  text: '文字如涟漪般在纸页间舒展（Light Novel），留驻下时光最深邃的印记。',
                ),
              ],
              style: textStyle,
            ),
            textAlign: _current.justify ? TextAlign.justify : TextAlign.start,
          ),
        ],
      ),
    );
  }

  /// 预设选择胶囊栏
  Widget _buildPresetBar(ColorScheme scheme) {
    final active = _current.currentPreset;
    return Row(
      children: [
        for (final preset in [
          ReaderTypographyPreset.compact,
          ReaderTypographyPreset.standard,
          ReaderTypographyPreset.loose,
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  final target = switch (preset) {
                    ReaderTypographyPreset.compact =>
                      ReaderTypography.compact(),
                    ReaderTypographyPreset.standard =>
                      ReaderTypography.standard(),
                    ReaderTypographyPreset.loose => ReaderTypography.loose(),
                    _ => ReaderTypography.standard(),
                  };
                  _commitChange(target);
                },
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: active == preset
                        ? scheme.primary
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active == preset
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active == preset ? FontWeight.bold : FontWeight.w500,
                      color: active == preset
                          ? scheme.onPrimary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (active == ReaderTypographyPreset.custom)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '自定义',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Apple Books 风格的精简低对比度滑杆行
  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueText,
    required double defaultValue,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clampedValue = value.clamp(min, max);

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Row(
        children: [
          // 左侧参数名称
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // 中间滑杆
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
                thumbColor: scheme.primary,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 1.5,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: clampedValue,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            ),
          ),

          // 右侧固定宽度数值（防止数字跳变挤压滑杆）
          SizedBox(
            width: 52,
            child: Text(
              valueText,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: (clampedValue - defaultValue).abs() < 0.02
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
