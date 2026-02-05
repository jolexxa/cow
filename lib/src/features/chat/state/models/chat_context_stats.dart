final class ChatContextStats {
  const ChatContextStats({
    required this.promptTokens,
    required this.contextSize,
    required this.budgetTokens,
    required this.remainingTokens,
    required this.maxOutputTokens,
    required this.safetyMarginTokens,
  });

  final int promptTokens;
  final int contextSize;
  final int budgetTokens;
  final int remainingTokens;
  final int maxOutputTokens;
  final int safetyMarginTokens;

  int get usagePercent {
    if (contextSize <= 0) return 0;
    final percent = (promptTokens * 100 / contextSize).round();
    if (percent < 0) return 0;
    if (percent > 100) return 100;
    return percent;
  }
}
