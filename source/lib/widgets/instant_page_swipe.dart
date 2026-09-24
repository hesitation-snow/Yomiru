import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Observes a short, single-finger horizontal swipe without competing with
/// SelectionArea's recognizers. Long presses, mouse selection and pinches stay
/// with their original controls. The page itself never moves during the drag.
class InstantPageSwipe extends StatefulWidget {
  const InstantPageSwipe(
      {super.key,
      required this.enabled,
      required this.onTurn,
      required this.child});
  final bool enabled;
  final ValueChanged<bool> onTurn;
  final Widget child;
  @override
  State<InstantPageSwipe> createState() => _InstantPageSwipeState();
}

class _InstantPageSwipeState extends State<InstantPageSwipe> {
  final _pointers = <int>{};
  PointerDownEvent? _start;
  bool _swipeStarted = false;
  bool _longPress = false;

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || event.kind != PointerDeviceKind.touch) {
      _start = null;
      return;
    }
    _start = event;
    _swipeStarted = false;
    _longPress = false;
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (start == null ||
        _swipeStarted ||
        _longPress ||
        (event.position - start.position).distance < kTouchSlop) {
      return;
    }
    _longPress = event.timeStamp - start.timeStamp >= kLongPressTimeout;
    _swipeStarted = !_longPress;
  }

  void _up(PointerUpEvent event) {
    final start = _start;
    _pointers.remove(event.pointer);
    _start = null;
    if (start == null ||
        start.pointer != event.pointer ||
        _pointers.isNotEmpty) {
      return;
    }
    final delta = event.position - start.position;
    if (_longPress ||
        (!_swipeStarted &&
            event.timeStamp - start.timeStamp >= kLongPressTimeout) ||
        delta.dx.abs() < 40 ||
        delta.dx.abs() < delta.dy.abs() * 1.3) {
      return;
    }
    widget.onTurn(delta.dx < 0);
  }

  @override
  void didUpdateWidget(InstantPageSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _pointers.clear();
      _start = null;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.enabled ? _down : null,
        onPointerMove: widget.enabled ? _move : null,
        onPointerUp: widget.enabled ? _up : null,
        onPointerCancel: widget.enabled
            ? (event) {
                _pointers.remove(event.pointer);
                _start = null;
              }
            : null,
        child: widget.child,
      );
}
