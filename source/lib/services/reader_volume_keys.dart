import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ModalRoute 包含目录/设置弹窗，盖住阅读器时必须把音量键还给系统。
final readerRouteObserver = RouteObserver<ModalRoute<dynamic>>();

class ReaderVolumeKeys {
  ReaderVolumeKeys({required this.onTurn, required this.isEligible});
  static const channel = MethodChannel('moe.yutro.yomiru/reader_keys');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static int _nextOwner = 0;
  static ReaderVolumeKeys? _active;
  final int _owner = ++_nextOwner;
  final void Function(bool forward) onTurn;
  final bool Function() isEligible;
  bool _disposed = false;

  void sync({bool force = false}) {
    if (!supported || _disposed) return;
    final enabled = isEligible();
    if (enabled) {
      if (identical(_active, this) && !force) return;
      _active = this;
      channel.setMethodCallHandler(_handleCall);
      unawaited(_send(true));
    } else if (identical(_active, this)) {
      _active = null;
      unawaited(_send(false));
    }
  }

  static Future<void> _handleCall(MethodCall call) async {
    final active = _active;
    final args = call.arguments;
    if (call.method != 'volumeKey' ||
        active == null ||
        args is! Map ||
        args['owner'] != active._owner ||
        !active.isEligible()) {
      return;
    }
    if (args['direction'] == 'next') active.onTurn(true);
    if (args['direction'] == 'previous') active.onTurn(false);
  }

  Future<void> _send(bool enabled) async {
    try {
      await channel.invokeMethod<void>(
          'setVolumePaging', {'enabled': enabled, 'owner': _owner});
    } on MissingPluginException {
      // 测试环境/旧壳不支持；不得影响普通阅读。
    } on PlatformException {
      // 平台不可用时不打断正文。
    }
  }

  void dispose() {
    if (identical(_active, this)) {
      _active = null;
      unawaited(_send(false));
    }
    _disposed = true;
  }
}
