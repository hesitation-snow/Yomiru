import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 全局头像缓存：优先显示本地文件，并在缓存过期后后台重新获取。
class YomiruAvatarCache {
  static final CacheManager manager = CacheManager(
    Config(
      'yomiru_avatar_cache',
      stalePeriod: const Duration(hours: 12),
      maxNrOfCacheObjects: 500,
    ),
  );

  static CachedNetworkImageProvider provider(String url) =>
      CachedNetworkImageProvider(url, cacheManager: manager);

  /// 预加载当前页面的头像。失败时静默处理，不阻塞页面内容。
  static void precache(BuildContext context, Iterable<String> urls) {
    final unique = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .take(40);
    for (final url in unique) {
      unawaited(precacheImage(provider(url), context).catchError((_) {}));
    }
  }
}

/// 勋章图使用独立缓存，避免和头像缓存互相挤占；网络可用时会按缓存策略后台更新。
class YomiruMedalCache {
  static final CacheManager manager = CacheManager(
    Config(
      'yomiru_medal_cache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 1000,
    ),
  );

  static CachedNetworkImageProvider provider(String url) =>
      CachedNetworkImageProvider(url, cacheManager: manager);

  /// 预加载勋章图到本地缓存，失败时不影响商城页面。
  static void precache(BuildContext context, Iterable<String> urls) {
    final unique = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .take(100);
    for (final url in unique) {
      unawaited(precacheImage(provider(url), context).catchError((_) {}));
    }
  }
}
