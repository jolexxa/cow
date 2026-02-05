import 'dart:ffi';

import 'package:cow_brain/src/adapters/llama/llama_model_metadata.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaModelMetadata', () {
    test('chatTemplate returns null when native returns nullptr', () {
      final bindings = FakeLlamaBindings();
      // Default impl returns nullptr.
      final metadata = LlamaModelMetadata(
        bindings: bindings,
        model: Pointer.fromAddress(1),
      );

      expect(metadata.chatTemplate, isNull);
    });

    test('chatTemplate returns string when native returns a pointer', () {
      final template = '<|im_start|>system\n'.toNativeUtf8().cast<Char>();
      final bindings = FakeLlamaBindings()..chatTemplateResult = template;

      final metadata = LlamaModelMetadata(
        bindings: bindings,
        model: Pointer.fromAddress(1),
      );

      expect(metadata.chatTemplate, '<|im_start|>system\n');
      calloc.free(template);
    });

    test('getMetaString returns null when key is not found', () {
      final bindings = FakeLlamaBindings();
      // Default metaValStrResult is -1 → not found.
      final metadata = LlamaModelMetadata(
        bindings: bindings,
        model: Pointer.fromAddress(1),
      );

      expect(metadata.getMetaString('general.name'), isNull);
    });

    test('getMetaString returns value when key is found', () {
      final bindings = FakeLlamaBindings()
        ..metaValStrImpl = (model, key, buf, bufSize) {
          const value = 'Qwen2.5-7B';
          final units = value.codeUnits;
          for (var i = 0; i < units.length; i++) {
            (buf + i).value = units[i];
          }
          (buf + units.length).value = 0;
          return units.length;
        };

      final metadata = LlamaModelMetadata(
        bindings: bindings,
        model: Pointer.fromAddress(1),
      );

      expect(metadata.getMetaString('general.name'), 'Qwen2.5-7B');
    });
  });
}
