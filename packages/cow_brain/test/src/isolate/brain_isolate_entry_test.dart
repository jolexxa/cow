import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:test/test.dart';

void main() {
  test('brainIsolateEntry publishes a send port', () async {
    final receivePort = ReceivePort();
    brainIsolateEntry(receivePort.sendPort);

    final message = await receivePort.first;
    expect(message, isA<SendPort>());
    receivePort.close();
  });
}
