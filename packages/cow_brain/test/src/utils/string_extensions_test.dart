import 'package:cow_brain/src/utils/string_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('StringTrimming', () {
    test(r'stripLeadingNewlines removes leading \n and \r', () {
      expect('\n\nhello'.stripLeadingNewlines(), 'hello');
      expect('\r\nhello'.stripLeadingNewlines(), 'hello');
      expect('hello'.stripLeadingNewlines(), 'hello');
      expect(''.stripLeadingNewlines(), '');
      expect('\n'.stripLeadingNewlines(), '');
    });

    test('stripEdgeNewlines removes both leading and trailing newlines', () {
      expect('\nhello\n'.stripEdgeNewlines(), 'hello');
      expect('\r\nhello\r\n'.stripEdgeNewlines(), 'hello');
      expect('hello\n\n'.stripEdgeNewlines(), 'hello');
      expect('\n\n'.stripEdgeNewlines(), '');
      expect('hello'.stripEdgeNewlines(), 'hello');
    });
  });

  group('StringBufferExtensions', () {
    test('toStringOrNull returns null for empty buffer', () {
      expect(StringBuffer().toStringOrNull(), isNull);
    });

    test('toStringOrNull returns contents for non-empty buffer', () {
      final buffer = StringBuffer()..write('hello');
      expect(buffer.toStringOrNull(), 'hello');
    });
  });
}
