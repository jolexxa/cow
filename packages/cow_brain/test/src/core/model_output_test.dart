import 'package:cow_brain/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ModelOutput', () {
    test('CancelledException is an Exception', () {
      expect(const CancelledException(), isA<Exception>());
    });
  });
}
