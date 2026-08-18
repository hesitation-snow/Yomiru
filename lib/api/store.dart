import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lk_client.dart';

/// 会话与主题持久化
class LKStore {
  /// 主题模式(ValueNotifier 让 MaterialApp 即时切换)
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
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
    await _secure.delete(key: 'security_key');
    await p.remove('security_key');
    await p.remove('uid');
    await p.remove('nickname');
    await p.remove('avatar');
    LKClient.shared.session.clear();
    LKClient.sessionRev.value++;
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
