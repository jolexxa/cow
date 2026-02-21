// To run:
// dart tool/download_llama_assets.dart

import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _repoOwner = 'ggml-org';
const _repoName = 'llama.cpp';
const _tmpDirName = 'tmp';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'tag',
      abbr: 't',
      help:
          'llama.cpp release tag (ex: b7818). If omitted, try to infer from '
          'the git submodule.',
    );

  final parsed = parser.parse(args);
  final tagArg = parsed['tag'];
  final tag = tagArg is String && tagArg.isNotEmpty
      ? tagArg
      : await _resolveReleaseTag();

  final platform = _currentPlatform();
  final assetName = _assetName(tag, platform);
  final entryLibrary = _entryLibraryName(platform);
  final repoRoot = _repoRoot();
  final tmpRoot = Directory(p.join(repoRoot.path, 'tool', _tmpDirName));
  final runDir = Directory(
    p.join(
      tmpRoot.path,
      'llama_assets_${DateTime.now().millisecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);

  try {
    final downloadPath = p.join(runDir.path, assetName);
    final url = Uri.parse(
      'https://github.com/$_repoOwner/$_repoName/releases/download/'
      '$tag/$assetName',
    );
    stdout.writeln('Downloading $url');
    await _downloadFile(url, downloadPath);

    stdout.writeln('Extracting $assetName');
    await _runProcess('tar', ['-xzf', downloadPath, '-C', runDir.path]);

    final extractedRoot = _findExtractedRoot(runDir, entryLibrary);
    stdout.writeln('Copying libraries from ${extractedRoot.path}');

    final destDir = Directory(
      p.join(
        repoRoot.path,
        'packages',
        'llama_cpp_dart',
        'assets',
        'native',
        platform.assetFolder,
        platform.archFolder,
      ),
    )..createSync(recursive: true);

    final libs = _findAllNativeLibraries(extractedRoot, platform);
    for (final sourceFile in libs) {
      final name = p.basename(sourceFile.path);
      final destPath = p.join(destDir.path, name);
      sourceFile.copySync(destPath);
    }

    final licenseFile = File(p.join(extractedRoot.path, 'LICENSE'));
    if (licenseFile.existsSync()) {
      licenseFile.copySync(p.join(destDir.path, 'LICENSE'));
    }

    stdout.writeln('Copied ${libs.length} libraries into ${destDir.path}');
  } finally {
    if (runDir.existsSync()) {
      runDir.deleteSync(recursive: true);
    }
  }
}

Directory _repoRoot() {
  final scriptDir = File.fromUri(Platform.script).parent;
  return scriptDir.parent;
}

Future<String> _resolveReleaseTag() async {
  final llamaDir = p.join(
    _repoRoot().path,
    'packages',
    'llama_cpp_dart',
    'third_party',
    'llama.cpp',
  );
  try {
    final exact = await _runProcess('git', [
      '-C',
      llamaDir,
      'describe',
      '--tags',
      '--exact-match',
    ]);
    final stdoutText = exact.stdout is String ? exact.stdout as String : '';
    final tag = stdoutText.trim();
    if (tag.isNotEmpty) {
      return tag;
    }
  } on ProcessException catch (_) {
    // Ignore and fall through to error below.
  }

  stderr.writeln(
    'Could not infer a llama.cpp release tag from the submodule. '
    'Pass one explicitly with --tag.',
  );
  exit(1);
}

PlatformTarget _currentPlatform() {
  final abi = Abi.current();
  if (Platform.isMacOS) {
    if (abi != Abi.macosArm64) {
      throw UnsupportedError('Unsupported macOS architecture: $abi');
    }
    return PlatformTarget.macOSArm64();
  }
  if (Platform.isLinux) {
    if (abi != Abi.linuxX64) {
      throw UnsupportedError('Unsupported Linux architecture: $abi');
    }
    return PlatformTarget.linuxX64();
  }
  throw UnsupportedError(
    'Unsupported host platform: ${Platform.operatingSystem}',
  );
}

String _assetName(String tag, PlatformTarget platform) {
  if (platform.isMacOS) {
    return 'llama-$tag-bin-macos-arm64.tar.gz';
  }
  return 'llama-$tag-bin-ubuntu-vulkan-x64.tar.gz';
}

String _entryLibraryName(PlatformTarget platform) {
  if (platform.isMacOS) return 'libllama.0.dylib';
  return 'libllama.so';
}

Future<void> _downloadFile(Uri url, String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to download $url (status ${response.statusCode})',
      );
    }
    final file = File(path);
    final sink = file.openWrite();
    await response.pipe(sink);
  } finally {
    client.close();
  }
}

Directory _findExtractedRoot(Directory runDir, String entryLibrary) {
  final candidates = runDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.basename(file.path) == entryLibrary)
      .toList();
  if (candidates.isEmpty) {
    stderr.writeln('Could not find $entryLibrary in extracted archive.');
    exit(1);
  }
  return candidates.first.parent;
}

List<File> _findAllNativeLibraries(Directory root, PlatformTarget platform) {
  bool isNativeLib(String name) {
    if (platform.isMacOS) return name.endsWith('.dylib');
    return name.contains('.so');
  }

  return root
      .listSync()
      .whereType<File>()
      .where((f) => isNativeLib(p.basename(f.path)))
      .toList();
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    final stderrText = result.stderr is String ? result.stderr as String : '';
    throw ProcessException(
      executable,
      arguments,
      'Command failed with exit code ${result.exitCode}: $stderrText',
      result.exitCode,
    );
  }
  return result;
}

class PlatformTarget {
  PlatformTarget._({
    required this.assetFolder,
    required this.archFolder,
    required this.isMacOS,
  });

  factory PlatformTarget.macOSArm64() {
    return PlatformTarget._(
      assetFolder: 'macos',
      archFolder: 'arm64',
      isMacOS: true,
    );
  }

  factory PlatformTarget.linuxX64() {
    return PlatformTarget._(
      assetFolder: 'linux',
      archFolder: 'x64',
      isMacOS: false,
    );
  }

  final String assetFolder;
  final String archFolder;
  final bool isMacOS;
}
