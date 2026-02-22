// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/model_profiles.dart';
import 'package:cow_brain/src/adapters/prompt_formatter.dart';

/// Detects the appropriate [ModelProfile] from a Jinja2 chat template.
final class ProfileDetector {
  const ProfileDetector();

  /// Sniffs the chat template string for marker tokens and returns the
  /// appropriate model profile.
  ModelProfile? detect(String chatTemplate) {
    // ChatML (Qwen): uses <|im_start|> / <|im_end|>
    if (chatTemplate.contains('<|im_start|>')) {
      return ModelProfiles.qwen3;
    }

    // Unrecognized template — let the caller decide on a fallback.
    return null;
  }
}
