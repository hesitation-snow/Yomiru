import 'dart:async';
import 'dart:collection';

/// 同一类后台工作共用并发上限，离开页面后尚未开始的工作直接跳过。
class BackgroundWorkQueue {
  BackgroundWorkQueue({required this.concurrency}) : assert(concurrency > 0);
  final int concurrency;
  final Queue<void Function()> _pending = Queue();
  int _active = 0;
  final _idleWaiters = <Completer<void>>[];

  Future<void> get whenIdle {
    if (_active == 0 && _pending.isEmpty) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  Future<T?> run<T>(Future<T> Function() work, {bool Function()? isCurrent}) {
    final result = Completer<T?>();
    _pending.add(() async {
      try {
        if (isCurrent == null || isCurrent()) {
          result.complete(await work());
        } else {
          result.complete(null);
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _active--;
        _pump();
      }
    });
    _pump();
    return result.future;
  }

  void _pump() {
    while (_active < concurrency && _pending.isNotEmpty) {
      _active++;
      _pending.removeFirst()();
    }
    if (_active == 0 && _pending.isEmpty) {
      for (final waiter in _idleWaiters) {
        waiter.complete();
      }
      _idleWaiters.clear();
    }
  }
}
