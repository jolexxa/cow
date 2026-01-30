import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('SlidingWindowContextManager', () {
    const tool = ToolDefinition(
      name: 'search',
      description: 'search the web',
      parameters: {},
    );

    Message system(String content) =>
        Message(role: Role.system, content: content);
    Message user(String content) => Message(role: Role.user, content: content);

    test(
      'slides by dropping whole messages while pinning the system prompt',
      () {
        final manager = SlidingWindowContextManager(
          counter: FakeTokenCounter(perToolTokens: 0),
        );

        final slice = manager.prepare(
          messages: [
            system('You are a careful assistant.'),
            user('First user message that will be trimmed.'),
            user('Second user message that should remain.'),
          ],
          tools: const [],
          contextSize: 110,
          maxOutputTokens: 10,
          systemApplied: false,
        );

        expect(slice.droppedMessageCount, 1);
        expect(slice.messages, hasLength(2));
        expect(slice.messages.first.role, Role.system);
        expect(slice.messages.last.content, contains('Second'));
      },
    );

    test('allows dropping the system prompt when it is already applied', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(),
      );

      final slice = manager.prepare(
        messages: [system('system'), user('user')],
        tools: const [],
        contextSize: 25,
        maxOutputTokens: 10,
        systemApplied: true,
      );

      expect(slice.messages, hasLength(1));
      expect(slice.messages.single.role, Role.user);
    });

    test('safety margin reduces the usable budget', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
        safetyMarginTokens: 10,
      );

      final slice = manager.prepare(
        messages: [
          user('Message about cows and tools.'),
          user('Follow-up message with more detail.'),
        ],
        tools: const [],
        contextSize: 75,
        maxOutputTokens: 10,
        systemApplied: true,
      );

      expect(slice.droppedMessageCount, 1);
    });

    test('tool definitions contribute to trimming decisions', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 30),
      );

      final slice = manager.prepare(
        messages: [
          user('Message about cows and tools.'),
          user('Follow-up message with more detail.'),
        ],
        tools: const [tool],
        contextSize: 88,
        maxOutputTokens: 10,
        systemApplied: true,
      );

      expect(slice.droppedMessageCount, 1);
    });

    test('reuse hints show append-only compatibility without reset', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(),
      );

      final previous = manager.prepare(
        messages: [system('system'), user('one')],
        tools: const [],
        contextSize: 200,
        maxOutputTokens: 20,
        systemApplied: false,
      );

      final next = manager.prepare(
        messages: [system('system'), user('one'), user('two')],
        tools: const [],
        contextSize: 200,
        maxOutputTokens: 20,
        systemApplied: false,
        previousSlice: previous,
      );

      expect(next.reusePrefixMessageCount, previous.messages.length);
      expect(next.requiresReset, isFalse);
    });

    test(
      'sliding triggers requiresReset when the prefix is no longer intact',
      () {
        final manager = SlidingWindowContextManager(
          counter: FakeTokenCounter(),
        );

        final previous = manager.prepare(
          messages: [system('system'), user('one'), user('two')],
          tools: const [],
          contextSize: 200,
          maxOutputTokens: 20,
          systemApplied: false,
        );

        final next = manager.prepare(
          messages: [system('system'), user('one'), user('two')],
          tools: const [],
          contextSize: 45,
          maxOutputTokens: 10,
          systemApplied: false,
          previousSlice: previous,
        );

        expect(next.messages, hasLength(2));
        expect(next.reusePrefixMessageCount, 1);
        expect(next.requiresReset, isTrue);
      },
    );

    test('throws when the budget is not positive', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(),
        safetyMarginTokens: 10,
      );

      expect(
        () => manager.prepare(
          messages: [user('hi')],
          tools: const [],
          contextSize: 10,
          maxOutputTokens: 10,
          systemApplied: true,
        ),
        throwsArgumentError,
      );
    });

    test('throws when the prompt cannot fit after dropping messages', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(baseTokens: 1000),
      );

      expect(
        () => manager.prepare(
          messages: [system('system')],
          tools: const [],
          contextSize: 50,
          maxOutputTokens: 10,
          systemApplied: false,
        ),
        throwsStateError,
      );
    });
  });
}

final class FakeTokenCounter implements TokenCounter {
  FakeTokenCounter({
    this.baseTokens = 0,
    this.perMessageTokens = 10,
    this.perToolTokens = 20,
  });

  final int baseTokens;
  final int perMessageTokens;
  final int perToolTokens;

  @override
  int countPromptTokens({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
  }) {
    final messageTokens = messages.fold<int>(
      0,
      (total, message) => total + perMessageTokens + message.content.length,
    );
    final toolTokens = tools.length * perToolTokens;
    return baseTokens + messageTokens + toolTokens;
  }
}
