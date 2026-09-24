import 'package:flutter/services.dart';

/// Only the newest reader may change system bars during route replacement.
/// Register before loading preferences so an outgoing route cannot reset them.
class ReaderSystemUi {
  static final List<ReaderSystemUi> _readers = [];
  bool? _hidden;

  ReaderSystemUi() {
    _readers.add(this);
  }

  void apply(bool hidden) {
    _hidden = hidden;
    if (_readers.isNotEmpty && identical(_readers.last, this)) {
      SystemChrome.setEnabledSystemUIMode(
          hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  void dispose() {
    final wasCurrent = _readers.isNotEmpty && identical(_readers.last, this);
    _readers.remove(this);
    if (!wasCurrent) return;
    if (_readers.isEmpty) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      final previous = _readers.last;
      if (previous._hidden != null) previous.apply(previous._hidden!);
    }
  }
}
