// Native llama.cpp models/options are low-level; docs can come later.
// ignore_for_file: public_member_api_docs

import 'dart:ffi';

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final class LlamaHandles {
  LlamaHandles({
    required this.bindings,
    required this.model,
    required this.context,
    required this.vocab,
  });

  final LlamaBindings bindings;
  final Pointer<llama_model> model;
  Pointer<llama_context> context;
  final Pointer<llama_vocab> vocab;
}
