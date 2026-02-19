import 'package:cow_brain/cow_brain.dart';

/// Encapsulates all brain interaction logic for summary generation.
///
/// Owns the lightweight brain lifecycle, text accumulation, and event
/// processing. ChatCubit just calls [generateSummary] and passes the result
/// back to SummaryLogic.
final class SummaryBrain {
  SummaryBrain({required CowBrain brain}) : _brain = brain;

  final CowBrain _brain;

  static const AgentSettings _settings = AgentSettings(
    safetyMarginTokens: 32,
    maxSteps: 2,
  );

  /// Generates a summary for the given text using the provided prompt.
  ///
  /// Resets the brain, runs the turn, accumulates text deltas, and returns
  /// the raw result. Throws on error.
  Future<String> generateSummary(String text, String prompt) async {
    _brain.reset();
    final buffer = StringBuffer();

    await for (final event in _brain.runTurn(
      userMessage: Message(role: Role.user, content: '$prompt\n\n$text'),
      settings: _settings,
      enableReasoning: false,
    )) {
      switch (event) {
        case AgentTextDelta(:final text):
          buffer.write(text);
        case AgentError(:final error):
          throw Exception(error);
        case AgentTurnFinished():
        case AgentStepFinished():
        case AgentStepStarted():
        case AgentReady():
        case AgentContextTrimmed():
        case AgentToolCalls():
        case AgentToolResult():
        case AgentTelemetryUpdate():
        case AgentReasoningDelta():
          break;
      }
    }

    return buffer.toString();
  }

  /// Initializes the brain with the given runtime options and profile.
  Future<void> init({
    required int modelHandle,
    required BackendRuntimeOptions options,
    required ModelProfileId profile,
  }) async {
    await _brain.init(
      modelHandle: modelHandle,
      options: options,
      profile: profile,
      tools: const [],
      settings: _settings,
      enableReasoning: false,
    );
  }
}
