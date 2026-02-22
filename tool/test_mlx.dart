// To run:
// dart tool/test_mlx.dart

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final code = await runCommand(
    '${repoRoot().path}/packages/cow_mlx/test.sh',
    args,
  );
  exitCode = code;
}
