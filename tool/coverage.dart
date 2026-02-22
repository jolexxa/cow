// To run:
// dart tool/coverage.dart             # all coverage-tracked packages
// dart tool/coverage.dart cow_brain   # just cow_brain

import 'dart:io';

import 'src/helpers.dart';

Future<void> main(List<String> args) async {
  final target = args.firstOrNull;

  final results = <String, ({int hit, int found, double pct})>{};

  final ok = await runOnPackages(coveragePackages, target, (pkg) async {
    final root = repoRoot().path;
    final pkgDir = '$root/$pkg';
    final name = pkg.split('/').last;

    if (!Directory('$pkgDir/test').existsSync()) {
      stdout.writeln('=== $name: no test/ directory, skipping ===');
      return true;
    }

    stdout.writeln('=== Coverage: $name ===');

    // Clean previous coverage.
    final coverageDir = Directory('$pkgDir/coverage');
    if (coverageDir.existsSync()) {
      coverageDir.deleteSync(recursive: true);
    }

    // Run tests with coverage.
    var code = await runCommand(
        'dart',
        [
          'test',
          '--coverage=coverage',
        ],
        workingDirectory: pkgDir);
    if (code != 0) return false;

    // Format coverage to lcov (--check-ignore respects coverage:ignore).
    code = await runCommand(
        'dart',
        [
          'pub',
          'global',
          'run',
          'coverage:format_coverage',
          '--lcov',
          '--in=coverage',
          '--out=coverage/lcov.info',
          '--report-on=lib',
          '--check-ignore',
          '--ignore-files=**/*.g.dart',
        ],
        workingDirectory: pkgDir);
    if (code != 0) return false;

    // Parse lcov.info ourselves for accurate numbers.
    final lcovFile = File('$pkgDir/coverage/lcov.info');
    if (!lcovFile.existsSync()) {
      stderr.writeln('  lcov.info not found');
      return false;
    }

    final summary = _parseLcov(lcovFile);
    results[name] = summary;

    final pctStr = summary.pct.toStringAsFixed(1);
    stdout.writeln(
      '  ${summary.hit}/${summary.found} lines covered ($pctStr%)',
    );

    if (summary.found > 0 && summary.hit < summary.found) {
      // Print uncovered files for quick debugging.
      final uncovered = _uncoveredFiles(lcovFile);
      for (final entry in uncovered) {
        stdout.writeln('    ${entry.file}: ${entry.missed} lines uncovered');
      }
    }

    // Generate coverage badge SVG.
    code = await runCommand(
        'dart', ['run', 'test_coverage_badge', '--file', 'coverage/lcov.info'],
        workingDirectory: pkgDir);
    if (code != 0) {
      stderr.writeln('  Badge generation failed');
    }

    stdout.writeln('');
    return true;
  });

  if (!ok) {
    exitCode = 1;
    return;
  }

  // Print summary table.
  stdout.writeln('========================================');
  stdout.writeln('  Coverage Summary');
  stdout.writeln('========================================');

  var allHit = 0;
  var allFound = 0;

  for (final entry in results.entries) {
    final r = entry.value;
    allHit += r.hit;
    allFound += r.found;
    final pctStr = r.pct.toStringAsFixed(1);
    final status = r.hit == r.found ? 'OK' : 'FAIL';
    stdout.writeln(
      '  ${entry.key.padRight(24)} ${r.hit}/${r.found} ($pctStr%) $status',
    );
  }

  if (allFound > 0) {
    final totalPct = allHit / allFound * 100;
    stdout.writeln('  ${'TOTAL'.padRight(24)} '
        '$allHit/$allFound (${totalPct.toStringAsFixed(1)}%)');
  }
  stdout.writeln('========================================');

  // Enforce 100% coverage.
  final failing = results.entries
      .where((e) => e.value.found > 0 && e.value.hit < e.value.found)
      .toList();

  if (failing.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln('Coverage < 100% for:');
    for (final e in failing) {
      stderr.writeln(
        '  ${e.key}: ${e.value.pct.toStringAsFixed(1)}%',
      );
    }
    exitCode = 1;
  } else {
    stdout.writeln('All coverage checks passed (100%).');
  }
}

/// Parse an lcov.info file and return total hit/found line counts.
({int hit, int found, double pct}) _parseLcov(File lcovFile) {
  var hit = 0;
  var found = 0;

  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    } else if (line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    }
  }

  final pct = found > 0 ? hit / found * 100 : 100.0;
  return (hit: hit, found: found, pct: pct);
}

/// Return per-file uncovered line counts from an lcov.info file.
List<({String file, int missed})> _uncoveredFiles(File lcovFile) {
  final results = <({String file, int missed})>[];
  String? currentFile;
  var fileHit = 0;
  var fileFound = 0;

  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      // Shorten to just the lib-relative path.
      final libIdx = currentFile.indexOf('lib/');
      if (libIdx >= 0) currentFile = currentFile.substring(libIdx);
      fileHit = 0;
      fileFound = 0;
    } else if (line.startsWith('LH:')) {
      fileHit = int.parse(line.substring(3));
    } else if (line.startsWith('LF:')) {
      fileFound = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      if (currentFile != null && fileHit < fileFound) {
        results.add((file: currentFile, missed: fileFound - fileHit));
      }
      currentFile = null;
    }
  }

  results.sort((a, b) => b.missed.compareTo(a.missed));
  return results;
}
