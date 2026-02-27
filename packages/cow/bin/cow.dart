import 'dart:io';

import 'package:cow/src/app/app.dart';
import 'package:cow/src/native_stderr.dart';
import 'package:cow/src/platforms/os_platform.dart';

Future<void> main(List<String> args) async {
  final platform = OSPlatform.current();

  // We have to redirect native standard error output to a file because
  // native libraries which write to standard error (like llama_cpp) will ruin
  // our beautiful terminal output.
  // We can't tell llama_cpp to be quiet, either, because it has a global
  // logging callback. Since we are using it from multiple isolates to run
  // multiple models at once, we can't share native handles across isolates and
  // it crashes. So the only option is to redirect native stderr via
  // mac/linux system calls.
  final debug = args.contains('--debug');
  redirectNativeStderr(platform, debug: debug);

  final appArgs = args.where((a) => a != '--debug').toList();
  final exitCode = await runCowApp(appArgs, platform);
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
