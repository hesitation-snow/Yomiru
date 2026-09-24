import 'dart:async';

import 'package:flutter/foundation.dart';

/// Timer ticks only repaint the countdown; elapsed time comes from a deadline.
/// [refresh] catches up immediately when the app returns from the background.
class DeadlineCountdown extends ValueNotifier<int> {
  DeadlineCountdown({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(0);

  final DateTime Function() _now;
  DateTime? _deadline;
  Timer? _timer;
  VoidCallback? onElapsed;

  void start(int seconds) {
    stop();
    value = seconds.clamp(0, 1 << 31);
    if (value == 0) return;
    _deadline = _now().add(Duration(seconds: value));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void refresh() {
    final deadline = _deadline;
    if (deadline == null) return;
    final remaining = deadline.difference(_now()).inMilliseconds;
    value = ((remaining + 999) ~/ 1000).clamp(0, 1 << 31);
    if (value == 0) {
      stop();
      onElapsed?.call();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
