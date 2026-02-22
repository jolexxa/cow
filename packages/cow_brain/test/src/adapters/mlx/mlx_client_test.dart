import 'dart:convert';
import 'dart:ffi';

import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_mlx_bindings.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MlxClient _client({String libraryPath = '/fake/libCowMLX.dylib'}) =>
    MlxClient(libraryPath: libraryPath);

/// Build a pre-wired [MlxHandles] that uses [bindings] directly so tests
/// don't need to go through [MlxClient.loadModel].
MlxHandles _handles(
  FakeMlxBindings bindings, {
  int modelHandle = 1,
  int contextHandle = -1,
}) => MlxHandles(
  bindings: bindings,
  modelHandle: modelHandle,
  contextHandle: contextHandle,
);

void main() {
  late FakeMlxBindings bindings;

  setUp(() {
    bindings = FakeMlxBindings();
    MlxClient.openBindings = ({required String libraryPath}) => bindings;
  });

  tearDown(() {
    MlxClient.openBindings = MlxBindingsLoader.open;
  });

  // -------------------------------------------------------------------------
  // _ensureBindings — lazy init
  // -------------------------------------------------------------------------

  group('_ensureBindings (lazy init)', () {
    test('calls openBindings then init_() on first access', () {
      var openCalls = 0;
      MlxClient.openBindings = ({required String libraryPath}) {
        openCalls++;
        return bindings;
      };

      final _ = _client()
        // Trigger lazy init via loadModel.
        ..loadModel(modelPath: '/model');

      expect(openCalls, 1);
      expect(bindings.initCalls, 1);
    });

    test('does not call init_() again on subsequent accesses', () {
      final _ = _client()
        ..loadModel(modelPath: '/model')
        ..loadModel(modelPath: '/model');

      expect(bindings.initCalls, 1);
    });
  });

  // -------------------------------------------------------------------------
  // loadModel
  // -------------------------------------------------------------------------

  group('loadModel', () {
    test(
      'calls bindings.loadModel and returns MlxHandles with contextHandle -1',
      () {
        bindings.loadModelResult = 5;

        final client = _client();
        final handles = client.loadModel(modelPath: '/path/to/model');

        expect(bindings.loadModelCalls, 1);
        expect(handles.modelHandle, 5);
        expect(handles.contextHandle, -1);
        expect(handles.bindings, same(bindings));
      },
    );

    test('throws StateError when loadModel returns negative handle', () {
      bindings
        ..loadModelResult = -1
        ..getErrorResult = 'file not found';

      final client = _client();

      expect(
        () => client.loadModel(modelPath: '/bad/path'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('file not found'),
          ),
        ),
      );
    });

    test('uses Unknown error when getError returns null', () {
      bindings
        ..loadModelResult = -1
        ..getErrorResult = null;

      final client = _client();

      expect(
        () => client.loadModel(modelPath: '/bad/path'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Unknown error'),
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // tokenize
  // -------------------------------------------------------------------------

  group('tokenize', () {
    test('returns tokens from bindings on successful call', () {
      // Default FakeMlxBindings writes [101, 102, 103] and returns 3.
      final client = _client();
      final handles = _handles(bindings);

      final tokens = client.tokenize(handles, 'hello');

      expect(tokens, [101, 102, 103]);
      expect(bindings.tokenizeCalls, 1);
    });

    test(
      'retries with larger buffer when first call signals buffer too small',
      () {
        var callCount = 0;
        bindings.tokenizeImpl =
            (
              modelHandle,
              text,
              textLen,
              outTokens,
              maxTokens,
              addSpecial,
            ) {
              callCount++;
              if (callCount == 1) {
                // Negative (not -1) signals needed size = 5.
                return -5;
              }
              // Second call — write 5 tokens.
              for (var i = 0; i < 5; i++) {
                outTokens[i] = i + 1;
              }
              return 5;
            };

        final client = _client();
        final handles = _handles(bindings);

        final tokens = client.tokenize(handles, 'hello world');

        expect(tokens, [1, 2, 3, 4, 5]);
        expect(bindings.tokenizeCalls, 2);
      },
    );

    test('throws StateError when tokenization fails even after retry', () {
      bindings.tokenizeImpl = (_, _, _, _, _, _) => -2;

      final client = _client();
      final handles = _handles(bindings);

      expect(
        () => client.tokenize(handles, 'hello'),
        throwsStateError,
      );
    });

    test('passes addSpecial flag to bindings', () {
      bool? capturedAddSpecial;
      bindings.tokenizeImpl =
          (
            modelHandle,
            text,
            textLen,
            outTokens,
            maxTokens,
            addSpecial,
          ) {
            capturedAddSpecial = addSpecial;
            outTokens[0] = 1;
            return 1;
          };

      final client = _client();
      final handles = _handles(bindings);

      client.tokenize(handles, 'hi', addSpecial: false);

      expect(capturedAddSpecial, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // createContext
  // -------------------------------------------------------------------------

  group('createContext', () {
    test('returns context handle from bindings', () {
      bindings.createContextResult = 99;

      final client = _client();
      final handles = _handles(bindings);

      final ctx = client.createContext(handles, 512);

      expect(ctx, 99);
      expect(bindings.createContextCalls, 1);
    });

    test('throws StateError when createContext returns negative', () {
      bindings.createContextResult = -1;

      final client = _client();
      final handles = _handles(bindings);

      expect(
        () => client.createContext(handles, 512),
        throwsStateError,
      );
    });
  });

  // -------------------------------------------------------------------------
  // resetContext
  // -------------------------------------------------------------------------

  group('resetContext', () {
    test('frees old context and creates a new one', () {
      bindings.createContextResult = 20;

      final client = _client();
      final handles = _handles(bindings, contextHandle: 10);

      client.resetContext(handles, 512);

      expect(bindings.freeContextCalls, 1);
      expect(bindings.lastFreeContextHandle, 10);
      expect(handles.contextHandle, 20);
    });

    test('does not call freeContext when contextHandle is -1', () {
      bindings.createContextResult = 5;

      final client = _client();
      final handles = _handles(bindings);

      client.resetContext(handles, 256);

      expect(bindings.freeContextCalls, 0);
      expect(handles.contextHandle, 5);
    });
  });

  // -------------------------------------------------------------------------
  // isEog
  // -------------------------------------------------------------------------

  group('isEog', () {
    test('returns true when bindings say token is end-of-generation', () {
      bindings.isEogResult = true;

      final client = _client();
      final handles = _handles(bindings);

      expect(client.isEog(handles, 2), isTrue);
      expect(bindings.isEogCalls, 1);
    });

    test('returns false when bindings say token is not end-of-generation', () {
      bindings.isEogResult = false;

      final client = _client();
      final handles = _handles(bindings);

      expect(client.isEog(handles, 5), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // generateBegin
  // -------------------------------------------------------------------------

  group('generateBegin', () {
    test('calls bindings with correct tokens and sampling options', () {
      const options = SamplingOptions(
        seed: 7,
        temperature: 0.8,
        topP: 0.9,
        topK: 50,
        minP: 0.1,
        penaltyRepeat: 1.2,
        penaltyLastN: 32,
      );

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      client.generateBegin(handles, [10, 20, 30], options);

      expect(bindings.generateBeginCalls, 1);
      expect(bindings.lastGenerateBeginTokens, [10, 20, 30]);
      expect(bindings.lastTemperature, closeTo(0.8, 1e-9));
      expect(bindings.lastTopP, closeTo(0.9, 1e-9));
      expect(bindings.lastTopK, 50);
      expect(bindings.lastMinP, closeTo(0.1, 1e-9));
      expect(bindings.lastRepeatPenalty, closeTo(1.2, 1e-9));
      expect(bindings.lastRepeatWindow, 32);
      expect(bindings.lastSeed, 7);
    });

    test('uses default sampling values when options fields are null', () {
      const options = SamplingOptions();

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      client.generateBegin(handles, [1], options);

      // Defaults from MlxClient source: temp=0.7, topP=0.95, topK=40,
      // minP=0.05, repeatPenalty=1.1, repeatWindow=64, seed=0.
      expect(bindings.lastTemperature, closeTo(0.7, 1e-9));
      expect(bindings.lastTopP, closeTo(0.95, 1e-9));
      expect(bindings.lastTopK, 40);
      expect(bindings.lastMinP, closeTo(0.05, 1e-9));
      expect(bindings.lastRepeatPenalty, closeTo(1.1, 1e-9));
      expect(bindings.lastRepeatWindow, 64);
      expect(bindings.lastSeed, 0);
    });

    test('does nothing when tokens list is empty', () {
      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      client.generateBegin(handles, [], const SamplingOptions());

      expect(bindings.generateBeginCalls, 0);
    });

    test('throws StateError when generateBegin fails', () {
      bindings
        ..generateBeginResult = false
        ..getErrorResult = 'context full';

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      expect(
        () => client.generateBegin(handles, [1, 2], const SamplingOptions()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('context full'),
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // generateNext
  // -------------------------------------------------------------------------

  group('generateNext', () {
    test('returns null when bindings return -1 (done)', () {
      // Default generateNextImpl returns -1.
      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      expect(client.generateNext(handles), isNull);
      expect(bindings.generateNextCalls, 1);
    });

    test('returns empty list when bindings return 0 (control token)', () {
      bindings.generateNextImpl = (ctx, buf, bufLen) => 0;

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      expect(client.generateNext(handles), const <int>[]);
    });

    test('returns raw bytes when bindings write bytes to buffer', () {
      bindings.generateNextImpl = (ctx, buf, bufLen) {
        final bytes = utf8.encode('Hi');
        final ptr = buf.cast<Uint8>();
        for (var i = 0; i < bytes.length; i++) {
          ptr[i] = bytes[i];
        }
        return bytes.length;
      };

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      expect(client.generateNext(handles), utf8.encode('Hi'));
    });

    test('retries with larger buffer when bindings return < -1', () {
      var callCount = 0;
      bindings.generateNextImpl = (ctx, buf, bufLen) {
        callCount++;
        if (callCount == 1) {
          // Signal that 10 bytes are needed.
          return -10;
        }
        // Second call with adequate buffer — write text.
        final bytes = utf8.encode('Hello!');
        final ptr = buf.cast<Uint8>();
        for (var i = 0; i < bytes.length; i++) {
          ptr[i] = bytes[i];
        }
        return bytes.length;
      };

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      final result = client.generateNext(handles);

      expect(result, utf8.encode('Hello!'));
      expect(bindings.generateNextCalls, 2);
    });

    test('returns null after retry when bindings still '
        'return negative (< -1)', () {
      // After retry the buffer has adequate size but bindings return -1 (done).
      var callCount = 0;
      bindings.generateNextImpl = (ctx, buf, bufLen) {
        callCount++;
        if (callCount == 1) return -5;
        return -1;
      };

      final client = _client();
      final handles = _handles(bindings, contextHandle: 3);

      // After retry n == -1, which falls into n <= 0 branch and n != 0 => null.
      expect(client.generateNext(handles), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // dispose
  // -------------------------------------------------------------------------

  group('dispose', () {
    test('frees context then model when contextHandle >= 0', () {
      final client = _client();
      final handles = _handles(bindings, modelHandle: 2, contextHandle: 7);

      client.dispose(handles);

      expect(bindings.freeContextCalls, 1);
      expect(bindings.lastFreeContextHandle, 7);
      expect(bindings.freeModelCalls, 1);
      expect(handles.contextHandle, -1);
    });

    test('skips freeContext when contextHandle is -1', () {
      final client = _client();
      final handles = _handles(bindings, modelHandle: 2);

      client.dispose(handles);

      expect(bindings.freeContextCalls, 0);
      expect(bindings.freeModelCalls, 1);
    });
  });
}
