import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/utils/deep_equals_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('deepEquals extensions', () {
    test('Message.deepEquals compares tool calls and content', () {
      const left = Message(
        role: Role.assistant,
        content: 'hi',
        reasoningContent: 'think',
        toolCalls: [
          ToolCall(id: '1', name: 'search', arguments: {'q': 'cows'}),
        ],
      );
      const right = Message(
        role: Role.assistant,
        content: 'hi',
        reasoningContent: 'think',
        toolCalls: [
          ToolCall(id: '1', name: 'search', arguments: {'q': 'cows'}),
        ],
      );

      expect(left.deepEquals(right), isTrue);
    });

    test('ToolCallList.deepEquals detects length mismatch', () {
      const left = [
        ToolCall(id: '1', name: 'search', arguments: {}),
      ];
      const right = [
        ToolCall(id: '1', name: 'search', arguments: {}),
        ToolCall(id: '2', name: 'search', arguments: {}),
      ];

      expect(left.deepEquals(right), isFalse);
    });

    test('ToolCallList.deepEquals detects id and arguments mismatch', () {
      const left = [
        ToolCall(id: '1', name: 'search', arguments: {'q': 'cows'}),
      ];
      const right = [
        ToolCall(id: '2', name: 'search', arguments: {'q': 'cows'}),
      ];

      expect(left.deepEquals(right), isFalse);
    });

    test('ToolArgumentMap.deepEquals detects missing keys', () {
      final left = <String, Object?>{'q': 'cows', 'page': 1};
      final right = <String, Object?>{'q': 'cows'};

      expect(left.deepEquals(right), isFalse);
    });

    test('Object.deepEquals handles nested maps and lists', () {
      final left = <String, Object?>{
        'items': [
          {'k': 1},
          [1, 2],
        ],
      };
      final right = <String, Object?>{
        'items': [
          {'k': 1},
          [1, 2],
        ],
      };

      expect(left.deepEquals(right), isTrue);
    });

    test('ObjectList.deepEquals detects nested differences', () {
      final left = <Object?>[
        {'k': 1},
      ];
      final right = <Object?>[
        {'k': 2},
      ];

      expect(left.deepEquals(right), isFalse);
    });
  });
}
