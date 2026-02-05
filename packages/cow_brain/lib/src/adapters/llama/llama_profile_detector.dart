// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_profiles.dart';
import 'package:cow_brain/src/adapters/llama/llama_prompt_formatter.dart';

/// Detects the appropriate [LlamaModelProfile] from a Jinja2 chat template.
final class LlamaProfileDetector {
  const LlamaProfileDetector();

  /// Sniffs the chat template string for marker tokens and returns the
  /// appropriate model profile.
  LlamaModelProfile? detect(String chatTemplate) {
    // ChatML (Qwen): uses <|im_start|> / <|im_end|>
    if (chatTemplate.contains('<|im_start|>')) {
      return LlamaProfiles.qwen3;
    }

    // Unrecognized template — let the caller decide on a fallback.
    return null;
  }
}
