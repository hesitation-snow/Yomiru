import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 当前设备的正文缓存。
///
/// 缓存存放在应用私有目录，仅保存已经成功取得阅读权限的章节正文。
/// 它不是安全存储，也不保存 security_key、cookie 或其他会话凭据。
class ReaderContentCache {
  static const _directoryName = 'reader_content_cache';
  static const _maxEntries = 50;

  static Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final dir =
        Directory('${root.path}${Platform.pathSeparator}$_directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static File _file(Directory dir, int chapterId) =>
      File('${dir.path}${Platform.pathSeparator}chapter_$chapterId.json');

  /// 读取缓存。缓存损坏、章节不匹配或当前缓存的是未解锁试读内容时直接忽略。
  static Future<LKChapterDetail?> read(int bookId, int chapterId) async {
    try {
      final file = _file(await _directory(), chapterId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['book_id'] != bookId) {
        return null;
      }
      final raw = decoded['detail'];
      if (raw is! Map<String, dynamic>) return null;
      final detail = LKChapterDetail.fromCacheJson(raw);
      if (detail.chapterId != chapterId ||
          (detail.locked && !detail.unlocked)) {
        return null;
      }
      // 访问时更新时间,让清理策略保留最近阅读的正文。
      await file.setLastModified(DateTime.now());
      return detail;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> contains(int bookId, int chapterId) async =>
      await read(bookId, chapterId) != null;

  /// 只缓存公开内容或已经解锁的付费章节,避免把未授权试读内容持久化。
  static Future<void> write(int bookId, LKChapterDetail detail) async {
    if (bookId <= 0 || detail.chapterId <= 0) return;
    try {
      final file = _file(await _directory(), detail.chapterId);
      if (detail.locked && !detail.unlocked) {
        if (await file.exists()) await file.delete();
        return;
      }
      // 空响应可能只是服务端暂时没有返回正文,不覆盖已有有效缓存。
      if (detail.bodyText.isEmpty &&
          (detail.bodyHtml == null || detail.bodyHtml!.isEmpty)) {
        return;
      }
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'book_id': bookId,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'detail': detail.toCacheJson(),
        }),
        flush: true,
      );
      await _prune(file.parent);
    } catch (_) {
      // 缓存失败不应影响正常在线阅读。
    }
  }

  static Future<int> count() async {
    try {
      final dir = await _directory();
      return (await dir
              .list()
              .where((e) => e is File && e.path.endsWith('.json'))
              .toList())
          .length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clear() async {
    try {
      final root = await getApplicationSupportDirectory();
      final dir =
          Directory('${root.path}${Platform.pathSeparator}$_directoryName');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响其他设置和阅读功能。
    }
  }

  static Future<void> _prune(Directory dir) async {
    final files = (await dir
            .list()
            .where((e) => e is File && e.path.endsWith('.json'))
            .toList())
        .whereType<File>()
        .toList();
    if (files.length <= _maxEntries) return;
    final entries = <(File, DateTime)>[];
    for (final file in files) {
      try {
        entries.add((file, await file.lastModified()));
      } catch (_) {}
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    for (final entry in entries.take(entries.length - _maxEntries)) {
      try {
        await entry.$1.delete();
      } catch (_) {}
    }
  }
}
