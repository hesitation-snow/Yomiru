import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 接口异常(code != 0 / HTTP 错误 / 网络错误)
class LKException implements Exception {
  final int code;
  final String message;
  final bool accessRestricted;
  LKException(this.code, this.message, {this.accessRestricted = false});
  @override
  String toString() => message.isEmpty ? '请求失败(错误码 $code)' : message;
}

/// 登录会话(持久化字段由上层保存)
class LKSession {
  String securityKey = '';
  int uid = 0;
  String nickname = '';
  String avatar = '';
  bool get isLoggedIn => securityKey.isNotEmpty;

  void clear() {
    securityKey = '';
    uid = 0;
    nickname = '';
    avatar = '';
  }
}

/// lightnovel.fun 正式服 API 客户端
/// 统一走站点提供的 pc-proxy 网关,全部 POST + JSON。
class LKClient {
  LKClient._();
  static final LKClient shared = LKClient._();

  /// 登录态版本号:登录/登出/会话变更时自增,UI 监听刷新(如"我的"页用户卡片)
  static final ValueNotifier<int> sessionRev = ValueNotifier<int>(0);

  final String base = 'https://www.lightnovel.fun/api/pc-proxy';
  final LKSession session = LKSession();

  // 仅供公开、只读接口使用的响应缓存。缓存键不包含 security_key、cookie
  // 或其他会话凭据；私信、消息、福利和个人资料等敏感接口不会传入 cacheKey。
  static const _responseCachePrefix = 'lk_response_cache_v1_';
  static Future<SharedPreferences>? _cachePrefs;

  static Future<SharedPreferences> _responsePrefs() =>
      _cachePrefs ??= SharedPreferences.getInstance();

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36 LKFlutter/0.1',
    'Origin': 'https://www.lightnovel.fun',
    'Referer': 'https://www.lightnovel.fun/',
    // iOS 上避免复用可能挂起的 keep-alive 连接
    'Connection': 'close',
  };

  /// 自动附加 security_key(登录态接口用)
  Map<String, dynamic> authed([Map<String, dynamic> extra = const {}]) {
    final b = Map<String, dynamic>.from(extra);
    if (session.securityKey.isNotEmpty) b['security_key'] = session.securityKey;
    return b;
  }

  /// POST → 校验 code==0 → 返回 data
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {String? accessErrorMessage,
      String? cacheKey,
      Duration? cacheTtl,
      bool forceRefresh = false}) async {
    final cached = cacheKey == null ? null : await _readCached(cacheKey);
    if (cached != null &&
        !forceRefresh &&
        cacheTtl != null &&
        DateTime.now().millisecondsSinceEpoch - cached.savedAt <=
            cacheTtl.inMilliseconds) {
      return cached.data;
    }

    late final http.Response resp;
    try {
      resp = await http
          .post(Uri.parse('$base$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (cached != null) return cached.data;
      throw LKException(-1, '连接超时，请检查网络后重试');
    } catch (_) {
      if (cached != null) return cached.data;
      throw LKException(-1, '连接失败，请检查网络后重试');
    }
    if (resp.statusCode >= 400) {
      // 不记录响应正文:错误响应可能包含账号信息或服务端回显内容。
      debugPrint('LKHTTP status=${resp.statusCode} path=$path');
      if (cached != null && resp.statusCode >= 500) return cached.data;
      throw LKException(resp.statusCode, '网络异常(HTTP ${resp.statusCode})');
    }
    final Object? obj;
    try {
      obj = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw LKException(-1, '响应解析失败');
    }
    if (obj is! Map<String, dynamic>) throw LKException(-1, '响应格式错误');
    final code = (obj['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      if (cached != null && code >= 500) return cached.data;
      final msg = _extractMessage(obj['data']);
      throw LKException(code, msg.isNotEmpty ? msg : _codeHint(code));
    }
    final data = obj['data'];
    if (data is Map<String, dynamic>) {
      if (cacheKey != null) await _writeCached(cacheKey, data);
      return data;
    }
    if (accessErrorMessage != null) {
      throw LKException(403, accessErrorMessage, accessRestricted: true);
    }
    throw LKException(-1, '响应格式错误');
  }

  Future<_CachedResponse?> _readCached(String key) async {
    try {
      final raw =
          (await _responsePrefs()).getString('$_responseCachePrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt = (decoded['saved_at'] as num?)?.toInt() ?? 0;
      final data = decoded['data'];
      if (savedAt <= 0 || data is! Map) return null;
      return _CachedResponse(savedAt, Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCached(String key, Map<String, dynamic> data) async {
    try {
      await (await _responsePrefs()).setString(
        '$_responseCachePrefix$key',
        jsonEncode({
          'saved_at': DateTime.now().millisecondsSinceEpoch,
          'data': data,
        }),
      );
    } catch (_) {
      // 缓存写入失败不影响正常请求结果。
    }
  }

  /// POST → 返回 data(不做模型转换)
  Future<void> postVoid(String path, Map<String, dynamic> body) async {
    await post(path, body);
  }

  static String _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final m = data['message'];
      if (m is String && m.isNotEmpty) return m;
      for (final v in data.values) {
        if (v is List && v.isNotEmpty && v.first is String) {
          return v.first as String;
        }
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return '';
  }

  /// 常见错误码的友好提示
  static String _codeHint(int code) => switch (code) {
        8 => '登录状态已失效,请重新登录',
        403 => '没有权限执行此操作',
        404 => '内容不存在或已删除',
        429 => '操作太频繁,请稍后再试',
        500 => '服务器开小差了,请稍后再试',
        _ => '请求失败(错误码 $code)',
      };

  /// pageSize 服务端上限 50
  static int clampPageSize(int n) => n < 1 ? 1 : (n > 50 ? 50 : n);

  /// multipart 头像上传,返回新头像 URL
  Future<String> uploadAvatar(String filePath, String md5Hex) async {
    final key = session.securityKey;
    if (key.isEmpty) throw LKException(8, '未登录');
    final req = http.MultipartRequest(
        'POST', Uri.parse('$base/api/bff/upload-my-avatar-v1'));
    req.headers.addAll({
      'User-Agent': _headers['User-Agent']!,
      'Origin': _headers['Origin']!,
      'Referer': _headers['Referer']!,
    });
    req.fields['security_key'] = key;
    req.fields['scene'] = 'user_avatar';
    req.fields['md5'] = md5Hex;
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final resp = await req.send().timeout(const Duration(seconds: 40));
    final bytes = await resp.stream.toBytes();
    final obj = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final code = (obj['code'] as num?)?.toInt() ?? -1;
    if (code != 0) throw LKException(code, _extractMessage(obj['data']));
    final d = (obj['data'] as Map<String, dynamic>?) ?? {};
    return (d['url'] as String?) ?? (d['avatar'] as String?) ?? '';
  }

  /// 上传动态/评论图片,统一返回站点 data 对象。
  Future<Map<String, dynamic>> uploadMultipart(
      String path, String filePath, Map<String, String> fields) async {
    final key = session.securityKey;
    if (key.isEmpty) throw LKException(8, '未登录');
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'));
    req.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': _headers['User-Agent']!,
      'Origin': _headers['Origin']!,
      'Referer': _headers['Referer']!,
    });
    req.fields['security_key'] = key;
    req.fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final resp = await req.send().timeout(const Duration(seconds: 40));
    final bytes = await resp.stream.toBytes();
    if (resp.statusCode >= 400) {
      throw LKException(resp.statusCode, '网络异常(HTTP ${resp.statusCode})');
    }
    final obj = jsonDecode(utf8.decode(bytes));
    if (obj is! Map<String, dynamic>) throw LKException(-1, '响应格式错误');
    final code = (obj['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final message = _extractMessage(obj['data']);
      throw LKException(code, message.isEmpty ? _codeHint(code) : message);
    }
    final data = obj['data'];
    if (data is Map<String, dynamic>) return data;
    throw LKException(-1, '响应格式错误');
  }
}

class _CachedResponse {
  final int savedAt;
  final Map<String, dynamic> data;

  const _CachedResponse(this.savedAt, this.data);
}
