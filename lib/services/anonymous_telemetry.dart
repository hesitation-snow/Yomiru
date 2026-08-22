import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启用时的匿名使用统计。
///
/// 该服务不会读取登录态、账号资料、书籍、阅读内容或网络地址。安装标识是
/// 应用本地随机生成的值，并保存在系统安全存储中；请求失败时静默留待下次
/// 启动重试，绝不影响应用本身的使用。
class AnonymousTelemetry {
  AnonymousTelemetry._();

  static const _endpoint = 'https://telemetry.yutro.uk/v1/install';
  static const _installationIdKey = 'anonymous_telemetry_installation_id_v1';
  static const _reportedKey = 'anonymous_telemetry_reported_v1';
  static const _secure = FlutterSecureStorage();
  static Future<void>? _inFlight;

  static Future<void> reportFirstActivation() {
    return _inFlight ??= _report().whenComplete(() => _inFlight = null);
  }

  static Future<void> _report() async {
    try {
      // Android/iOS 以外的平台不参与移动端安装统计。
      if (!Platform.isAndroid && !Platform.isIOS) return;

      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(_reportedKey) ?? false) return;

      final installationId = await _installationId();
      if (installationId == null) return;

      final package = await PackageInfo.fromPlatform();
      final system = await _systemDetails();
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'installation_id': installationId,
              'app': {
                'version': package.version,
                'build': package.buildNumber,
                'platform': system.platform,
              },
              'system': {
                'os': system.os,
                'architecture': system.architecture,
                'locale': system.locale,
                'model': system.model,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));

      // 无论服务端本次是否为新记录，2xx 都说明它已确认该安装标识；不再重复。
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await preferences.setBool(_reportedKey, true);
      }
    } catch (_) {
      // 统计不可成为启动失败、耗电或打扰用户的原因，后续启动会自然重试。
    }
  }

  static Future<String?> _installationId() async {
    try {
      final existing = await _secure.read(key: _installationIdKey);
      if (existing != null &&
          RegExp(r'^YOM-[A-F0-9]{32}$').hasMatch(existing)) {
        return existing;
      }
      final random = Random.secure();
      final id =
          'YOM-${List<String>.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase()).join()}';
      await _secure.write(key: _installationIdKey, value: id);
      return id;
    } catch (_) {
      // 不在较弱的普通偏好中降级保存稳定标识。
      return null;
    }
  }

  static Future<_SystemDetails> _systemDetails() async {
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    final safeLocale = locale.isEmpty ? 'und' : locale;
    final plugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final release = info.version.release.trim();
      return _SystemDetails(
        platform: 'android',
        os: release.isEmpty ? 'Android' : 'Android $release',
        architecture: _androidArchitecture(info.supportedAbis),
        locale: safeLocale,
        model: _limit(info.model, 80, fallback: 'Unknown'),
      );
    }

    final info = await plugin.iosInfo;
    final machine = _limit(info.utsname.machine, 80, fallback: 'Unknown');
    return _SystemDetails(
      platform: 'ios',
      os: _limit('iOS ${info.systemVersion}', 80, fallback: 'iOS'),
      architecture: _iosArchitecture(machine),
      locale: safeLocale,
      model: machine,
    );
  }

  static String _androidArchitecture(List<String> abis) {
    final all = abis.join(' ').toLowerCase();
    if (all.contains('arm64') || all.contains('aarch64')) return 'ARM64';
    if (all.contains('armeabi') || all.contains(' arm')) return 'ARM';
    if (all.contains('x86_64')) return 'x86_64';
    if (all.contains('x86')) return 'x86';
    return 'Unknown';
  }

  static String _iosArchitecture(String machine) {
    if (machine.startsWith('iPhone') || machine.startsWith('iPad')) {
      return 'ARM64';
    }
    if (machine.contains('x86_64')) return 'x86_64';
    if (machine.contains('arm64')) return 'ARM64';
    return 'Unknown';
  }

  static String _limit(String value, int length, {required String fallback}) {
    final compact = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return fallback;
    return compact.length <= length ? compact : compact.substring(0, length);
  }
}

class _SystemDetails {
  final String platform;
  final String os;
  final String architecture;
  final String locale;
  final String model;

  const _SystemDetails({
    required this.platform,
    required this.os,
    required this.architecture,
    required this.locale,
    required this.model,
  });
}
