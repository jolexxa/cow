import 'dart:ffi';
import 'dart:io';

import 'package:cow/src/platforms/os_platform.dart';
import 'package:ffi/ffi.dart';

/// Redirects native stderr (fd 2) so that noisy native libraries (llama.cpp)
/// don't pollute terminal / test output.
///
/// In [debug] mode, output is written to `cow_native.log` instead of being
/// discarded.
void redirectNativeStderr(OSPlatform platform, {bool debug = false}) {
  final libc = _openLibC();
  if (libc == null) return;

  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Int32),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  final dup2 = libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'dup2',
      );
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );

  final target = debug ? 'cow_native.log' : '/dev/null';
  final flags =
      platform.openFlagWriteOnly |
      platform.openFlagCreate |
      platform.openFlagTrunc;

  const mode = 0x1A4; // 0644
  final targetPtr = target.toNativeUtf8();
  final fd = open(targetPtr, flags, mode);
  calloc.free(targetPtr);

  if (fd < 0) return;
  dup2(fd, 2);
  close(fd);
}

DynamicLibrary? _openLibC() {
  try {
    if (Platform.isMacOS) {
      return DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libc.so.6');
    }
  } on Object catch (_) {}
  return null;
}
