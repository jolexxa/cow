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

  /// Creates handles from a shared model pointer (address as int).
  /// Use this when receiving a model pointer from another isolate.
  factory LlamaHandles.fromModelPointer({
    required int modelPointer,
    required LlamaBindings bindings,
  }) {
    final model = Pointer<llama_model>.fromAddress(modelPointer);
    final vocab = bindings.llama_model_get_vocab(model);
    return LlamaHandles(
      bindings: bindings,
      model: model,
      context: nullptr,
      vocab: vocab,
    );
  }

  final LlamaBindings bindings;
  final Pointer<llama_model> model;
  Pointer<llama_context> context;
  final Pointer<llama_vocab> vocab;

  /// Returns the model pointer as an integer address for cross-isolate sharing.
  int get modelPointerAddress => model.address;
}
