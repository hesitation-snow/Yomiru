import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomiru/widgets/reader_device_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'displays formatted time without battery and updates independently',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ReaderDeviceStatus(color: Colors.grey)));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    await tester.pump(const Duration(seconds: 61));
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
