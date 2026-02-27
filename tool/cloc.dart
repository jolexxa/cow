// To run:
// dart tool/cloc.dart             # by-package Dart breakdown (default)
// dart tool/cloc.dart --tests     # include test/

import 'dart:convert';
import 'dart:io';

import 'src/helpers.dart';

final _excludeDirsBase = [
  'external',
  '.dart_tool',
  '.build',
  '.fvm',
  'coverage',
  'build',
  'third_party',
  '.pub-cache',
  '.idea',
  '.claude',
  // Exclude FFI binding packages (mostly generated code).
  ...ffigenPackages.map((p) => p.split('/').last),
];

/// All countable top-level directories (packages + tool), minus FFI packages.
final _targets = [
  ...allDartPackages.where((p) => !ffigenPackages.contains(p)),
  'tool',
];

Future<void> main(List<String> args) async {
  final root = repoRoot().path;
  final includeTests = args.contains('--tests');
  final excludeDirs = [
    ..._excludeDirsBase,
    if (!includeTests) 'test',
  ];
  final excludeArg = '--exclude-dir=${excludeDirs.join(',')}';
  const excludeExtArg = '--exclude-ext=profraw,lock';

  // Per-package breakdown: run cloc --json on each target, Dart only.
  final results = <String, _PkgResult>{};
  var totalFiles = 0;
  var totalBlank = 0;
  var totalComment = 0;
  var totalCode = 0;

  for (final target in _targets) {
    final dir = '$root/$target';
    if (!Directory(dir).existsSync()) continue;

    final proc = await Process.run(
      'cloc',
      [
        dir,
        '--json',
        '--vcs=git',
        '--include-lang=Dart',
        excludeArg,
        excludeExtArg,
      ],
    );

    if (proc.exitCode != 0) continue;

    try {
      final json = jsonDecode(proc.stdout as String) as Map<String, dynamic>;
      final dart = json['Dart'] as Map<String, dynamic>?;
      if (dart == null) continue;

      final r = _PkgResult(
        files: dart['nFiles'] as int,
        blank: dart['blank'] as int,
        comment: dart['comment'] as int,
        code: dart['code'] as int,
      );
      results[target.split('/').last] = r;
      totalFiles += r.files;
      totalBlank += r.blank;
      totalComment += r.comment;
      totalCode += r.code;
    } on FormatException {
      continue;
    }
  }

  // Print table.
  const nameW = 22;
  const numW = 10;

  stdout.writeln(
    '${'Package'.padRight(nameW)}'
    '${'Files'.padLeft(numW)}'
    '${'Blank'.padLeft(numW)}'
    '${'Comment'.padLeft(numW)}'
    '${'Code'.padLeft(numW)}',
  );
  stdout.writeln('-' * (nameW + numW * 4));

  // Sort by code descending.
  final sorted = results.entries.toList()
    ..sort((a, b) => b.value.code.compareTo(a.value.code));

  for (final entry in sorted) {
    final r = entry.value;
    stdout.writeln(
      '${entry.key.padRight(nameW)}'
      '${r.files.toString().padLeft(numW)}'
      '${r.blank.toString().padLeft(numW)}'
      '${r.comment.toString().padLeft(numW)}'
      '${r.code.toString().padLeft(numW)}',
    );
  }

  stdout.writeln('-' * (nameW + numW * 4));
  stdout.writeln(
    '${'TOTAL'.padRight(nameW)}'
    '${totalFiles.toString().padLeft(numW)}'
    '${totalBlank.toString().padLeft(numW)}'
    '${totalComment.toString().padLeft(numW)}'
    '${totalCode.toString().padLeft(numW)}',
  );
}

class _PkgResult {
  _PkgResult({
    required this.files,
    required this.blank,
    required this.comment,
    required this.code,
  });

  final int files;
  final int blank;
  final int comment;
  final int code;
}
