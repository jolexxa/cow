// Agent runner interface for testing and isolate orchestration.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/isolate/models.dart';

typedef ToolExecutor = Future<List<ToolResult>> Function(List<ToolCall> calls);

abstract interface class AgentRunner {
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps,
    bool enableReasoning,
  });

  int get contextSize;
  int get maxOutputTokens;
}
