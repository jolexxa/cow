import 'package:cow_brain/src/adapters/local_token_counter.dart';
import 'package:cow_brain/src/adapters/qwen3_prompt_formatter.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('LocalTokenCounter', () {
    const formatter = Qwen3PromptFormatter();
    const tool = ToolDefinition(
      name: 'search',
      description: 'Search the web',
      parameters: {'type': 'object'},
    );

    int countTokens(String prompt, {required bool addBos}) {
      return prompt.length + (addBos ? 1 : 0);
    }

    const messages = [
      Message(role: Role.system, content: 'You are helpful.'),
      Message(role: Role.user, content: 'Tell me about cows.'),
    ];

    test('counts tokens on the fully formatted prompt', () {
      final counter = LocalTokenCounter(
        formatter: formatter,
        tokenCounter: countTokens,
      );

      final withoutTools = counter.countPromptTokens(
        messages: messages,
        tools: const [],
        systemApplied: false,
      );
      final withTools = counter.countPromptTokens(
        messages: messages,
        tools: const [tool],
        systemApplied: false,
      );
      final systemApplied = counter.countPromptTokens(
        messages: messages,
        tools: const [],
        systemApplied: true,
      );

      expect(withTools, greaterThan(withoutTools));
      expect(systemApplied, lessThan(withoutTools));
    });
  });
}
