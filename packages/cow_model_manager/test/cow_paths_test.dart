import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:test/test.dart';

void main() {
  test('uses explicit home directory when provided', () {
    const homeDir = '/tmp/cow-home';
    final profile = ModelProfileSpec(
      id: 'alpha',
      supportsReasoning: false,
      files: const [
        ModelFileSpec(
          url: 'https://example.com/model.bin',
          fileName: 'model.bin',
        ),
      ],
      entrypointFileName: 'model.bin',
    );

    final paths = CowPaths(homeDir: homeDir);

    expect(paths.homeDir, homeDir);
    expect(paths.cowDir, p.join(homeDir, '.cow'));
    expect(paths.modelsDir, p.join(homeDir, '.cow', 'models'));
    expect(paths.modelDir(profile), p.join(homeDir, '.cow', 'models', 'alpha'));
    expect(
      paths.modelFilePath(profile, profile.files.first),
      p.join(homeDir, '.cow', 'models', 'alpha', 'model.bin'),
    );
    expect(
      paths.modelEntrypoint(profile),
      p.join(homeDir, '.cow', 'models', 'alpha', 'model.bin'),
    );
  });

  test('resolves home directory from HOME', () {
    final paths = CowPaths(
      platform: FakePlatform(environment: const {'HOME': '/home/tester'}),
    );

    expect(paths.homeDir, '/home/tester');
  });

  test('falls back to USERPROFILE when HOME is missing', () {
    final paths = CowPaths(
      platform: FakePlatform(
        environment: const {'USERPROFILE': r'C:\Users\cow'},
      ),
    );

    expect(paths.homeDir, r'C:\Users\cow');
  });

  test('throws when no home directory can be resolved', () {
    expect(
      () => CowPaths(platform: FakePlatform(environment: const {})),
      throwsA(isA<StateError>()),
    );
  });
}
