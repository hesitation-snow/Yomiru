import 'dart:async';

import 'package:flutter/material.dart';

/// Displays current time in the reader independently of chapter layout;
/// suspends updates in the background.
class ReaderDeviceStatus extends StatefulWidget {
  const ReaderDeviceStatus({super.key, required this.color});
  final Color color;

  @override
  State<ReaderDeviceStatus> createState() => _ReaderDeviceStatusState();
}

class _ReaderDeviceStatusState extends State<ReaderDeviceStatus>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _time = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextMinute();
  }

  void _scheduleNextMinute() {
    _timer?.cancel();
    // Align the clock to the next minute with a safety buffer against scheduler jitter.
    final msToNextMinute =
        60000 - (DateTime.now().millisecondsSinceEpoch % 60000) + 50;
    _timer = Timer(Duration(milliseconds: msToNextMinute), () {
      if (!mounted) return;
      setState(() => _time = DateTime.now());
      _scheduleNextMinute();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _time = DateTime.now());
      _scheduleNextMinute();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: Text(
        time,
        style: TextStyle(fontSize: 11, color: widget.color),
      ),
    );
  }
}
