// Process-level llama.cpp backend lifecycle + logging ownership.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';

final class LlamaBackend {
  LlamaBackend({required String libraryPath}) : _libraryPath = libraryPath;

  final String _libraryPath;
  bool _acquired = false;

  void ensureInitialized() {
    if (_acquired) {
      _LlamaBackendState.instance.validate(
        libraryPath: _libraryPath,
      );
      return;
    }
    _acquired = true;
    _LlamaBackendState.instance.acquire(
      libraryPath: _libraryPath,
    );
  }

  void release() {
    if (!_acquired) {
      return;
    }
    _acquired = false;
    _LlamaBackendState.instance.release();
  }
}

final class _LlamaBackendState {
  _LlamaBackendState._();

  static final _LlamaBackendState instance = _LlamaBackendState._();

  int _refCount = 0;
  String? _libraryPath;
  LlamaBindings? _bindings;

  void validate({required String libraryPath}) {
    if (_refCount == 0) {
      return;
    }
    if (_libraryPath != libraryPath) {
      throw StateError(
        'llama backend already initialized with a different configuration.',
      );
    }
  }

  void acquire({required String libraryPath}) {
    if (_refCount > 0) {
      validate(libraryPath: libraryPath);
      _refCount += 1;
      return;
    }
    _bindings = LlamaClient.openBindings(libraryPath: libraryPath);
    _bindings!.llama_backend_init();
    _libraryPath = libraryPath;
    _refCount = 1;
  }

  void release() {
    if (_refCount == 0) {
      return;
    }
    _refCount -= 1;
    if (_refCount > 0) {
      return;
    }
    _bindings?.llama_backend_free();
    _bindings = null;
    _libraryPath = null;
  }
}
