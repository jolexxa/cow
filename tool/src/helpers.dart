import 'dart:io';

/// All Dart packages in the monorepo.
const allDartPackages = [
  'packages/cow',
  'packages/collections',
  'packages/blocterm',
  'packages/cow_brain',
  'packages/cow_model_manager',
  'packages/llama_cpp_dart',
  'packages/logic_blocks',
  'packages/mlx_dart',
];

/// Packages that require coverage tracking.
const coveragePackages = [
  'packages/blocterm',
  'packages/cow_brain',
  'packages/cow_model_manager',
  'packages/logic_blocks',
];

/// Packages that use build_runner for code generation.
const buildRunnerPackages = ['packages/cow', 'packages/cow_brain'];

/// Packages that use dart ffigen for native bindings generation.
const ffigenPackages = ['packages/mlx_dart', 'packages/llama_cpp_dart'];

/// Dart packages that have tests (excludes mlx_dart which is Swift-only).
const testablePackages = [
  'packages/cow',
  'packages/collections',
  'packages/blocterm',
  'packages/cow_brain',
  'packages/cow_model_manager',
  'packages/llama_cpp_dart',
  'packages/logic_blocks',
];

/// Returns the repository root directory.
Directory repoRoot() {
  // Platform.script points to the main script in tool/, so go up one level.
  return File.fromUri(Platform.script).parent.parent;
}

/// Resolves a package target name to a relative path from repo root.
///
/// Accepts both `"cow_brain"` and `"packages/cow_brain"`.
/// Returns `null` if the package directory doesn't exist.
String? resolvePackage(String target) {
  final root = repoRoot().path;
  final asPackagesPath = 'packages/$target';

  if (Directory('$root/$asPackagesPath').existsSync()) {
    return asPackagesPath;
  }
  if (Directory('$root/$target').existsSync()) {
    return target;
  }
  return null;
}

/// Runs a command with inherited stdio (live output).
/// Returns the exit code.
Future<int> runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

/// Runs an [action] on a single target package or all packages in the list.
///
/// If [target] is non-null, resolves it and runs [action] on that one package.
/// Otherwise runs [action] on every package, tracking failures.
///
/// [action] receives the package path (e.g. `"packages/cow_brain"`) and should
/// return `true` on success, `false` on failure.
///
/// Returns `true` if everything passed.
Future<bool> runOnPackages(
  List<String> packages,
  String? target,
  Future<bool> Function(String pkg) action,
) async {
  if (target != null) {
    final resolved = resolvePackage(target);
    if (resolved == null) {
      stderr.writeln('Unknown package: $target');
      return false;
    }
    return action(resolved);
  }

  final failed = <String>[];
  for (final pkg in packages) {
    if (!await action(pkg)) {
      failed.add(pkg);
    }
  }

  if (failed.isNotEmpty) {
    stderr.writeln('FAILED:');
    for (final pkg in failed) {
      stderr.writeln('  - $pkg');
    }
    return false;
  }

  return true;
}
