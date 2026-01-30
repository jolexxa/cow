import 'package:cow_brain/src/core/core.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('Conversation', () {
    test('initial includes a system prompt when provided', () {
      final conversation = Conversation.initial(
        systemPrompt: 'You are helpful.',
      );

      expect(conversation.messages, hasLength(1));
      expect(conversation.messages.single.role, Role.system);
      expect(conversation.messages.single.content, 'You are helpful.');
    });

    test('beginTurn returns incrementing turn ids', () {
      final conversation = Conversation.initial();

      expect(conversation.beginTurn(), 'turn-1');
      expect(conversation.beginTurn(), 'turn-2');
    });

    test('systemApplied can be toggled explicitly', () {
      final conversation = Conversation.initial();

      expect(conversation.systemApplied, isFalse);
      conversation.setSystemApplied(value: true);
      expect(conversation.systemApplied, isTrue);
      conversation.setSystemApplied(value: false);
      expect(conversation.systemApplied, isFalse);
    });

    test('addUser rejects empty content', () {
      final conversation = Conversation.initial();

      expect(() => conversation.addUser('   '), throwsArgumentError);
    });

    test('appendAssistantText allows empty content', () {
      final conversation = Conversation.initial().appendAssistantText('');

      expect(conversation.messages.single.role, Role.assistant);
      expect(conversation.messages.single.content, isEmpty);
    });

    test('appendAssistantToolCalls rejects duplicate tool call ids', () {
      const calls = [
        ToolCall(id: '1', name: 'search', arguments: {}),
        ToolCall(id: '1', name: 'search', arguments: {}),
      ];

      expect(
        () => Conversation.initial().appendAssistantToolCalls(calls),
        throwsArgumentError,
      );
    });

    test('appendAssistantToolCalls rejects empty call lists', () {
      expect(
        () => Conversation.initial().appendAssistantToolCalls(const []),
        throwsArgumentError,
      );
    });

    test('appendToolResult requires a matching tool call id', () {
      const result = ToolResult(
        toolCallId: 'missing',
        name: 'search',
        content: 'nope',
      );

      expect(
        () => Conversation.initial().appendToolResult(result),
        throwsArgumentError,
      );
    });

    test('appendToolResult requires the tool name to match the call', () {
      final conversation = Conversation.initial().appendAssistantToolCalls(
        const [
          ToolCall(id: '1', name: 'search', arguments: {}),
        ],
      );

      const result = ToolResult(
        toolCallId: '1',
        name: 'lookup',
        content: 'mismatch',
      );

      expect(() => conversation.appendToolResult(result), throwsArgumentError);
    });

    test('appendToolResult appends a tool message when valid', () {
      final conversation = Conversation.initial().appendAssistantToolCalls(
        const [
          ToolCall(id: '1', name: 'search', arguments: {}),
        ],
      );

      final updated = conversation.appendToolResult(
        const ToolResult(toolCallId: '1', name: 'search', content: 'ok'),
      );

      expect(updated.messages, hasLength(2));
      final toolMessage = updated.messages.last;
      expect(toolMessage.role, Role.tool);
      expect(toolMessage.toolCallId, '1');
      expect(toolMessage.name, 'search');
      expect(toolMessage.content, 'ok');
    });
  });
}
