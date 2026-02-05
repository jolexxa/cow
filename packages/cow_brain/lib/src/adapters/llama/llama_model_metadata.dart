// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:ffi';

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Utility for reading GGUF model metadata.
final class LlamaModelMetadata {
  const LlamaModelMetadata({
    required LlamaBindings bindings,
    required Pointer<llama_model> model,
  }) : _bindings = bindings,
       _model = model;

  final LlamaBindings _bindings;
  final Pointer<llama_model> _model;

  /// Reads the chat template from the model metadata.
  ///
  /// Returns null if no chat template is available.
  String? get chatTemplate {
    final namePtr = nullptr.cast<Char>();
    // llama.cpp owns the returned pointer (static model data — no free needed).
    final result = _bindings.llama_model_chat_template(_model, namePtr);
    if (result == nullptr) return null;
    return result.cast<Utf8>().toDartString();
  }

  /// Reads a string metadata value by key.
  ///
  /// Returns null if the key is not found.
  String? getMetaString(String key) {
    final keyPtr = key.toNativeUtf8(allocator: calloc).cast<Char>();
    const bufSize = 4096;
    final buf = calloc<Char>(bufSize);
    try {
      final result = _bindings.llama_model_meta_val_str(
        _model,
        keyPtr,
        buf,
        bufSize,
      );
      if (result < 0) return null;
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc
        ..free(keyPtr)
        ..free(buf);
    }
  }
}
