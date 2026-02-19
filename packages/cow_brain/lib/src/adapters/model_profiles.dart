// Model profiles are thin wiring; we keep docs light for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/extractors/json_tool_call_extractor.dart';
import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/adapters/qwen25_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/qwen3_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/stream_parser.dart';
import 'package:cow_brain/src/adapters/stream_tokenizer.dart';
import 'package:cow_brain/src/adapters/universal_stream_parser.dart';
import 'package:cow_brain/src/isolate/models.dart';

final class ModelProfiles {
  // -- Stream parsers --

  static final StreamParser qwenStreamParser = UniversalStreamParser(
    config: StreamParserConfig(
      toolCallExtractor: const JsonToolCallExtractor(),
      tags: StreamTokenizer.defaultTags,
      supportsReasoning: true,
      enableFallbackToolParsing: false,
    ),
  );

  // -- Model profiles --

  static final ModelProfile qwen3 = ModelProfile(
    formatter: const Qwen3PromptFormatter(),
    streamParser: qwenStreamParser,
  );

  static final ModelProfile qwen25 = ModelProfile(
    formatter: const Qwen25PromptFormatter(),
    streamParser: qwenStreamParser,
  );

  static ModelProfile profileFor(ModelProfileId id) {
    switch (id) {
      case ModelProfileId.qwen3:
        return qwen3;
      case ModelProfileId.qwen25:
        return qwen25;
      case ModelProfileId.auto:
        throw ArgumentError(
          'ModelProfileId.auto cannot be resolved statically. '
          'Use createAgent to resolve it from the runtime chat template.',
        );
    }
  }
}
