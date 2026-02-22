// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs
// This needs to be abstracted anyways.
// ignore_for_file: one_member_abstracts

import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/core/model_output.dart';

abstract interface class StreamParser {
  Stream<ModelOutput> parse(Stream<StreamChunk> chunks);
}
