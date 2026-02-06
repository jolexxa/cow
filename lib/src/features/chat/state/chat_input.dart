import 'package:cow/src/features/chat/state/models/brain_role.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow_brain/cow_brain.dart';

/// Inputs to the chat session state machine.
sealed class ChatInput {
  const ChatInput();
}

/// Initialize the session and load models.
final class Start extends ChatInput {
  const Start({this.existingMessages = const []});

  final List<ChatMessage> existingMessages;
}

/// Models loaded successfully.
final class ModelsLoaded extends ChatInput {
  const ModelsLoaded({required this.settings});

  final AgentSettings settings;
}

/// Model loading failed.
final class ModelsLoadFailed extends ChatInput {
  const ModelsLoadFailed(this.error);

  final String error;
}

/// Submit a user message.
final class Submit extends ChatInput {
  const Submit(this.message, {required this.responseId});

  final String message;
  final int responseId;
}

/// An agent event was received during turn streaming.
final class AgentEventReceived extends ChatInput {
  const AgentEventReceived(this.event);

  final AgentEvent event;
}

/// Tool calls need to be executed.
final class ExecutingToolCalls extends ChatInput {
  const ExecutingToolCalls(this.event);

  final AgentToolCalls event;
}

/// Tool execution completed.
final class ToolCallsComplete extends ChatInput {
  const ToolCallsComplete();
}

/// Turn streaming completed.
final class TurnFinalized extends ChatInput {
  const TurnFinalized();
}

/// Turn streaming failed with an error.
final class TurnError extends ChatInput {
  const TurnError(this.error);

  final String error;
}

/// Cancel the current turn.
final class Cancel extends ChatInput {
  const Cancel();
}

/// Clear all messages and reset.
final class Clear extends ChatInput {
  const Clear();
}

/// Reset to ready state without clearing history.
final class Reset extends ChatInput {
  const Reset();
}

/// Toggle reasoning on/off.
final class ToggleReasoning extends ChatInput {
  const ToggleReasoning();
}

/// Dispose the session and clean up resources.
final class Dispose extends ChatInput {
  const Dispose();
}

/// Model loading progress update.
final class ModelLoadProgressUpdate extends ChatInput {
  const ModelLoadProgressUpdate({
    required this.currentModel,
    required this.totalModels,
    required this.progress,
    required this.modelName,
  });

  final int currentModel;
  final int totalModels;
  final double progress;
  final String modelName;
}

/// A model has finished loading.
final class ModelLoaded extends ChatInput {
  const ModelLoaded({required this.role, required this.model});

  final BrainRole role;
  final LoadedModel model;
}

/// Set the total number of models to load.
final class SetTotalModels extends ChatInput {
  const SetTotalModels(this.count);

  final int count;
}

/// Brains have been initialized and are ready.
final class BrainsInitialized extends ChatInput {
  const BrainsInitialized({required this.settings});

  final AgentSettings settings;
}
