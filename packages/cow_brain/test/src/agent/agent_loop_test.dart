import 'package:cow_brain/src/agent/agent.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/core.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group('AgentLoop', () {
    test('emits a simple text finish and turn finish', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputTextDelta('Hello'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);
      final tools = ToolRegistry();
      final context = PassthroughContextManager();
      final loop = _buildLoop(
        llm: llm,
        tools: tools,
        context: context,
        contextSize: 512,
        maxOutputTokens: 64,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      expect(events.map((e) => e.runtimeType), [
        AgentStepStarted,
        AgentTelemetryUpdate,
        AgentTextDelta,
        AgentStepFinished,
        AgentTurnFinished,
      ]);

      final finished = events.whereType<AgentStepFinished>().single;
      expect(finished.text, 'Hello');
      expect(convo.messages.last.role, Role.assistant);
      expect(convo.messages.last.content, 'Hello');
      expect(convo.systemApplied, isTrue);
    });

    test(
      'tool calls emit results and the loop continues to the next step',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputTextDelta('Let me check.'),
            OutputToolCalls([
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {'q': 'cows'},
              ),
            ]),
            OutputStepFinished(FinishReason.stop),
          ],
          const [
            OutputTextDelta('All set.'),
            OutputStepFinished(FinishReason.stop),
          ],
        ]);

        final tools = ToolRegistry()
          ..register(
            const ToolDefinition(
              name: 'search',
              description: 'Search the web',
              parameters: {},
            ),
            (args) => 'Result for ${args['q']}',
          );

        final loop = _buildLoop(
          llm: llm,
          tools: tools,
          contextSize: 512,
          maxOutputTokens: 64,
        );

        final convo = Conversation.initial().addUser('Find cow facts');
        final events = await loop.runTurn(convo).toList();

        expect(events.whereType<AgentStepStarted>(), hasLength(2));
        expect(events.whereType<AgentToolResult>(), hasLength(1));

        final toolFinishIndex = events.indexWhere(
          (e) => e is AgentToolCalls,
        );
        final toolResultIndex = events.indexWhere(
          (e) => e is AgentToolResult,
        );
        final textFinishIndex = events.indexWhere(
          (e) => e is AgentStepFinished,
        );
        expect(toolFinishIndex, greaterThanOrEqualTo(0));
        expect(toolResultIndex, greaterThan(toolFinishIndex));
        expect(textFinishIndex, greaterThan(toolResultIndex));

        expect(convo.messages.map((m) => m.role), [
          Role.user,
          Role.assistant,
          Role.tool,
          Role.assistant,
        ]);
        expect(convo.messages[1].toolCalls, hasLength(1));
        expect(convo.messages.last.content, 'All set.');
      },
    );

    test(
      'recomputes with systemApplied=false when a reset is required',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputStepFinished(FinishReason.stop),
          ],
        ]);

        final context = RecordingContextManager([
          ContextSlice(
            messages: const [Message(role: Role.system, content: 'System')],
            estimatedPromptTokens: 10,
            droppedMessageCount: 0,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 438,
            reusePrefixMessageCount: 0,
            requiresReset: true,
          ),
          ContextSlice(
            messages: const [Message(role: Role.system, content: 'System')],
            estimatedPromptTokens: 10,
            droppedMessageCount: 0,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 438,
            reusePrefixMessageCount: 0,
            requiresReset: false,
          ),
        ]);

        final loop = _buildLoop(
          llm: llm,
          context: context,
          contextSize: 512,
          maxOutputTokens: 64,
        );

        final convo = Conversation.initial(systemPrompt: 'System')
          ..setSystemApplied(value: true)
          ..addUser('Hi');

        await loop.runTurn(convo).toList();

        expect(context.calls, hasLength(2));
        expect(context.calls.first.systemApplied, isTrue);
        expect(context.calls.last.systemApplied, isFalse);
        expect(context.calls.last.previousSlice, isNull);

        final config = llm.receivedConfigs.single;
        expect(config.requiresReset, isTrue);
      },
    );

    test('forces a reset when enableReasoning toggles between turns', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputStepFinished(FinishReason.stop),
        ],
        const [
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final context = RecordingContextManager([
        ContextSlice(
          messages: const [Message(role: Role.system, content: 'System')],
          estimatedPromptTokens: 10,
          droppedMessageCount: 0,
          contextSize: 512,
          maxOutputTokens: 64,
          safetyMarginTokens: 0,
          budgetTokens: 448,
          remainingTokens: 438,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
        ContextSlice(
          messages: const [Message(role: Role.system, content: 'System')],
          estimatedPromptTokens: 10,
          droppedMessageCount: 0,
          contextSize: 512,
          maxOutputTokens: 64,
          safetyMarginTokens: 0,
          budgetTokens: 448,
          remainingTokens: 438,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
        ContextSlice(
          messages: const [Message(role: Role.system, content: 'System')],
          estimatedPromptTokens: 10,
          droppedMessageCount: 0,
          contextSize: 512,
          maxOutputTokens: 64,
          safetyMarginTokens: 0,
          budgetTokens: 448,
          remainingTokens: 438,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
      ]);

      final loop = _buildLoop(
        llm: llm,
        context: context,
        contextSize: 512,
        maxOutputTokens: 64,
      );

      final convo = Conversation.initial(systemPrompt: 'System')..addUser('Hi');

      await loop.runTurn(convo).toList();

      convo.addUser('Hi again');
      await loop.runTurn(convo, enableReasoning: false).toList();

      expect(context.calls, hasLength(3));
      expect(context.calls[1].systemApplied, isTrue);
      expect(context.calls[2].systemApplied, isFalse);
      expect(context.calls[2].previousSlice, isNull);

      final secondConfig = llm.receivedConfigs[1];
      expect(secondConfig.requiresReset, isTrue);
    });

    test('emits context trimmed events when messages are dropped', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputStepFinished(FinishReason.stop),
        ],
      ]);
      final context = RecordingContextManager([
        ContextSlice(
          messages: const [Message(role: Role.user, content: 'Hi')],
          estimatedPromptTokens: 10,
          droppedMessageCount: 1,
          contextSize: 512,
          maxOutputTokens: 64,
          safetyMarginTokens: 0,
          budgetTokens: 448,
          remainingTokens: 438,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
      ]);

      final loop = _buildLoop(
        llm: llm,
        context: context,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      expect(events.whereType<AgentContextTrimmed>(), hasLength(1));
    });

    test('trims leading newlines on first text delta', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputTextDelta('\nHello'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      final delta = events.whereType<AgentTextDelta>().single;
      expect(delta.text, 'Hello');
      expect(convo.messages.last.content, 'Hello');
    });

    test('trims leading newlines on first reasoning delta', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputReasoningDelta('\nBecause.'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      final delta = events.whereType<AgentReasoningDelta>().single;
      expect(delta.text, 'Because.');
      expect(convo.messages.last.reasoningContent, 'Because.');
    });

    test('emits cancelled when the llm throws CancelledException', () async {
      final llm = ErroringLlmAdapter(const CancelledException());

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      final finished = events.last as AgentTurnFinished;
      expect(finished.finishReason, FinishReason.cancelled);
    });

    test('emits error when the llm throws', () async {
      final llm = ErroringLlmAdapter(StateError('boom'));

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      expect(events.whereType<AgentError>(), hasLength(1));
      final finished = events.last as AgentTurnFinished;
      expect(finished.finishReason, FinishReason.error);
    });

    test('emits maxSteps when tool calls never complete the turn', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputToolCalls([
            ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cow'}),
          ]),
          OutputStepFinished(FinishReason.stop),
        ],
        const [
          OutputToolCalls([
            ToolCall(id: 'call-2', name: 'search', arguments: {'q': 'pony'}),
          ]),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final tools = ToolRegistry()
        ..register(
          const ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: {},
          ),
          (args) => 'ok',
        );

      final loop = _buildLoop(
        llm: llm,
        tools: tools,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo, maxSteps: 2).toList();

      final finished = events.last as AgentTurnFinished;
      expect(finished.finishReason, FinishReason.maxSteps);
    });

    test('emits telemetry update and tool calls with pre-tool text', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputReasoningDelta('\nReasoning'),
          OutputTextDelta('\nWorking'),
          OutputToolCalls([
            ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cow'}),
          ]),
          OutputStepFinished(FinishReason.stop),
        ],
        const [
          OutputTextDelta('Done.'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final tools = ToolRegistry()
        ..register(
          const ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: {},
          ),
          (args) => 'ok',
        );

      final context = RecordingContextManager([
        ContextSlice(
          messages: const [Message(role: Role.user, content: 'Hi')],
          estimatedPromptTokens: 10,
          droppedMessageCount: 0,
          contextSize: 128,
          maxOutputTokens: 32,
          safetyMarginTokens: 1,
          budgetTokens: 95,
          remainingTokens: 85,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
        ContextSlice(
          messages: const [Message(role: Role.user, content: 'Hi')],
          estimatedPromptTokens: 12,
          droppedMessageCount: 0,
          contextSize: 128,
          maxOutputTokens: 32,
          safetyMarginTokens: 1,
          budgetTokens: 95,
          remainingTokens: 83,
          reusePrefixMessageCount: 0,
          requiresReset: false,
        ),
      ]);

      final loop = _buildLoop(
        llm: llm,
        tools: tools,
        context: context,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop
          .runTurn(
            convo,
            toolExecutor: (calls) async => [
              const ToolResult(
                toolCallId: 'call-1',
                name: 'search',
                content: 'ok',
              ),
            ],
          )
          .toList();

      final telemetry = events.whereType<AgentTelemetryUpdate>().first;
      expect(telemetry.promptTokens, 10);
      expect(telemetry.remainingTokens, 85);

      final toolCalls = events.whereType<AgentToolCalls>().first;
      expect(toolCalls.preToolText, 'Working');
      expect(toolCalls.preToolReasoning, 'Reasoning');

      expect(events.whereType<AgentToolResult>(), hasLength(1));
    });

    test('cancels mid-stream when shouldCancel toggles', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputTextDelta('Hello'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      var cancelChecks = 0;
      bool shouldCancel() {
        cancelChecks += 1;
        return cancelChecks >= 2;
      }

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop
          .runTurn(convo, shouldCancel: shouldCancel)
          .toList();

      final finished = events.last as AgentTurnFinished;
      expect(finished.finishReason, FinishReason.cancelled);
      expect(events.whereType<AgentStepFinished>(), isEmpty);
    });

    test('cancels before tool execution when shouldCancel is true', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputToolCalls([
            ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cow'}),
          ]),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final tools = ToolRegistry()
        ..register(
          const ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: {},
          ),
          (args) => throw StateError('Should not be called'),
        );

      final loop = _buildLoop(
        llm: llm,
        tools: tools,
      );

      // Checks: (1) start of while loop, (2) after OutputToolCalls processed,
      // (3) after OutputStepFinished processed, (4) before toolExecutor.
      // Return true on 4th call to hit line 227 specifically.
      var cancelChecks = 0;
      bool shouldCancel() {
        cancelChecks += 1;
        return cancelChecks >= 4;
      }

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop
          .runTurn(convo, shouldCancel: shouldCancel)
          .toList();

      final finished = events.last as AgentTurnFinished;
      expect(finished.finishReason, FinishReason.cancelled);
      expect(events.whereType<AgentToolResult>(), isEmpty);
      expect(events.whereType<AgentToolCalls>(), hasLength(1));
    });

    test('drops empty deltas after trimming', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputTextDelta('\n'),
          OutputReasoningDelta('\r\n'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      expect(events.whereType<AgentTextDelta>(), isEmpty);
      expect(events.whereType<AgentReasoningDelta>(), isEmpty);
    });

    test('emits telemetry updates as output tokens are generated', () async {
      final llm = FakeLlmAdapter([
        const [
          OutputTokensGenerated(2),
          OutputTextDelta('Hello'),
          OutputTokensGenerated(3),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final loop = _buildLoop(
        llm: llm,
      );

      final convo = Conversation.initial().addUser('Hi');
      final events = await loop.runTurn(convo).toList();

      final telemetry = events.whereType<AgentTelemetryUpdate>().toList();
      expect(telemetry.length, greaterThan(1));
      final initial = telemetry.first.remainingTokens;
      final finalRemaining = telemetry.last.remainingTokens;
      expect(finalRemaining, initial - 5);
    });

    test(
      'propagates non-stop finish reasons to step and turn events',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputTextDelta('Partial'),
            OutputStepFinished(FinishReason.length),
          ],
        ]);

        final loop = _buildLoop(
          llm: llm,
        );

        final convo = Conversation.initial().addUser('Hi');
        final events = await loop.runTurn(convo).toList();

        final stepFinished = events.whereType<AgentStepFinished>().single;
        expect(stepFinished.finishReason, FinishReason.length);

        final turnFinished = events.last as AgentTurnFinished;
        expect(turnFinished.finishReason, FinishReason.length);
      },
    );
  });

  group('incremental context & KV cache management', () {
    test('chains previousSlice across multi-step tool loop', () async {
      final slice1 = ContextSlice(
        messages: const [Message(role: Role.user, content: 'Hi')],
        estimatedPromptTokens: 10,
        droppedMessageCount: 0,
        contextSize: 512,
        maxOutputTokens: 64,
        safetyMarginTokens: 0,
        budgetTokens: 448,
        remainingTokens: 438,
        reusePrefixMessageCount: 0,
        requiresReset: false,
      );
      final slice2 = ContextSlice(
        messages: const [Message(role: Role.user, content: 'Hi')],
        estimatedPromptTokens: 12,
        droppedMessageCount: 0,
        contextSize: 512,
        maxOutputTokens: 64,
        safetyMarginTokens: 0,
        budgetTokens: 448,
        remainingTokens: 436,
        reusePrefixMessageCount: 1,
        requiresReset: false,
      );

      final llm = FakeLlmAdapter([
        const [
          OutputToolCalls([
            ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cow'}),
          ]),
          OutputStepFinished(FinishReason.stop),
        ],
        const [
          OutputTextDelta('Done.'),
          OutputStepFinished(FinishReason.stop),
        ],
      ]);

      final tools = ToolRegistry()
        ..register(
          const ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: {},
          ),
          (args) => 'ok',
        );

      final context = RecordingContextManager([slice1, slice2]);

      final loop = _buildLoop(
        llm: llm,
        tools: tools,
        context: context,
      );

      final convo = Conversation.initial().addUser('Hi');
      await loop.runTurn(convo).toList();

      // First call has no previousSlice.
      expect(context.calls[0].previousSlice, isNull);
      // Second call gets slice1 as previousSlice.
      expect(context.calls[1].previousSlice, same(slice1));
    });

    test(
      'sends incremental reuse count and no reset for append-only steps',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputToolCalls([
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {'q': 'cow'},
              ),
            ]),
            OutputStepFinished(FinishReason.stop),
          ],
          const [
            OutputTextDelta('Done.'),
            OutputStepFinished(FinishReason.stop),
          ],
        ]);

        final tools = ToolRegistry()
          ..register(
            const ToolDefinition(
              name: 'search',
              description: 'Search',
              parameters: {},
            ),
            (args) => 'ok',
          );

        final loop = _buildLoop(
          llm: llm,
          tools: tools,
          contextSize: 512,
          maxOutputTokens: 64,
        );

        final convo = Conversation.initial().addUser('Hi');
        await loop.runTurn(convo).toList();

        // Step 1: no previous context, so reuse=0.
        expect(llm.receivedConfigs[0].requiresReset, isFalse);
        expect(llm.receivedConfigs[0].reusePrefixMessageCount, 0);

        // Step 2: conversation grew, passthrough context manager
        // sets reuse to previous message count.
        expect(llm.receivedConfigs[1].requiresReset, isFalse);
        expect(
          llm.receivedConfigs[1].reusePrefixMessageCount,
          greaterThan(0),
        );
      },
    );

    test(
      'sends requiresReset=true when context manager signals prefix break',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputStepFinished(FinishReason.stop),
          ],
        ]);

        final context = RecordingContextManager([
          ContextSlice(
            messages: const [Message(role: Role.user, content: 'Hi')],
            estimatedPromptTokens: 10,
            droppedMessageCount: 1,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 438,
            reusePrefixMessageCount: 1,
            requiresReset: true,
          ),
          // Second prepare call after systemApplied reset.
          ContextSlice(
            messages: const [Message(role: Role.user, content: 'Hi')],
            estimatedPromptTokens: 10,
            droppedMessageCount: 1,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 438,
            reusePrefixMessageCount: 0,
            requiresReset: false,
          ),
        ]);

        final loop = _buildLoop(
          llm: llm,
          context: context,
        );

        final convo = Conversation.initial(systemPrompt: 'System')
          ..setSystemApplied(value: true)
          ..addUser('Hi');
        await loop.runTurn(convo).toList();

        final config = llm.receivedConfigs.single;
        expect(config.requiresReset, isTrue);
        expect(config.reusePrefixMessageCount, 0);
      },
    );

    test(
      'previousSlice is null on first step, set on subsequent steps',
      () async {
        final llm = FakeLlmAdapter([
          const [
            OutputToolCalls([
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {'q': 'cow'},
              ),
            ]),
            OutputStepFinished(FinishReason.stop),
          ],
          const [
            OutputTextDelta('Done.'),
            OutputStepFinished(FinishReason.stop),
          ],
        ]);

        final tools = ToolRegistry()
          ..register(
            const ToolDefinition(
              name: 'search',
              description: 'Search',
              parameters: {},
            ),
            (args) => 'ok',
          );

        final context = RecordingContextManager([
          ContextSlice(
            messages: const [Message(role: Role.user, content: 'Hi')],
            estimatedPromptTokens: 10,
            droppedMessageCount: 0,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 438,
            reusePrefixMessageCount: 0,
            requiresReset: false,
          ),
          ContextSlice(
            messages: const [Message(role: Role.user, content: 'Hi')],
            estimatedPromptTokens: 12,
            droppedMessageCount: 0,
            contextSize: 512,
            maxOutputTokens: 64,
            safetyMarginTokens: 0,
            budgetTokens: 448,
            remainingTokens: 436,
            reusePrefixMessageCount: 1,
            requiresReset: false,
          ),
        ]);

        final loop = _buildLoop(
          llm: llm,
          tools: tools,
          context: context,
        );

        final convo = Conversation.initial().addUser('Hi');
        await loop.runTurn(convo).toList();

        expect(context.calls, hasLength(2));
        expect(context.calls[0].previousSlice, isNull);
        expect(context.calls[1].previousSlice, isNotNull);
      },
    );
  });
}

AgentLoop _buildLoop({
  required LlmAdapter llm,
  ToolRegistry? tools,
  ContextManager? context,
  int contextSize = 128,
  int maxOutputTokens = 32,
}) {
  return AgentLoop(
    llm: llm,
    tools: tools ?? ToolRegistry(),
    context: context ?? PassthroughContextManager(),
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: 0.7,
  );
}

final class FakeLlmAdapter implements LlmAdapter {
  FakeLlmAdapter(this._scriptPerCall);

  final List<List<ModelOutput>> _scriptPerCall;
  final List<LlmConfig> receivedConfigs = <LlmConfig>[];
  var _callIndex = 0;

  @override
  Stream<ModelOutput> next({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
    required LlmConfig config,
  }) {
    receivedConfigs.add(config);
    final script = _scriptPerCall[_callIndex];
    _callIndex += 1;
    return Stream<ModelOutput>.fromIterable(script);
  }
}

final class PassthroughContextManager implements ContextManager {
  @override
  ContextSlice prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required int contextSize,
    required int maxOutputTokens,
    required bool systemApplied,
    ContextSlice? previousSlice,
  }) {
    return ContextSlice(
      messages: messages,
      estimatedPromptTokens: messages.length,
      droppedMessageCount: 0,
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      safetyMarginTokens: 0,
      budgetTokens: contextSize - maxOutputTokens,
      remainingTokens: contextSize - maxOutputTokens - messages.length,
      reusePrefixMessageCount: previousSlice?.messages.length ?? 0,
      requiresReset: false,
    );
  }
}

final class RecordingContextManager implements ContextManager {
  RecordingContextManager(this._slices);

  final List<ContextSlice> _slices;
  final List<PrepareCall> calls = <PrepareCall>[];
  var _index = 0;

  @override
  ContextSlice prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required int contextSize,
    required int maxOutputTokens,
    required bool systemApplied,
    ContextSlice? previousSlice,
  }) {
    calls.add(
      PrepareCall(systemApplied: systemApplied, previousSlice: previousSlice),
    );
    final slice = _slices[_index];
    _index += 1;
    return slice;
  }
}

final class ErroringLlmAdapter implements LlmAdapter {
  ErroringLlmAdapter(this._error);

  final Object _error;

  @override
  Stream<ModelOutput> next({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
    required LlmConfig config,
  }) {
    return Stream<ModelOutput>.error(_error);
  }
}

final class PrepareCall {
  const PrepareCall({
    required this.systemApplied,
    required this.previousSlice,
  });

  final bool systemApplied;
  final ContextSlice? previousSlice;
}
