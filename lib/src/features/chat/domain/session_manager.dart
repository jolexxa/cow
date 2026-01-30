import 'package:cow_brain/cow_brain.dart';

final class SessionManager {
  SessionManager({
    required this.brains,
    required this.mainKey,
    required this.summaryKey,
  });

  final CowBrains<String> brains;
  final String mainKey;
  final String summaryKey;

  late final CowBrain main;
  late final CowBrain summary;

  void create({CowBrain? existingBrain}) {
    main = existingBrain ?? brains.create(mainKey);
    summary = brains.create(summaryKey);
  }

  Future<void> initMain({
    required LlamaRuntimeOptions runtimeOptions,
    required LlamaProfileId profile,
    required List<ToolDefinition> tools,
    required AgentSettings settings,
    required bool enableReasoning,
  }) async {
    await main.init(
      runtimeOptions: runtimeOptions,
      profile: profile,
      tools: tools,
      settings: settings,
      enableReasoning: enableReasoning,
    );
  }

  Future<void> initSummary({
    required LlamaRuntimeOptions runtimeOptions,
    required LlamaProfileId profile,
  }) async {
    await summary.init(
      runtimeOptions: runtimeOptions,
      profile: profile,
      tools: const [],
      settings: const AgentSettings(safetyMarginTokens: 64, maxSteps: 1),
      enableReasoning: false,
    );
  }

  Future<void> dispose() async {
    await brains.remove(mainKey);
    await brains.remove(summaryKey);
  }
}
