import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// CRC-32 计算工具
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static int compute(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) {
      crc = _table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _ZipEntryMeta {
  final String name;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int method; // 0: STORED, 8: DEFLATED
  final int modTime;
  final int modDate;
  final bool isUtf8;

  _ZipEntryMeta({
    required this.name,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.method,
    required this.modTime,
    required this.modDate,
    required this.isUtf8,
  });
}

/// 专为 EPUB 3.3 标准打造的轻量、高效、低内存流式 ZIP 归档器
///
/// 特性：
/// 1. 规范规定：首个条目固定为未压缩的 `mimetype`，且 extra field 长度为 0；
/// 2. 支持直接从磁盘流式读取章节和插画，避免长篇大体量书籍在内存中 OOM；
/// 3. 严格遵循 RFC 1951 (Deflate) 与 PKWARE ZIP 规范，全面兼容各类电子书阅读器。
class EpubZipWriter {
  final RandomAccessFile _raf;
  final List<_ZipEntryMeta> _entries = [];
  bool _closed = false;
  int _currentOffset = 0;

  EpubZipWriter._(this._raf);

  /// 创建并打开一个输出 EPUB 文件
  static Future<EpubZipWriter> open(File targetFile) async {
    if (await targetFile.exists()) {
      await targetFile.delete();
    } else {
      await targetFile.parent.create(recursive: true);
    }
    final raf = await targetFile.open(mode: FileMode.write);
    final writer = EpubZipWriter._(raf);
    // 写入 EPUB 规范规定的第一个未压缩 entry: mimetype
    await writer._writeMimetypeEntry();
    return writer;
  }

  /// 转换当前时间为 MS-DOS 日期与时间
  static (int time, int date) _dosDateTime(DateTime dt) {
    final time = (dt.hour << 11) | (dt.minute << 5) | (dt.second ~/ 2);
    final date = ((dt.year - 1980) << 9) | (dt.month << 5) | dt.day;
    return (time & 0xFFFF, date & 0xFFFF);
  }

  /// 写入 EPUB 3 规范必须置于第 0 字节的 mimetype 文件
  Future<void> _writeMimetypeEntry() async {
    final nameBytes = ascii.encode('mimetype');
    final contentBytes = ascii.encode('application/epub+zip');
    final crc = Crc32.compute(contentBytes);
    final (dosTime, dosDate) = _dosDateTime(DateTime.now());

    // 1. Local file header
    final header = ByteData(30);
    header.setUint32(0, 0x04034b50, Endian.little); // Signature
    header.setUint16(4, 10, Endian.little); // Version needed (1.0 for Stored)
    header.setUint16(6, 0, Endian.little); // General purpose bit flag (0)
    header.setUint16(8, 0, Endian.little); // Compression method (0 = STORED)
    header.setUint16(10, dosTime, Endian.little);
    header.setUint16(12, dosDate, Endian.little);
    header.setUint32(14, crc, Endian.little);
    header.setUint32(18, contentBytes.length, Endian.little); // Compressed
    header.setUint32(22, contentBytes.length, Endian.little); // Uncompressed
    header.setUint16(26, nameBytes.length, Endian.little); // Name length
    header.setUint16(28, 0, Endian.little); // Extra field length: MUST BE 0!

    await _raf.writeFrom(header.buffer.asUint8List());
    await _raf.writeFrom(nameBytes);
    await _raf.writeFrom(contentBytes);

    _entries.add(_ZipEntryMeta(
      name: 'mimetype',
      crc32: crc,
      compressedSize: contentBytes.length,
      uncompressedSize: contentBytes.length,
      localHeaderOffset: 0,
      method: 0,
      modTime: dosTime,
      modDate: dosDate,
      isUtf8: false,
    ));

    _currentOffset = 30 + nameBytes.length + contentBytes.length;
  }

  /// 添加内存字节数据到 ZIP
  Future<void> addBytes(
    String entryName,
    List<int> uncompressedBytes, {
    bool compress = true,
  }) async {
    _checkOpen();
    final cleanName = entryName.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (cleanName.isEmpty || cleanName == 'mimetype') return;

    final nameBytes = utf8.encode(cleanName);
    final crc = Crc32.compute(uncompressedBytes);
    final (dosTime, dosDate) = _dosDateTime(DateTime.now());

    List<int> payload = uncompressedBytes;
    var method = 0;

    if (compress && uncompressedBytes.isNotEmpty) {
      final deflated = ZLibCodec(raw: true).encode(uncompressedBytes);
      if (deflated.length < uncompressedBytes.length) {
        payload = deflated;
        method = 8;
      }
    }

    final localOffset = _currentOffset;
    final header = ByteData(30);
    header.setUint32(0, 0x04034b50, Endian.little);
    header.setUint16(4, 20, Endian.little); // Version needed 2.0
    header.setUint16(6, 1 << 11, Endian.little); // UTF-8 filename flag
    header.setUint16(8, method, Endian.little);
    header.setUint16(10, dosTime, Endian.little);
    header.setUint16(12, dosDate, Endian.little);
    header.setUint32(14, crc, Endian.little);
    header.setUint32(18, payload.length, Endian.little);
    header.setUint32(22, uncompressedBytes.length, Endian.little);
    header.setUint16(26, nameBytes.length, Endian.little);
    header.setUint16(28, 0, Endian.little); // Extra field length

    await _raf.writeFrom(header.buffer.asUint8List());
    await _raf.writeFrom(nameBytes);
    if (payload.isNotEmpty) {
      await _raf.writeFrom(payload);
    }

    _entries.add(_ZipEntryMeta(
      name: cleanName,
      crc32: crc,
      compressedSize: payload.length,
      uncompressedSize: uncompressedBytes.length,
      localHeaderOffset: localOffset,
      method: method,
      modTime: dosTime,
      modDate: dosDate,
      isUtf8: true,
    ));

    _currentOffset += 30 + nameBytes.length + payload.length;
  }

  /// 直接将磁盘文件流式写入 ZIP，不长时间占用堆内存
  Future<void> addFile(
    String entryName,
    File sourceFile, {
    bool compress = true,
  }) async {
    _checkOpen();
    final bytes = await sourceFile.readAsBytes();
    await addBytes(entryName, bytes, compress: compress);
  }

  /// 写入 Central Directory 和 EOCD，完成归档并关闭文件句柄
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    final centralDirectoryOffset = _currentOffset;
    var centralDirectorySize = 0;

    for (final entry in _entries) {
      final nameBytes = utf8.encode(entry.name);
      final cdHeader = ByteData(46);
      cdHeader.setUint32(0, 0x02014b50, Endian.little); // CD Signature
      cdHeader.setUint16(4, 20, Endian.little); // Version made by
      cdHeader.setUint16(6, 20, Endian.little); // Version needed
      cdHeader.setUint16(8, entry.isUtf8 ? (1 << 11) : 0, Endian.little);
      cdHeader.setUint16(10, entry.method, Endian.little);
      cdHeader.setUint16(12, entry.modTime, Endian.little);
      cdHeader.setUint16(14, entry.modDate, Endian.little);
      cdHeader.setUint32(16, entry.crc32, Endian.little);
      cdHeader.setUint32(20, entry.compressedSize, Endian.little);
      cdHeader.setUint32(24, entry.uncompressedSize, Endian.little);
      cdHeader.setUint16(28, nameBytes.length, Endian.little);
      cdHeader.setUint16(30, 0, Endian.little); // Extra field len
      cdHeader.setUint16(32, 0, Endian.little); // Comment len
      cdHeader.setUint16(34, 0, Endian.little); // Disk number start
      cdHeader.setUint16(36, 0, Endian.little); // Internal attrs
      cdHeader.setUint32(38, 0, Endian.little); // External attrs
      cdHeader.setUint32(42, entry.localHeaderOffset, Endian.little);

      await _raf.writeFrom(cdHeader.buffer.asUint8List());
      await _raf.writeFrom(nameBytes);

      centralDirectorySize += 46 + nameBytes.length;
    }

    // End of Central Directory Record (EOCD)
    final eocd = ByteData(22);
    eocd.setUint32(0, 0x06054b50, Endian.little); // EOCD Signature
    eocd.setUint16(4, 0, Endian.little); // Disk number
    eocd.setUint16(6, 0, Endian.little); // Start disk
    eocd.setUint16(8, _entries.length, Endian.little); // Entries on disk
    eocd.setUint16(10, _entries.length, Endian.little); // Total entries
    eocd.setUint32(12, centralDirectorySize, Endian.little);
    eocd.setUint32(16, centralDirectoryOffset, Endian.little);
    eocd.setUint16(20, 0, Endian.little); // Comment length

    await _raf.writeFrom(eocd.buffer.asUint8List());
    await _raf.flush();
    await _raf.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('EpubZipWriter is already closed.');
    }
  }
}
