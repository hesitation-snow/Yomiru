import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/reader/structured_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_open_chinese_convert'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'convert') {
        final args = methodCall.arguments;
        final text = args is List ? args[0] as String : (args as Map)['text'] as String;
        return text
            .replaceAll('这里', '這裡')
            .replaceAll('简体', '簡體')
            .replaceAll('链接', '連結')
            .replaceAll('汉字', '漢字')
            .replaceAll('注音', '註音');
      }
      return null;
    },
  );

  group('StructuredContentParser HTML parsing', () {
    test('parses basic formatting (b, i, u, s, font color)', () {
      const html =
          '<p>Hello <b>bold</b> <i>italic</i> <u>underline</u> <s>strike</s> '
          '<font color="#ff0000">red text</font></p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      final b = blocks.first;
      expect(b.type, StructuredBlockType.paragraph);
      expect(b.text,
          'Hello bold italic underline strike red text');

      final boldRun = b.runs.firstWhere((r) => r.text == 'bold');
      expect(boldRun.isBold, isTrue);
      expect(boldRun.isItalic, isFalse);

      final italicRun = b.runs.firstWhere((r) => r.text == 'italic');
      expect(italicRun.isItalic, isTrue);

      final underlineRun = b.runs.firstWhere((r) => r.text == 'underline');
      expect(underlineRun.isUnderline, isTrue);

      final strikeRun = b.runs.firstWhere((r) => r.text == 'strike');
      expect(strikeRun.isStrikethrough, isTrue);

      final redRun = b.runs.firstWhere((r) => r.text == 'red text');
      expect(redRun.color, const Color(0xFFFF0000));
    });

    test('parses headings (h1..h6)', () {
      const html = '<h1>Title 1</h1><h2>Title 2</h2><p>Normal text</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 3);
      expect(blocks[0].type, StructuredBlockType.heading);
      expect(blocks[0].headingLevel, 1);
      expect(blocks[0].text, 'Title 1');

      expect(blocks[1].type, StructuredBlockType.heading);
      expect(blocks[1].headingLevel, 2);
      expect(blocks[1].text, 'Title 2');

      expect(blocks[2].type, StructuredBlockType.paragraph);
      expect(blocks[2].text, 'Normal text');
    });

    test('parses blockquote and alignment', () {
      const html =
          '<blockquote style="text-align: center;"><p>Quote content</p></blockquote>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      final b = blocks.first;
      expect(b.type, StructuredBlockType.blockquote);
      expect(b.isBlockquote, isTrue);
      expect(b.align, TextAlign.center);
      expect(b.indent, greaterThan(0));
      expect(b.text, 'Quote content');
    });

    test('parses horizontal divider <hr>', () {
      const html = '<p>Before</p><hr><p>After</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 3);
      expect(blocks[0].text, 'Before');
      expect(blocks[1].isDivider, isTrue);
      expect(blocks[2].text, 'After');
    });

    test('parses images with aspect ratio', () {
      const html =
          '<p>Intro</p><img src="https://example.com/image1.jpg" width="400" height="800"><p>Outro</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 3);
      expect(blocks[0].text, 'Intro');
      expect(blocks[1].isImage, isTrue);
      expect(blocks[1].imageUrl, 'https://example.com/image1.jpg');
      expect(blocks[1].imageAspect, closeTo(0.5, 0.001));
      expect(blocks[2].text, 'Outro');
    });

    test('parses ruby tags into annotated run', () {
      const html = '<p>主角是<ruby>勇者<rt>ゆうしゃ</rt></ruby>。</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      final b = blocks.first;
      expect(b.text, '主角是勇者(ゆうしゃ)。');
      final rubyRun = b.runs.firstWhere((r) => r.rubyText != null);
      expect(rubyRun.rubyText, 'ゆうしゃ');
      expect(rubyRun.rubyBaseText, '勇者');
      expect(rubyRun.text, '勇者(ゆうしゃ)');
      final annotations = b.rubyAnnotations(
        baseStyle: const TextStyle(fontSize: 18, height: 1.7),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
      );
      expect(annotations, hasLength(1));
      expect(annotations.single.start, 3);
      expect(annotations.single.end, 5);
      expect(annotations.single.text, 'ゆうしゃ');
      expect(annotations.single.style.fontSize, closeTo(18 * 0.58, 0.01));
    });

    test('ruby remains readable and reserves space with tight line spacing',
        () {
      const html = '<p>上一行<ruby>漢字<rt>かんじ</rt></ruby>下一行</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      const tightStyle = TextStyle(fontSize: 18, height: 0.9);
      final span = block.buildTextSpan(
        baseStyle: tightStyle,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        forMeasurement: true,
      );
      final rubyBase = span.children!
          .whereType<TextSpan>()
          .firstWhere((child) => child.text == '漢字');

      expect(rubyBase.style?.height, greaterThanOrEqualTo(2.30));
      expect(
        block
            .rubyAnnotations(
              baseStyle: tightStyle,
              linkColor: Colors.blue,
              backgroundColor: Colors.white,
            )
            .single
            .style
            .fontSize,
        closeTo(18 * 0.58, 0.01),
      );
    });

    test('parses hyperlinks correctly', () {
      const html = '<p>点击 <a href="https://example.com/item">这里</a> 查看</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      final b = blocks.first;
      expect(b.text, '点击 这里 查看');
      final links = b.extractLinks();
      expect(links.length, 1);
      expect(links.first.$3, 'https://example.com/item');
      expect(b.text.substring(links.first.$1, links.first.$2), '这里');
    });

    test('ignores script, style, and strips [res] tags', () {
      const html =
          '<script>alert("xss")</script><style>.bad{color:red}</style><p>[res]0,12345[/res]Safe text</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      expect(blocks.first.text, 'Safe text');
    });
  });

  group('StructuredBlock slicing and TextSpan building', () {
    test('ruby rendering keeps the original text offsets and copy text', () {
      const html = '<p>主角是<ruby>勇者<rt>ゆうしゃ</rt></ruby>。</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      final span = block.buildTextSpan(
        baseStyle: const TextStyle(fontSize: 18, height: 1.7),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        forMeasurement: true,
      );

      expect(span.toPlainText(), block.text);
      expect(span.toPlainText(), '主角是勇者(ゆうしゃ)。');

      final partialSlice = block.slice(0, 5);
      expect(
        partialSlice.rubyAnnotations(
          baseStyle: const TextStyle(fontSize: 18, height: 1.7),
          linkColor: Colors.blue,
          backgroundColor: Colors.white,
        ),
        isEmpty,
      );
      expect(
        partialSlice
            .buildTextSpan(
              baseStyle: const TextStyle(fontSize: 18, height: 1.7),
              linkColor: Colors.blue,
              backgroundColor: Colors.white,
              forMeasurement: true,
            )
            .toPlainText(),
        partialSlice.text,
      );
    });

    testWidgets('ruby annotation paints above the base text', (tester) async {
      const html = '<p>主角是<ruby>勇者<rt>ゆうしゃ</rt></ruby>。</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      const style = TextStyle(fontSize: 18, height: 1.7);
      final span = block.buildTextSpan(
        baseStyle: style,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StructuredRubyText(
              block: block,
              span: span,
              baseStyle: style,
              linkColor: Colors.blue,
              backgroundColor: Colors.white,
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.noScaling,
              locale: const Locale('zh', 'CN'),
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ));

      final text = tester.widget<RichText>(find.byType(RichText));
      expect(text.text.toPlainText(), block.text);
      expect(find.byType(StructuredRubyText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('superscript and subscript annotations paint without errors',
        (tester) async {
      const html = '<p>H<sup>2</sup>O 与 H<sub>2</sub>O</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      const style = TextStyle(fontSize: 20, height: 1.5, color: Colors.black);
      final span = block.buildTextSpan(
        baseStyle: style,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: StructuredRubyText(
              block: block,
              span: span,
              baseStyle: style,
              linkColor: Colors.blue,
              backgroundColor: Colors.white,
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.noScaling,
              locale: const Locale('zh', 'CN'),
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ));

      expect(span.toPlainText(), 'H2O 与 H2O');
      expect(block.verticalAnnotations(
        baseStyle: style,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
      ), hasLength(2));
      expect(tester.takeException(), isNull);
    });

    test('slice preserves run styles and character boundaries', () {
      const block = StructuredBlock(
        type: StructuredBlockType.paragraph,
        text: 'ABCDEFGHIJ',
        runs: [
          StructuredInlineRun(text: 'ABC', isBold: true),
          StructuredInlineRun(text: 'DEF', isItalic: true),
          StructuredInlineRun(text: 'GHIJ', isUnderline: true),
        ],
      );

      // Slice 'CDE' (index 2 to 5)
      final slice1 = block.slice(2, 5);
      expect(slice1.text, 'CDE');
      expect(slice1.runs.length, 2);
      expect(slice1.runs[0].text, 'C');
      expect(slice1.runs[0].isBold, isTrue);
      expect(slice1.runs[1].text, 'DE');
      expect(slice1.runs[1].isItalic, isTrue);

      // Slice 'FG' (index 5 to 7)
      final slice2 = block.slice(5, 7);
      expect(slice2.text, 'FG');
      expect(slice2.runs.length, 2);
      expect(slice2.runs[0].text, 'F');
      expect(slice2.runs[0].isItalic, isTrue);
      expect(slice2.runs[1].text, 'G');
      expect(slice2.runs[1].isUnderline, isTrue);
    });

    test('ensureLegibleColor boosts dark color on dark background', () {
      const darkColor = Color(0xFF111111);
      const darkBg = Color(0xFF1A1A1A);
      final adjusted = StructuredBlock.ensureLegibleColor(darkColor, darkBg);
      expect(adjusted.computeLuminance(), greaterThan(0.3));
    });

    test('ensureLegibleColor darkens light color on light background', () {
      const lightColor = Color(0xFFEEEEEE);
      const lightBg = Color(0xFFFFFFFF);
      final adjusted = StructuredBlock.ensureLegibleColor(lightColor, lightBg);
      expect(adjusted.computeLuminance(), lessThan(0.4));
    });

    test('buildTextSpan creates matching spans for measurement and display', () {
      const block = StructuredBlock(
        type: StructuredBlockType.heading,
        headingLevel: 2,
        text: '大标题',
        runs: [
          StructuredInlineRun(text: '大标题', isBold: true),
        ],
      );

      final spanForMeasure = block.buildTextSpan(
        baseStyle: const TextStyle(fontSize: 16),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        forMeasurement: true,
      );

      expect(spanForMeasure.style?.fontSize, closeTo(16 * 1.28, 0.01));
      expect(spanForMeasure.style?.fontWeight, FontWeight.bold);

      final spanForDisplay = block.buildTextSpan(
        baseStyle: const TextStyle(fontSize: 16),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        forMeasurement: false,
      );
      expect(spanForDisplay.style?.fontSize, spanForMeasure.style?.fontSize);
    });

    test('convertBlocks converts only text and ruby without altering structure or URLs', () async {
      const html =
          '<p>这里是<a href="https://example.com/link">简体链接</a>与<ruby>汉字<rt>注音</rt></ruby></p>';
      final blocks = StructuredContentParser.parseHtml(html);
      final converted = await StructuredContentParser.convertBlocks(blocks, 1); // S2T
      expect(converted.length, 1);
      final b = converted.first;
      expect(b.text, contains('這裡是'));
      expect(b.text, contains('簡體連結'));
      expect(b.text, contains('漢字(註音)'));
      // Link URL is intact
      expect(b.runs.firstWhere((r) => r.linkUrl != null).linkUrl,
          'https://example.com/link');
    });

    test('text-indent in paragraph does not cause whole-block indentation', () {
      const html = '''
        <h1>第一章 序幕</h1>
        <p style="text-indent: 2em;">这是第一段正文，换行后不应当整段靠右。</p>
        <blockquote style="text-align: left;"><p>引用文字</p></blockquote>
      ''';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 3);

      // 大标题 indent 为 0
      expect(blocks[0].isHeading, isTrue);
      expect(blocks[0].indent, 0.0);

      // 普通正文 indent 必须为 0，与大标题对齐，且换行后不损失横向空间
      expect(blocks[1].isHeading, isFalse);
      expect(blocks[1].isBlockquote, isFalse);
      expect(blocks[1].indent, 0.0);

      // 引用块合法保留缩进
      expect(blocks[2].isBlockquote, isTrue);
      expect(blocks[2].indent, greaterThan(0));
    });

    test('parses unordered <ul> and ordered <ol> lists with bullet and number prefixes', () {
      const html = '''
        <ul class="ln-list">
          <li>第一项</li>
          <li>第二项</li>
        </ul>
        <ol class="ln-list">
          <li>有序首项</li>
          <li>有序次项</li>
        </ol>
      ''';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 4);

      // 无序列表
      expect(blocks[0].isListItem, isTrue);
      expect(blocks[0].text, '• 第一项');
      expect(blocks[0].indent, 14.0);
      expect(blocks[0].listNumber, isNull);

      expect(blocks[1].isListItem, isTrue);
      expect(blocks[1].text, '• 第二项');
      expect(blocks[1].indent, 14.0);

      // 有序列表
      expect(blocks[2].isListItem, isTrue);
      expect(blocks[2].text, '1. 有序首项');
      expect(blocks[2].indent, 14.0);
      expect(blocks[2].listNumber, 1);

      expect(blocks[3].isListItem, isTrue);
      expect(blocks[3].text, '2. 有序次项');
      expect(blocks[3].indent, 14.0);
      expect(blocks[3].listNumber, 2);
    });

    test('parses superscript <sup> with 0.75 multiplier and footnote marker', () {
      const html = '<p>正文123<sup class="ln-footnote-ref">[1]</sup>456</p>';
      final blocks = StructuredContentParser.parseHtml(html);
      expect(blocks.length, 1);
      final b = blocks.first;
      expect(b.text, '正文123[1]456');

      final supRun = b.runs.firstWhere((r) => r.text == '[1]');
      expect(supRun.fontSizeMultiplier, 0.75);
      expect(supRun.isFootnote, isTrue);
      expect(supRun.verticalAlignment, StructuredVerticalAlignment.superscript);
      final annotations = b.verticalAnnotations(
        baseStyle: const TextStyle(fontSize: 18),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
      );
      expect(annotations, hasLength(1));
      expect(annotations.single.start, 5);
      expect(annotations.single.end, 8);
    });

    test('inline CSS font size, weight, and vertical alignment are parsed', () {
      const html = '<p><span style="font-size: 20px; font-weight: 500">中</span>'
          '<span style="font-size: 120%; font-weight: 600">A</span>'
          '<span style="vertical-align: sub">2</span></p>';
      final block = StructuredContentParser.parseHtml(html).single;
      final medium = block.runs.firstWhere((run) => run.text == '中');
      final semibold = block.runs.firstWhere((run) => run.text == 'A');
      final subscript = block.runs.firstWhere((run) => run.text == '2');

      expect(medium.fontSizeMultiplier, closeTo(1.25, 0.001));
      expect(medium.fontWeight, FontWeight.w500);
      expect(semibold.fontSizeMultiplier, closeTo(1.2, 0.001));
      expect(semibold.fontWeight, FontWeight.w600);
      expect(subscript.verticalAlignment, StructuredVerticalAlignment.subscript);
    });

    test('footnote marker stays copyable and invokes its reference callback', () {
      const html = '<p>正文<sup class="ln-footnote-ref">[1]</sup>后文</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      String? tappedReference;
      final span = block.buildTextSpan(
        baseStyle: const TextStyle(fontSize: 18),
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        onFootnoteTap: (reference) => tappedReference = reference,
      );
      final marker = span.children!.whereType<TextSpan>().firstWhere(
            (child) => child.text == '[1]',
          );

      expect(span.toPlainText(), block.text);
      expect(marker.style?.color, Colors.transparent);
      final recognizer = marker.recognizer! as TapGestureRecognizer;
      recognizer.onTap!.call();
      recognizer.dispose();
      expect(tappedReference, '1');
    });

    testWidgets('footnote is a compact upper-right marker that remains tappable',
        (tester) async {
      const html = '<p>123456<sup class="ln-footnote-ref">[1]</sup>7890</p>';
      final block = StructuredContentParser.parseHtml(html).single;
      const style = TextStyle(
        fontSize: 26,
        height: 1.7,
        letterSpacing: 0.6,
        color: Colors.black,
      );
      const scaler = TextScaler.linear(1.1);
      String? tappedReference;
      var tapCount = 0;
      final span = block.buildTextSpan(
        baseStyle: style,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        onFootnoteTap: (reference) {
          tappedReference = reference;
          tapCount++;
        },
      );
      final marker = span.children!.whereType<TextSpan>().firstWhere(
            (child) => child.text == '[1]',
          );
      final measuredSpan = block.buildTextSpan(
        baseStyle: style,
        linkColor: Colors.blue,
        backgroundColor: Colors.white,
        forMeasurement: true,
      );
      final measuredMarker =
          measuredSpan.children!.whereType<TextSpan>().firstWhere(
                (child) => child.text == '[1]',
              );
      expect(marker.style?.letterSpacing, 0);
      expect(marker.style?.height, 1);
      expect(marker.style?.fontSize, measuredMarker.style?.fontSize);
      expect(span.toPlainText(), block.text);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 320,
              child: SelectionArea(
                child: StructuredRubyText(
                  block: block,
                  span: span,
                  baseStyle: style,
                  linkColor: Colors.blue,
                  backgroundColor: Colors.white,
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                  locale: const Locale('zh', 'CN'),
                  textAlign: TextAlign.start,
                  onFootnoteTap: (reference) {
                    tappedReference = reference;
                    tapCount++;
                  },
                ),
              ),
            ),
          ),
        ),
      ));

      final paragraph = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        locale: const Locale('zh', 'CN'),
        textWidthBasis: TextWidthBasis.parent,
      )..layout(maxWidth: 320);
      final previousBox = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 5, extentOffset: 6),
          )
          .single;
      final markerBox = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 6, extentOffset: 9),
          )
          .single;
      final nextBox = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 9, extentOffset: 10),
          )
          .single;
      expect(markerBox.left, closeTo(previousBox.right, 2));
      expect(nextBox.left, closeTo(markerBox.right, 2));

      final noteStyle = block
          .verticalAnnotations(
            baseStyle: style,
            linkColor: Colors.blue,
            backgroundColor: Colors.white,
          )
          .single
          .style;
      final notePainter = TextPainter(
        text: TextSpan(text: '[1]', style: noteStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      expect(noteStyle.decoration, TextDecoration.none);
      expect(
          markerBox.right - markerBox.left, closeTo(notePainter.width, 0.01));
      expect(
          nextBox.left - previousBox.right, lessThan(notePainter.width * 1.1));
      final hitArea = find.descendant(
        of: find.byType(StructuredRubyText),
        matching: find.byType(GestureDetector),
      );
      expect(hitArea, findsOneWidget);
      final positioned = tester.widget<Positioned>(find.ancestor(
        of: hitArea,
        matching: find.byType(Positioned),
      ));
      expect(positioned.left!, lessThan(previousBox.right));
      expect(positioned.top!, lessThan(previousBox.top));
      expect(positioned.left! + 4, closeTo(markerBox.left, 0.01));
      expect(positioned.left! + 4 + notePainter.width,
          closeTo(nextBox.left, 0.01));
      await tester.tap(hitArea);
      await tester.pump();
      expect(tappedReference, '1');
      expect(tapCount, 1);
      expect(tester.takeException(), isNull);
      notePainter.dispose();
      paragraph.dispose();
    });

    for (final bold in [false, true]) {
      for (final scale in [1.0, 1.6]) {
        for (final reference in ['1', '12']) {
          testWidgets(
              'footnote real layout: bold=$bold scale=$scale ref=$reference',
              (tester) async {
            final block = StructuredContentParser.parseHtml(
              '<p>123456<sup class="ln-footnote-ref">[$reference]</sup>7890</p>',
            ).single;
            final scaler = TextScaler.linear(scale);
            const textKey = ValueKey('footnote-paragraph');
            late TextStyle effectiveStyle;
            String? tapped;

            for (final (width, height) in [
              (480.0, 1.7), (200.0, 1.7), (480.0, 1.0), (200.0, 1.0),
            ]) {
              final style = TextStyle(fontSize: 26, height: height);
              await tester.pumpWidget(MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(boldText: bold, textScaler: scaler),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontFamily: 'Ahem',
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: SelectionArea(
                          child: Builder(builder: (context) {
                            effectiveStyle =
                                resolveStructuredTextStyle(context, style);
                            return StructuredRubyText(
                              textKey: textKey,
                              block: block,
                              // Deliberately leave inherited font properties
                              // unresolved here, as Text.rich used to do.
                              span: block.buildTextSpan(
                                baseStyle: style,
                                linkColor: Colors.blue,
                                backgroundColor: Colors.white,
                              ),
                              baseStyle: style,
                              linkColor: Colors.blue,
                              backgroundColor: Colors.white,
                              textDirection: TextDirection.ltr,
                              textScaler: scaler,
                              locale: const Locale('en'),
                              textAlign: TextAlign.start,
                              onFootnoteTap: (value) => tapped = value,
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ));
              final render = tester.renderObject<RenderParagraph>(
                find.byKey(textKey),
              );
              expect(render.text.toPlainText(), block.text);
              expect(render.text.style!.fontWeight,
                  bold ? FontWeight.bold : FontWeight.w500);
              expect(render.text.style!.fontFamily, 'Ahem');
              expect(render.registrar, isNotNull);

              final measured = TextPainter(
                text: block.buildTextSpan(
                  baseStyle: effectiveStyle,
                  linkColor: Colors.blue,
                  backgroundColor: Colors.white,
                  forMeasurement: true,
                ),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                locale: const Locale('en'),
              )..layout(maxWidth: width);
              expect(render.size.height, closeTo(measured.height, 0.01));
              final end = 6 + reference.length + 2;
              final selection = TextSelection(baseOffset: 6, extentOffset: end);
              final boxes = render.getBoxesForSelection(selection);
              final measuredBoxes = measured.getBoxesForSelection(selection);
              expect(boxes.map((box) => box.toRect()),
                  measuredBoxes.map((box) => box.toRect()));
              final note = TextPainter(
                text: TextSpan(
                  text: '[$reference]',
                  style: block
                      .verticalAnnotations(
                        baseStyle: effectiveStyle,
                        linkColor: Colors.blue,
                        backgroundColor: Colors.white,
                      )
                      .single
                      .style,
                ),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                locale: const Locale('en'),
              )..layout();
              expect(
                  boxes.fold<double>(
                      0, (sum, box) => sum + box.right - box.left),
                  closeTo(note.width, 0.01));
              final hit = find.descendant(
                of: find.byType(StructuredRubyText),
                matching: find.byType(GestureDetector),
              );
              expect(hit, findsNWidgets(boxes.length));
              for (var i = 0; i < boxes.length; i++) {
                final box = boxes[i];
                final positioned = tester.widget<Positioned>(find.ancestor(
                  of: hit.at(i),
                  matching: find.byType(Positioned),
                ));
                expect(
                    positioned.left,
                    closeTo(
                        (box.left - 4).clamp(0.0, width - positioned.width!),
                        0.01));
                final line = measured.computeLineMetrics().firstWhere((line) =>
                    (box.top + box.bottom) / 2 >= line.baseline - line.ascent &&
                    (box.top + box.bottom) / 2 <= line.baseline + line.descent);
                final top = (line.baseline -
                        line.unscaledAscent * 0.5 -
                        note.computeDistanceToActualBaseline(
                            TextBaseline.alphabetic))
                    .clamp(0.0, render.size.height - note.height);
                expect(
                    positioned.top,
                    closeTo(
                        (top - 4).clamp(
                            0.0, render.size.height - positioned.height!),
                        0.01));
                tapped = null;
                await tester.tap(hit.at(i));
                expect(tapped, reference);
              }
              expect(tester.takeException(), isNull);
              note.dispose();
              measured.dispose();
            }
          });
        }
      }
    }

    test(
        'buildTextSpan provides explicit decorationColor and thickness for strikethrough',
        () {
      const block = StructuredBlock(
        type: StructuredBlockType.paragraph,
        text: '1234567890',
        runs: [
          StructuredInlineRun(text: '123'),
          StructuredInlineRun(text: '456', isStrikethrough: true),
          StructuredInlineRun(text: '7890'),
        ],
      );

      final span = block.buildTextSpan(
        baseStyle: const TextStyle(fontSize: 16, color: Colors.white),
        linkColor: Colors.blue,
        backgroundColor: Colors.black,
      );

      expect(span.children, isNotNull);
      final strikeSpan = span.children![1] as TextSpan;
      expect(strikeSpan.text, '456');
      expect(strikeSpan.style?.decoration, TextDecoration.lineThrough);
      expect(strikeSpan.style?.decorationColor, Colors.white);
      expect(strikeSpan.style?.decorationThickness, 1.5);
    });

    test('firstLineIndent flag adds two full-width spaces when true and strips when false', () {
      const html = '<p>没有缩进的正文段落。</p><p>　　已有缩进的正文段落。</p><h1>标题不缩进</h1>';
      final indentedBlocks =
          StructuredContentParser.parseHtml(html, firstLineIndent: true);
      expect(indentedBlocks[0].text.startsWith('　　'), isTrue);
      expect(indentedBlocks[1].text.startsWith('　　'), isTrue);
      expect(indentedBlocks[1].text.startsWith('　　　　'), isFalse);
      expect(indentedBlocks[2].isHeading, isTrue);
      expect(indentedBlocks[2].text.startsWith('　'), isFalse);

      final unindentedBlocks =
          StructuredContentParser.parseHtml(html, firstLineIndent: false);
      expect(unindentedBlocks[0].text.startsWith('没有缩进'), isTrue);
      expect(unindentedBlocks[1].text.startsWith('已有缩进'), isTrue);
    });
  });
}
