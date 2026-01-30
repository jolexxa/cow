import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  test('ContextSlice exposes computed fields and is immutable', () {
    const message = Message(role: Role.user, content: 'Hi');
    final slice = ContextSlice(
      messages: const [message],
      estimatedPromptTokens: 7,
      droppedMessageCount: 0,
      contextSize: 128,
      maxOutputTokens: 16,
      safetyMarginTokens: 4,
      budgetTokens: 108,
      remainingTokens: 101,
      reusePrefixMessageCount: 0,
      requiresReset: false,
    );

    expect(slice.safetyMarginTokens, 4);
    expect(slice.budgetTokens, 108);
    expect(slice.remainingTokens, 101);
    expect(() => slice.messages.add(message), throwsUnsupportedError);
  });

  test('ContextSlice preserves provided safety margin and reset flags', () {
    final slice = ContextSlice(
      messages: const <Message>[],
      estimatedPromptTokens: 0,
      droppedMessageCount: 2,
      contextSize: 256,
      maxOutputTokens: 32,
      safetyMarginTokens: 12,
      budgetTokens: 212,
      remainingTokens: 200,
      reusePrefixMessageCount: 1,
      requiresReset: true,
    );

    expect(slice.safetyMarginTokens, 12);
    expect(slice.requiresReset, isTrue);
    expect(slice.reusePrefixMessageCount, 1);
  });
}
