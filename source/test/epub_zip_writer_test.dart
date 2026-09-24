import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/services/epub/epub_zip_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_zip_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('EpubZipWriter generates 100% compliant EPUB 3 container format', () async {
    final targetFile = File('${tempDir.path}/test_book.epub');
    final writer = await EpubZipWriter.open(targetFile);

    // 添加 META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    await writer.addBytes('META-INF/container.xml', utf8.encode(containerXml));

    // 添加章节文件
    const sampleXhtml = '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><body><p>Hello EPUB 3</p></body></html>';
    await writer.addBytes('EPUB/text/ch_0001.xhtml', utf8.encode(sampleXhtml));

    // 添加磁盘文件
    final dummyImgFile = File('${tempDir.path}/dummy.jpg');
    await dummyImgFile.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    await writer.addFile('EPUB/images/dummy.jpg', dummyImgFile, compress: false);

    await writer.close();

    expect(await targetFile.exists(), isTrue);
    final bytes = await targetFile.readAsBytes();
    expect(bytes.length, greaterThan(100));

    // 1. 验证 ZIP 文件的前 4 个字节必须为 Local File Header 签名 0x04034b50 (PK\x03\x04)
    expect(bytes[0], 0x50); // P
    expect(bytes[1], 0x4B); // K
    expect(bytes[2], 0x03);
    expect(bytes[3], 0x04);

    final byteData = ByteData.sublistView(bytes);

    // 2. 验证首个 entry 的各项约束（EPUB 3.3 规范核心）
    final method = byteData.getUint16(8, Endian.little);
    final compressedSize = byteData.getUint32(18, Endian.little);
    final uncompressedSize = byteData.getUint32(22, Endian.little);
    final nameLen = byteData.getUint16(26, Endian.little);
    final extraLen = byteData.getUint16(28, Endian.little);

    expect(method, equals(0), reason: 'mimetype must NOT be compressed (STORED = 0)');
    expect(extraLen, equals(0), reason: 'mimetype extra field length MUST be 0');
    expect(nameLen, equals(8), reason: 'name is "mimetype" (8 bytes)');

    final nameString = ascii.decode(bytes.sublist(30, 30 + nameLen));
    expect(nameString, equals('mimetype'));

    final payloadStart = 30 + nameLen;
    final payloadString = ascii.decode(bytes.sublist(payloadStart, payloadStart + uncompressedSize));
    expect(payloadString, equals('application/epub+zip'));
    expect(compressedSize, equals(20));
    expect(uncompressedSize, equals(20));

    // 3. 验证 CRC-32 校验码
    final computedCrc = Crc32.compute(ascii.encode('application/epub+zip'));
    final headerCrc = byteData.getUint32(14, Endian.little);
    expect(headerCrc, equals(computedCrc));

    // 4. 验证 End of Central Directory (EOCD)
    // 倒数 22 字节应为 EOCD 签名 0x06054b50
    final eocdOffset = bytes.length - 22;
    expect(byteData.getUint32(eocdOffset, Endian.little), equals(0x06054b50));
    final totalEntries = byteData.getUint16(eocdOffset + 10, Endian.little);
    expect(totalEntries, equals(4)); // mimetype, container.xml, ch_0001.xhtml, dummy.jpg
  });
}
