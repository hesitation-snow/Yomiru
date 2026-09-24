import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/reader/reader_typography.dart';
import 'package:yomiru/widgets/reader_typography_sheet.dart';

void main() {
  group('ReaderTypography Model & Adaptive Margins', () {
    test('Presets match standard, compact, loose, and detect custom', () {
      final std = ReaderTypography.standard();
      expect(std.currentPreset, equals(ReaderTypographyPreset.standard));
      expect(std.lineHeight, equals(1.70));
      expect(std.paragraphSpacing, equals(12.0));

      final compact = ReaderTypography.compact();
      expect(compact.currentPreset, equals(ReaderTypographyPreset.compact));
      expect(compact.lineHeight, equals(1.45));
      expect(compact.justify, isTrue);

      final loose = ReaderTypography.loose();
      expect(loose.currentPreset, equals(ReaderTypographyPreset.loose));
      expect(loose.lineHeight, equals(2.00));
      expect(loose.paragraphSpacing, equals(20.0));

      final modified = std.copyWith(lineHeight: 1.85);
      expect(modified.currentPreset, equals(ReaderTypographyPreset.custom));
    });

    test('Adaptive margin on phones uses marginHorizontal', () {
      final typo = ReaderTypography.standard();
      final pad = typo.computePadding(
        screenWidth: 390.0,
        screenHeight: 844.0,
      );

      // 手机端：水平边距即 marginHorizontal (20.0)，垂直预留顶部与底部
      expect(pad.left, equals(20.0));
      expect(pad.right, equals(20.0));
      expect(pad.top, equals(56.0));
      expect(pad.bottom, equals(70.0));
    });

    test('Adaptive margin on tablets constrains max text width in single column', () {
      final typo = ReaderTypography.standard();
      final pad = typo.computePadding(
        screenWidth: 1000.0,
        screenHeight: 800.0,
        isDoubleColumn: false,
      );

      // 平板单栏：maxContentWidth 为 680，多余 (1000 - 680) / 2 = 160 匀入左右
      // 因此左右为 20 + 160 = 180
      expect(pad.left, equals(180.0));
      expect(pad.right, equals(180.0));
      expect(1000.0 - pad.left - pad.right, equals(640.0));
    });

    test('Custom margins take precedence in advanced mode with minimum safety bounds', () {
      const typo = ReaderTypography(
        customMargins: true,
        marginTop: 60.0,
        marginBottom: 80.0,
        marginLeft: 15.0,
        marginRight: 25.0,
      );
      final pad = typo.computePadding(
        screenWidth: 1000.0,
        screenHeight: 800.0,
      );

      expect(pad.left, equals(15.0));
      expect(pad.right, equals(25.0));
      expect(pad.top, equals(60.0));
      expect(pad.bottom, equals(80.0));
    });

    test('Serialization to and from JSON preserves all fields', () {
      const original = ReaderTypography(
        lineHeight: 1.82,
        paragraphSpacing: 16.0,
        letterSpacing: 0.5,
        wordSpacing: 1.0,
        firstLineIndentChars: 2.0,
        justify: true,
        autoMargin: false,
        marginHorizontal: 24.0,
        customMargins: true,
        marginTop: 62.0,
        marginBottom: 72.0,
        marginLeft: 18.0,
        marginRight: 18.0,
        columnMode: ReaderColumnMode.doubleColumn,
      );

      final json = original.toJson();
      final restored = ReaderTypography.fromJson(json);

      expect(restored.lineHeight, equals(original.lineHeight));
      expect(restored.paragraphSpacing, equals(original.paragraphSpacing));
      expect(restored.letterSpacing, equals(original.letterSpacing));
      expect(restored.wordSpacing, equals(original.wordSpacing));
      expect(restored.firstLineIndentChars, equals(original.firstLineIndentChars));
      expect(restored.justify, equals(original.justify));
      expect(restored.autoMargin, equals(original.autoMargin));
      expect(restored.marginHorizontal, equals(original.marginHorizontal));
      expect(restored.customMargins, equals(original.customMargins));
      expect(restored.marginTop, equals(original.marginTop));
      expect(restored.marginBottom, equals(original.marginBottom));
      expect(restored.marginLeft, equals(original.marginLeft));
      expect(restored.marginRight, equals(original.marginRight));
      expect(restored.columnMode, equals(ReaderColumnMode.doubleColumn));
    });
  });

  group('ReaderTypographySheet Widget Tests', () {
    testWidgets('Renders all typography controls and updates settings', (tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ReaderTypography current = const ReaderTypography();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReaderTypographySheet(
            initialTypography: current,
            fontSize: 17.0,
            textColor: const Color(0xFF000000),
            backgroundColor: const Color(0xFFFFFFFF),
            linkColor: const Color(0xFF1E88E5),
            isDark: false,
            onPreviewChange: (t) => current = t,
            onCommit: (t) => current = t,
          ),
        ),
      ));

      // 常用设置检查
      expect(find.text('排版预览'), findsOneWidget);
      expect(find.text('紧凑'), findsOneWidget);
      expect(find.text('标准'), findsOneWidget);
      expect(find.text('宽松'), findsOneWidget);
      expect(find.text('行间距'), findsOneWidget);
      expect(find.text('段落间距'), findsOneWidget);
      expect(find.text('字符间距'), findsOneWidget);
      expect(find.text('页边留白'), findsOneWidget);
      expect(find.text('两端对齐'), findsOneWidget);
      expect(find.text('分栏模式'), findsOneWidget);
      expect(find.text('自动'), findsOneWidget);
      expect(find.text('单栏'), findsOneWidget);
      expect(find.text('双栏'), findsOneWidget);

      // 切换紧凑预设
      await tester.tap(find.text('紧凑'));
      await tester.pumpAndSettle();
      expect(current.currentPreset, equals(ReaderTypographyPreset.compact));

      // 展开「更多排版设置」
      await tester.ensureVisible(find.text('更多排版设置'));
      await tester.tap(find.text('更多排版设置'));
      await tester.pumpAndSettle();

      expect(find.text('词间距'), findsOneWidget);
      expect(find.text('首行缩进'), findsOneWidget);
      expect(find.text('独立四周边距'), findsOneWidget);
      expect(find.text('恢复默认排版'), findsOneWidget);

      // 切换首行缩进
      await tester.ensureVisible(find.text('首行缩进'));
      await tester.tap(find.text('首行缩进'));
      await tester.pumpAndSettle();
      expect(current.firstLineIndentChars, equals(2.0));

      // 切换分栏模式到双栏
      await tester.ensureVisible(find.text('双栏'));
      await tester.tap(find.text('双栏'));
      await tester.pumpAndSettle();
      expect(current.columnMode, equals(ReaderColumnMode.doubleColumn));

      // 点击恢复默认
      await tester.ensureVisible(find.text('恢复默认排版'));
      await tester.tap(find.text('恢复默认排版'));
      await tester.pumpAndSettle();
      expect(current.currentPreset, equals(ReaderTypographyPreset.standard));
      expect(current.firstLineIndentChars, equals(0.0));
      expect(current.columnMode, equals(ReaderColumnMode.auto));
    });

    testWidgets(
        'SwitchListTiles have transparent tileColor even under dark theme with custom listTileTheme',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ReaderTypography current = const ReaderTypography();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          listTileTheme: ListTileThemeData(
            tileColor: const Color(0xFF1E2025),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: Scaffold(
          body: ReaderTypographySheet(
            initialTypography: current,
            fontSize: 17.0,
            textColor: const Color(0xFFFFFFFF),
            backgroundColor: const Color(0xFF1E2025),
            linkColor: const Color(0xFF5C6BC0),
            isDark: true,
            onPreviewChange: (t) => current = t,
            onCommit: (t) => current = t,
          ),
        ),
      ));

      // 展开「更多排版设置」
      await tester.ensureVisible(find.text('更多排版设置'));
      await tester.tap(find.text('更多排版设置'));
      await tester.pumpAndSettle();

      final switchTiles =
          tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
      expect(switchTiles.length, greaterThanOrEqualTo(3));
      for (final tile in switchTiles) {
        expect(tile.tileColor, equals(Colors.transparent));
      }
    });
  });
}
