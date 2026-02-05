// Model profiles are thin wiring; we keep docs light for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/extractors/json_tool_call_extractor.dart';
import 'package:cow_brain/src/adapters/llama/llama_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/llama/llama_stream_parser.dart';
import 'package:cow_brain/src/adapters/llama/qwen25_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/llama/qwen3_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/llama/stream_tokenizer.dart';
import 'package:cow_brain/src/adapters/llama/universal_stream_parser.dart';
import 'package:cow_brain/src/isolate/models.dart';

final class LlamaProfiles {
  // -- Stream parsers --

  static final LlamaStreamParser qwenStreamParser = UniversalStreamParser(
    config: StreamParserConfig(
      toolCallExtractor: const JsonToolCallExtractor(),
      tags: StreamTokenizer.defaultTags,
      supportsReasoning: true,
      enableFallbackToolParsing: false,
    ),
  );

  // -- Model profiles --

  static final LlamaModelProfile qwen3 = LlamaModelProfile(
    formatter: const Qwen3PromptFormatter(),
    streamParser: qwenStreamParser,
  );

  static final LlamaModelProfile qwen25 = LlamaModelProfile(
    formatter: const Qwen25PromptFormatter(),
    streamParser: qwenStreamParser,
  );

  static LlamaModelProfile profileFor(LlamaProfileId id) {
    switch (id) {
      case LlamaProfileId.qwen3:
        return qwen3;
      case LlamaProfileId.qwen25:
        return qwen25;
      case LlamaProfileId.auto:
        throw ArgumentError(
          'LlamaProfileId.auto cannot be resolved statically. '
          'Use createAgent to resolve it from the runtime chat template.',
        );
    }
  }
}
