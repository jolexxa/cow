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

  group('sliding context — multi-step scenarios', () {
    Message system(String content) =>
        Message(role: Role.system, content: content);
    Message user(String content) => Message(role: Role.user, content: content);
    Message assistant(String content) =>
        Message(role: Role.assistant, content: content);

    test('incremental append preserves full reuse and no reset', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
      );

      // Step 1: system + user
      final msgs1 = [system('sys'), user('one')];
      final slice1 = manager.prepare(
        messages: msgs1,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
      );

      expect(slice1.reusePrefixMessageCount, 0);
      expect(slice1.requiresReset, isFalse);

      // Step 2: append assistant
      final msgs2 = [...msgs1, assistant('reply')];
      final slice2 = manager.prepare(
        messages: msgs2,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
        previousSlice: slice1,
      );

      expect(slice2.reusePrefixMessageCount, slice1.messages.length);
      expect(slice2.requiresReset, isFalse);

      // Step 3: append user
      final msgs3 = [...msgs2, user('two')];
      final slice3 = manager.prepare(
        messages: msgs3,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
        previousSlice: slice2,
      );

      expect(slice3.reusePrefixMessageCount, slice2.messages.length);
      expect(slice3.requiresReset, isFalse);

      // Step 4: append another user
      final msgs4 = [...msgs3, user('three')];
      final slice4 = manager.prepare(
        messages: msgs4,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
        previousSlice: slice3,
      );

      expect(slice4.reusePrefixMessageCount, slice3.messages.length);
      expect(slice4.requiresReset, isFalse);
      expect(slice4.droppedMessageCount, 0);
    });

    test('dropping a message triggers reset and adjusts reuse count', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
      );

      // Build conversation: system + 3 users (all fit)
      final msgs = [
        system('sys'),
        user('one'),
        user('two'),
        user('three'),
      ];
      final slice1 = manager.prepare(
        messages: msgs,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
      );

      expect(slice1.messages, hasLength(4));
      expect(slice1.droppedMessageCount, 0);

      // Now shrink context so something must be dropped.
      // Each message: 10 + content.length tokens.
      // sys=13, one=13, two=13, three=15 = 54 total.
      // Budget = contextSize - maxOutputTokens = contextSize - 10.
      // We need budget < 54 but >= (54 - 13) = 41 to drop exactly one.
      final slice2 = manager.prepare(
        messages: msgs,
        tools: const [],
        contextSize: 55,
        maxOutputTokens: 10,
        systemApplied: false,
        previousSlice: slice1,
      );

      // Should drop 'one' (first non-pinned message).
      expect(slice2.droppedMessageCount, 1);
      expect(slice2.messages, hasLength(3));
      expect(slice2.messages[0].role, Role.system);
      expect(slice2.messages[1].content, 'two');
      expect(slice2.messages[2].content, 'three');

      // The shared prefix is only [system('sys')], and previous had 4.
      // reusePrefixMessageCount = 1, previous had 4 messages, so reset.
      expect(slice2.reusePrefixMessageCount, 1);
      expect(slice2.requiresReset, isTrue);
    });

    test('recovery after drop — next append is incremental again', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
      );

      // Initial: system + 2 users (all fit in generous budget)
      final msgs1 = [system('sys'), user('one'), user('two')];
      final slice1 = manager.prepare(
        messages: msgs1,
        tools: const [],
        contextSize: 500,
        maxOutputTokens: 20,
        systemApplied: false,
      );

      // Force a drop by shrinking context.
      // sys=13, one=13, two=13 = 39 total. Budget = 45-10 = 35. Drop 'one'.
      final slice2 = manager.prepare(
        messages: msgs1,
        tools: const [],
        contextSize: 45,
        maxOutputTokens: 10,
        systemApplied: false,
        previousSlice: slice1,
      );

      expect(slice2.requiresReset, isTrue);
      expect(slice2.droppedMessageCount, 1);
      // After drop: [sys, two]

      // Simulate real app: FULL history grows, context stays tight.
      // The app keeps all messages; the context manager re-drops 'one'.
      final msgs3 = [...msgs1, assistant('ok')];
      final slice3 = manager.prepare(
        messages: msgs3,
        tools: const [],
        contextSize: 55,
        maxOutputTokens: 10,
        systemApplied: false,
        previousSlice: slice2,
      );

      // Context manager re-drops 'one', producing [sys, two, ok].
      // The prefix [sys, two] matches slice2, so reuse = 2, no reset.
      expect(slice3.droppedMessageCount, 1);
      expect(slice3.messages, hasLength(3));
      expect(slice3.messages[0].content, 'sys');
      expect(slice3.messages[1].content, 'two');
      expect(slice3.messages[2].content, 'ok');
      expect(slice3.reusePrefixMessageCount, slice2.messages.length);
      expect(slice3.requiresReset, isFalse);
    });

    test(
      'system prompt survives sliding while non-pinned messages drop first',
      () {
        final manager = SlidingWindowContextManager(
          counter: FakeTokenCounter(perToolTokens: 0),
        );

        // system + 5 user messages
        final msgs = [
          system('sys'),
          user('a'),
          user('b'),
          user('c'),
          user('d'),
          user('e'),
        ];

        // Each msg = 10 + content.length. sys=13, a-e=11 each = 68 total.
        // Budget = contextSize - maxOutputTokens.
        // Set budget to 46 (contextSize=56, maxOut=10). That fits sys(13) +
        // 3 messages of 11 = 46. Should drop 2 messages.
        final slice = manager.prepare(
          messages: msgs,
          tools: const [],
          contextSize: 56,
          maxOutputTokens: 10,
          systemApplied: false,
        );

        expect(slice.droppedMessageCount, 2);
        expect(slice.messages.first.role, Role.system);
        expect(slice.messages.first.content, 'sys');
        // Oldest non-pinned ('a' and 'b') should be dropped.
        expect(slice.messages[1].content, 'c');
        expect(slice.messages[2].content, 'd');
        expect(slice.messages[3].content, 'e');
      },
    );

    test('all non-pinned messages dropped before system is touched', () {
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
      );

      // With systemApplied=false, system is pinned.
      // system + 2 user messages = 3.
      // Make budget only fit system + 1 user.
      // sys=13, a=11, b=11 = 35. Budget = 24.
      final slice = manager.prepare(
        messages: [system('sys'), user('a'), user('b')],
        tools: const [],
        contextSize: 34,
        maxOutputTokens: 10,
        systemApplied: false,
      );

      // Should drop 'a', keep system + 'b'.
      expect(slice.droppedMessageCount, 1);
      expect(slice.messages, hasLength(2));
      expect(slice.messages[0].role, Role.system);
      expect(slice.messages[1].content, 'b');
    });

    test('dropping can orphan a tool result from its tool call', () {
      // This test documents a known limitation: the sliding window drops
      // messages individually without semantic awareness, so an assistant
      // tool-call message can be dropped while its tool result survives.
      final manager = SlidingWindowContextManager(
        counter: FakeTokenCounter(perToolTokens: 0),
      );

      final msgs = [
        system('sys'),
        user('question'),
        const Message(
          role: Role.assistant,
          content: 'calling tool',
          toolCalls: [
            ToolCall(id: 'c1', name: 'search', arguments: {'q': 'cows'}),
          ],
        ),
        const Message(
          role: Role.tool,
          content: 'tool result here',
          toolCallId: 'c1',
          name: 'search',
        ),
        user('follow-up'),
      ];

      // Token counts: sys=13, question=18, assistant=22, tool=26, follow=19
      // Total = 98. Budget = 70-10 = 60.
      // Drops 'question'(18) → 80 still > 60.
      // Drops 'calling tool'(22) → 58 ≤ 60. Stops.
      // Result: [sys, tool-result, follow-up] — orphaned tool result!
      final slice = manager.prepare(
        messages: msgs,
        tools: const [],
        contextSize: 70,
        maxOutputTokens: 10,
        systemApplied: false,
      );

      expect(slice.droppedMessageCount, 2);
      expect(slice.messages, hasLength(3));
      expect(slice.messages[0].role, Role.system);
      // The tool result survives without its parent tool call.
      expect(slice.messages[1].role, Role.tool);
      expect(slice.messages[1].toolCallId, 'c1');
      expect(slice.messages[2].content, 'follow-up');

      // Verify the assistant tool-call message is NOT in the output.
      final assistantToolCalls = slice.messages.where(
        (m) => m.toolCalls.isNotEmpty,
      );
      expect(assistantToolCalls, isEmpty);
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
