import 'package:cow_brain/cow_brain.dart';

final class ToolExecutor {
  ToolExecutor({required this.toolRegistry, required this.brain});

  final ToolRegistry toolRegistry;
  final CowBrain brain;

  Future<void> execute({
    required String turnId,
    required List<ToolCall> calls,
  }) async {
    try {
      final results = await toolRegistry.executeAll(calls);
      for (final result in results) {
        brain.sendToolResult(turnId: turnId, toolResult: result);
      }
    } on Object catch (error) {
      final results = calls
          .map(
            (call) => ToolResult(
              toolCallId: call.id,
              name: call.name,
              content: '',
              isError: true,
              errorMessage: error.toString(),
            ),
          )
          .toList();
      for (final result in results) {
        brain.sendToolResult(turnId: turnId, toolResult: result);
      }
    }
  }
}
