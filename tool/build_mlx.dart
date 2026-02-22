// To run:
// dart tool/build_mlx.dart [args...]

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final code = await runCommand(
    '${repoRoot().path}/packages/cow_mlx/build.sh',
    args,
  );
  exitCode = code;
}
