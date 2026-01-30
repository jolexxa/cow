import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

const _macosArm64AssetDir =
    'assets/native/macos/arm64/llama-b7818-bin-macos-arm64';

const _requiredLibraries = [
  'libllama.0.dylib',
  'libggml.0.dylib',
  'libggml-cpu.0.dylib',
  'libggml-blas.0.dylib',
  'libggml-metal.0.dylib',
  'libggml-rpc.0.dylib',
  'libggml-base.0.dylib',
];

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    if (targetOS != OS.macOS || targetArch != Architecture.arm64) {
      throw BuildError(
        message:
            'llama_cpp_dart only bundles prebuilt macOS arm64 binaries for '
            'now. Target was $targetOS/$targetArch. Add the appropriate '
            'binaries under assets/native and update hook/build.dart.',
      );
    }

    final packageRootDir = Directory.fromUri(input.packageRoot);
    final sourceDir = Directory(
      p.join(packageRootDir.path, _macosArm64AssetDir),
    );
    if (!sourceDir.existsSync()) {
      throw BuildError(
        message:
            'Missing prebuilt llama.cpp binaries at '
            '${sourceDir.path}.',
      );
    }

    final outputDir = Directory.fromUri(input.outputDirectoryShared);
    for (final libName in _requiredLibraries) {
      final sourcePath = p.join(sourceDir.path, libName);
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        throw BuildError(message: 'Missing required dylib: $sourcePath');
      }

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
