import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    // MLX is macOS ARM64 only.
    if (targetOS != OS.macOS || targetArch != Architecture.arm64) {
      // Silently skip — MLX is not available on this platform.
      // The app detects MLX availability at runtime.
      return;
    }

    final packageRootDir = Directory.fromUri(input.packageRoot);

    // Collect dylibs from all candidate directories.
    // Priority: assets dir first, then cow_mlx build outputs.
    final libs = <File>[];
    final candidateDirs = [
      // 1. Prebuilt assets (matches llama_cpp_dart pattern).
      p.join(packageRootDir.path, 'assets', 'native', 'macos', 'arm64'),
      // 2. cow_mlx xcodebuild output (required for Metal shaders).
      p.join(
        packageRootDir.path,
        '..',
        'cow_mlx',
        '.build',
        'xcode',
        'Build',
        'Products',
        'Release',
      ),
      // 3. cow_mlx SwiftPM release build output.
      p.join(packageRootDir.path, '..', 'cow_mlx', '.build', 'release'),
      // 4. cow_mlx SwiftPM debug build output (dev workflow).
      p.join(packageRootDir.path, '..', 'cow_mlx', '.build', 'debug'),
    ];

    for (final dirPath in candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      final dylibs = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).endsWith('.dylib'))
          .toList();
      if (dylibs.isNotEmpty) {
        libs.addAll(dylibs);
        break; // Use the first directory that has dylibs.
      }
    }

    if (libs.isEmpty) {
      // No dylibs found anywhere — skip silently.
      return;
    }

    final outputDir = Directory.fromUri(input.outputDirectoryShared);
    for (final sourceFile in libs) {
      final libName = p.basename(sourceFile.path);
      final resolvedSourcePath = sourceFile.resolveSymbolicLinksSync();
      final outputPath = p.join(outputDir.path, libName);
      File(resolvedSourcePath).copySync(outputPath);

      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: libName,
          linkMode: DynamicLoadingBundled(),
          file: File(outputPath).uri,
        ),
      );
    }
  });
}
