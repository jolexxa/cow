import 'dart:ffi';
import 'dart:io';

import 'package:cow/src/app/app.dart';
import 'package:ffi/ffi.dart';

Future<void> main(List<String> args) async {
  // We have to redirect native standard error output to a file because
  // native libraries which write to standard error (like llama_cpp) will ruin
  // our beautiful terminal output.
  // We can't tell llama_cpp to be quiet, either, because it has a global
  // logging callback. Since we are using it from multiple isolates to run
  // multiple models at once, we can't share native handles across isolates and
  // it crashes. So the only option is to redirect native stderr via
  // mac/linux system calls.
  _silenceNativeStderr();
  final exitCode = await runCowApp(args);
  await _flushThenExit(exitCode);
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([
    stdout.close(),
    stderr.close(),
  ]).then<void>((_) => exit(status));
}

void _silenceNativeStderr() {
  final libc = _openLibC();
  if (libc == null) {
    return;
  }
  const oWrOnly = 0x0001;
  const oCreat = 0x0200;
  const oAppend = 0x0008;
  const mode = 0x1A4; // 0644

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

  final targetPtr = '/dev/null'.toNativeUtf8();
  final fd = open(targetPtr, oWrOnly | oCreat | oAppend, mode);
  calloc.free(targetPtr);
  if (fd < 0) {
    return;
  }
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
