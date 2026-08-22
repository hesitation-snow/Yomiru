import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lk_client.dart';
import 'models.dart';

/// 会话与主题持久化
class LKStore {
  /// 主题模式(ValueNotifier 让 MaterialApp 即时切换)
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    var securityKey = '';
    var secureStorageReady = false;
    try {
      securityKey = await _secure.read(key: 'security_key') ?? '';
      // 一次性迁移旧版本写入 SharedPreferences 的会话凭据。
      if (securityKey.isEmpty) {
        final legacyKey = p.getString('security_key') ?? '';
        if (legacyKey.isNotEmpty) {
          await _secure.write(key: 'security_key', value: legacyKey);
          securityKey = legacyKey;
        }
      }
      secureStorageReady = true;
    } catch (_) {
      // Keychain/Keystore 不可用时不回退读取明文偏好，避免重新暴露凭据。
    }
    if (secureStorageReady) await p.remove('security_key');
    LKClient.shared.session
      ..securityKey = securityKey
      ..uid = p.getInt('uid') ?? 0
      ..nickname = p.getString('nickname') ?? ''
      ..avatar = p.getString('avatar') ?? '';
    themeMode.value = _parseTheme(p.getString('theme_mode'));
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    final s = LKClient.shared.session;
    if (s.securityKey.isEmpty) {
      await _secure.delete(key: 'security_key');
    } else {
      await _secure.write(key: 'security_key', value: s.securityKey);
    }
    // 清理旧版本可能留下的明文副本。
    await p.remove('security_key');
    await p.setInt('uid', s.uid);
    await p.setString('nickname', s.nickname);
    await p.setString('avatar', s.avatar);
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', mode.name);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    final oldUid = LKClient.shared.session.uid;
    await _secure.delete(key: 'security_key');
    await p.remove('security_key');
    await p.remove('uid');
    await p.remove('nickname');
    await p.remove('avatar');
    if (oldUid > 0) {
      await p.remove(_profileCacheKey(oldUid));
      await p.remove(_medalCacheKey(oldUid));
    }
    LKClient.shared.session.clear();
    LKClient.sessionRev.value++;
  }

  static String _medalCacheKey(int uid) => 'my_medals_cache_$uid';
  static String _profileCacheKey(int uid) => 'my_profile_cache_$uid';
  static const _globalMedalsKey = 'global_user_medals_cache_v1';
  static const _localShelfKey = 'local_shelf_books_v1';
  static final ValueNotifier<int> localShelfRev = ValueNotifier<int>(0);

  /// 未登录时使用的本地书架,只保存公开的书籍展示字段。
  static Future<List<LKBook>> localShelf() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_localShelfKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => LKBook.fromJson(Map<String, dynamic>.from(e)))
          .where((book) => book.bookId > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> isLocalShelf(int bookId) async {
    if (bookId <= 0) return false;
    final books = await localShelf();
    return books.any((book) => book.bookId == bookId);
  }

  static Future<void> setLocalShelf(LKBook book, bool added) async {
    if (book.bookId <= 0) return;
    // localShelf() 在空数据时可能返回 const [],这里必须复制为可变列表。
    final books = (await localShelf()).toList();
    books.removeWhere((item) => item.bookId == book.bookId);
    if (added) books.insert(0, book);
    await (await SharedPreferences.getInstance()).setString(
        _localShelfKey, jsonEncode(books.map((e) => e.toJson()).toList()));
    localShelfRev.value++;
  }

  /// 读取当前账号上次成功获取的个人资料；null 表示尚未缓存或缓存已损坏。
  static Future<LKMyProfile?> cachedMyProfile(int uid) async {
    if (uid <= 0) return null;
    final raw = (await SharedPreferences.getInstance())
        .getString(_profileCacheKey(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = LKMyProfile.fromJson(Map<String, dynamic>.from(decoded));
      return profile.uid == uid ? profile : null;
    } catch (_) {
      return null;
    }
  }

  /// 缓存资料展示所需字段，不包含 security_key、cookie 等会话凭据。
  static Future<void> cacheMyProfile(int uid, LKMyProfile profile) async {
    if (uid <= 0 || profile.uid != uid) return;
    final data = <String, dynamic>{
      'uid': profile.uid,
      'nickname': profile.nickname,
      'avatar': profile.avatar,
      'signature': profile.signature,
      'level_name': profile.levelName,
      'level': profile.level,
      'coin': profile.coin,
      'isBrave': profile.isBrave,
      'followers': profile.followersCount,
      'following': profile.followingCount,
      'post_count': profile.postCount,
      'bookshelf_count': profile.bookshelfCount,
      'history_count': profile.historyCount,
      'medals': profile.medals
          .take(5)
          .map((medal) => {
                'medal_id': medal.medalId,
                'name': medal.name,
                'image': medal.image,
                'equipped': medal.equipped,
              })
          .toList(),
    };
    await (await SharedPreferences.getInstance())
        .setString(_profileCacheKey(uid), jsonEncode(data));
  }

  /// 读取当前账号上次成功获取的勋章列表；null 表示尚未缓存。
  static Future<List<LKMedal>?> cachedMedals(int uid) async {
    if (uid <= 0) return null;
    final raw =
        (await SharedPreferences.getInstance()).getString(_medalCacheKey(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheMedals(int uid, List<LKMedal> medals) async {
    if (uid <= 0) return;
    final data = medals
        .map((medal) => {
              'medal_id': medal.medalId,
              'name': medal.name,
              'image': medal.image,
              'equipped': medal.equipped,
            })
        .toList();
    await (await SharedPreferences.getInstance())
        .setString(_medalCacheKey(uid), jsonEncode(data));
    await cacheGlobalMedals({uid: medals});
  }

  /// 读取所有动态/公开资料共用的用户勋章缓存，避免每个页面重复请求。
  static Future<Map<int, List<LKMedal>>> cachedGlobalMedals() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_globalMedalsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <int, List<LKMedal>>{};
      for (final entry in decoded.entries) {
        final uid = int.tryParse(entry.key.toString());
        final list = entry.value;
        if (uid == null || uid <= 0 || list is! List) continue;
        final medals = list
            .whereType<Map>()
            .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.image.isNotEmpty)
            .take(5)
            .toList();
        if (medals.isNotEmpty) result[uid] = medals;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> cacheGlobalMedals(
      Map<int, List<LKMedal>> incoming) async {
    final updates = incoming.entries
        .where((entry) => entry.key > 0 && entry.value.isNotEmpty)
        .toList();
    if (updates.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = <String, dynamic>{};
      final raw = prefs.getString(_globalMedalsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          merged.addAll(Map<String, dynamic>.from(decoded));
        }
      }
      for (final entry in updates) {
        merged['${entry.key}'] = entry.value
            .take(5)
            .map((medal) => {
                  'medal_id': medal.medalId,
                  'name': medal.name,
                  'image': medal.image,
                  'equipped': medal.equipped,
                })
            .toList();
      }
      // 控制 SharedPreferences 体积，只保留最近一次合并中的最多 500 个用户。
      final keys = merged.keys.toList();
      if (keys.length > 500) {
        for (final key in keys.take(keys.length - 500)) {
          merged.remove(key);
        }
      }
      await prefs.setString(_globalMedalsKey, jsonEncode(merged));
    } catch (_) {
      // 缓存失败不影响动态内容显示。
    }
  }

  static ThemeMode _parseTheme(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// 阅读器偏好(持久化)
class ReaderPrefs {
  static Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  static Future<double> fontSize() async =>
      (await _p()).getDouble('r_font') ?? 17;
  static Future<void> setFontSize(double v) async =>
      (await _p()).setDouble('r_font', v);

  static Future<double> lineHeight() async =>
      (await _p()).getDouble('r_lh') ?? 1.7;
  static Future<void> setLineHeight(double v) async =>
      (await _p()).setDouble('r_lh', v);

  static Future<int> bgPreset() async => (await _p()).getInt('r_bg') ?? -1;
  static Future<void> setBgPreset(int v) async =>
      (await _p()).setInt('r_bg', v);

  static Future<bool> bgFollowSystem() async =>
      (await _p()).getBool('r_bg_sys') ?? false;
  static Future<void> setBgFollowSystem(bool v) async =>
      (await _p()).setBool('r_bg_sys', v);

  static Future<bool> keepScreenOn() async =>
      (await _p()).getBool('r_keep_on') ?? false;
  static Future<void> setKeepScreenOn(bool v) async =>
      (await _p()).setBool('r_keep_on', v);

  static Future<bool> hideStatusBar() async =>
      (await _p()).getBool('r_hide_bar') ?? false;
  static Future<void> setHideStatusBar(bool v) async =>
      (await _p()).setBool('r_hide_bar', v);

  static Future<bool> tapTurnPage() async =>
      (await _p()).getBool('r_tap_turn') ?? false;
  static Future<void> setTapTurnPage(bool v) async =>
      (await _p()).setBool('r_tap_turn', v);

  static Future<bool> volumeTurnPage() async =>
      (await _p()).getBool('r_vol_turn') ?? false;
  static Future<void> setVolumeTurnPage(bool v) async =>
      (await _p()).setBool('r_vol_turn', v);

  static Future<bool> autoMargin() async =>
      (await _p()).getBool('r_auto_margin') ?? true;
  static Future<void> setAutoMargin(bool v) async =>
      (await _p()).setBool('r_auto_margin', v);

  static Future<double> marginTop() async =>
      (await _p()).getDouble('r_mt') ?? 56;
  static Future<void> setMarginTop(double v) async =>
      (await _p()).setDouble('r_mt', v);
  static Future<double> marginBottom() async =>
      (await _p()).getDouble('r_mb') ?? 70;
  static Future<void> setMarginBottom(double v) async =>
      (await _p()).setDouble('r_mb', v);
  static Future<double> marginLeft() async =>
      (await _p()).getDouble('r_ml') ?? 20;
  static Future<void> setMarginLeft(double v) async =>
      (await _p()).setDouble('r_ml', v);
  static Future<double> marginRight() async =>
      (await _p()).getDouble('r_mr') ?? 20;
  static Future<void> setMarginRight(double v) async =>
      (await _p()).setDouble('r_mr', v);

  static Future<bool> showIndicators() async =>
      (await _p()).getBool('r_ind') ?? true;
  static Future<void> setShowIndicators(bool v) async =>
      (await _p()).setBool('r_ind', v);

  static Future<bool> traditional() async =>
      (await _p()).getBool('r_trad') ?? false;
  static Future<void> setTraditional(bool v) async =>
      (await _p()).setBool('r_trad', v);

  static Future<bool> simplified() async =>
      (await _p()).getBool('r_simp') ?? false;
  static Future<void> setSimplified(bool v) async =>
      (await _p()).setBool('r_simp', v);

  static Future<bool> pagedMode() async =>
      (await _p()).getBool('r_paged') ?? false;
  static Future<void> setPagedMode(bool v) async =>
      (await _p()).setBool('r_paged', v);

  static Future<bool> feedListMode() async =>
      (await _p()).getBool('feed_list') ?? false;
  static Future<void> setFeedListMode(bool v) async =>
      (await _p()).setBool('feed_list', v);

  /// 章节阅读位置(0~1 进度),用于重新打开时自动跳转到上次阅读处
  static Future<double> readPosFrac(int chapterId) async =>
      (await _p()).getDouble('r_pos_$chapterId') ?? 0;
  static Future<void> setReadPosFrac(int chapterId, double frac) async =>
      (await _p()).setDouble('r_pos_$chapterId', frac.clamp(0.0, 1.0));
}
