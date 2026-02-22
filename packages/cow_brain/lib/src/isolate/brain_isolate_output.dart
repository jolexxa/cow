// Internal output types for brain isolate state machine.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/brain_isolate_data.dart';
import 'package:cow_brain/src/isolate/models.dart';

sealed class BrainIsolateOutput {
  const BrainIsolateOutput();
}

final class SendEventRequested extends BrainIsolateOutput {
  const SendEventRequested({required this.event});
  final AgentEvent event;
}

final class SendErrorRequested extends BrainIsolateOutput {
  const SendErrorRequested({required this.message});
  final String message;
}

final class StreamTurnRequested extends BrainIsolateOutput {
  const StreamTurnRequested({this.sequenceId = 0});
  final int sequenceId;
}

final class CancelTurnRequested extends BrainIsolateOutput {
  const CancelTurnRequested({this.sequenceId = 0});
  final int sequenceId;
}

final class DisposeRuntimeRequested extends BrainIsolateOutput {
  const DisposeRuntimeRequested();
}

final class ResetRuntimeRequested extends BrainIsolateOutput {
  const ResetRuntimeRequested();
}

final class CompleteToolResultRequested extends BrainIsolateOutput {
  const CompleteToolResultRequested({required this.result});
  final ToolResult result;
}

final class StoreConfigRequested extends BrainIsolateOutput {
  const StoreConfigRequested({required this.config});
  final BrainIsolateConfig config;
}

final class CreateSequenceRequested extends BrainIsolateOutput {
  const CreateSequenceRequested({required this.request});
  final CreateSequenceRequest request;
}

final class DestroySequenceRequested extends BrainIsolateOutput {
  const DestroySequenceRequested({required this.request});
  final DestroySequenceRequest request;
}
