// Internal input types for brain isolate state machine.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';

sealed class BrainIsolateInput {
  const BrainIsolateInput();
}

final class InitInput extends BrainIsolateInput {
  const InitInput({required this.request});
  final InitRequest request;
}

final class RunTurnInput extends BrainIsolateInput {
  const RunTurnInput({required this.request});
  final RunTurnRequest request;
}

final class ToolResultInput extends BrainIsolateInput {
  const ToolResultInput({required this.result});
  final ToolResult result;
}

final class CancelInput extends BrainIsolateInput {
  const CancelInput();
}

final class ResetInput extends BrainIsolateInput {
  const ResetInput();
}

final class DisposeInput extends BrainIsolateInput {
  const DisposeInput();
}

final class TurnCompleted extends BrainIsolateInput {
  const TurnCompleted();
}

final class TurnFailed extends BrainIsolateInput {
  const TurnFailed({required this.error});
  final String error;
}
