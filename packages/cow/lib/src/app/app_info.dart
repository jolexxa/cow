import 'dart:io';
import 'dart:math';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/config_resolver.dart';
import 'package:cow/src/app/cow_config.dart';
import 'package:cow/src/app/cow_paths.dart';
import 'package:cow/src/platforms/os_platform.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:nocterm/nocterm.dart';

class AppInfo {
  const AppInfo({
    required this.platform,
    required this.toolRegistry,
    required this.modelProfile,
    required this.summaryModelProfile,
    required this.primaryOptions,
    required this.summaryOptions,
    required this.requiredProfilesPresent,
    required this.cowPaths,
    required this.modelServer,
    required this.primarySeed,
    required this.summarySeed,
    required this.systemPrompt,
    required this.summarySystemPrompt,
  });

  static const String executableName = 'cow';
  static const String packageName = 'cow';
  static const String description = 'An humble AI in your terminal.';

  static const int _summaryMaxTokens = 512;

  final ToolRegistry toolRegistry;
  final OSPlatform platform;
  final AppModelProfile modelProfile;
  final AppModelProfile summaryModelProfile;
  final BackendRuntimeOptions primaryOptions;
  final BackendRuntimeOptions summaryOptions;
  final bool requiredProfilesPresent;
  final CowPaths cowPaths;
  final ModelServer modelServer;
  final int primarySeed;
  final int summarySeed;
  final String systemPrompt;
  final String summarySystemPrompt;

  static Future<AppInfo> initialize({
    required OSPlatform platform,
  }) async {
    final cowPaths = CowPaths();
    Directory(cowPaths.cowDir).createSync(recursive: true);
    final config = CowConfig.fromFile(cowPaths.configFile);
    final resolved = ConfigResolver.resolve(config, platform: platform);
    final modelProfile = resolved.primary;
    final summaryModelProfile = resolved.lightweight;
    final toolRegistry = ToolRegistry()
      ..register(
        const ToolDefinition(
          name: 'date_time',
          description: 'Returns the current date/time in ISO 8601 format.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'required': <String>[],
          },
        ),
        (_) => DateTime.now().toIso8601String(),
      );

    final modelsDir = cowPaths.modelsDir;
    final requiredProfilesPresent =
        profileFilesPresent(modelProfile.downloadableModel, modelsDir) &&
        profileFilesPresent(
          summaryModelProfile.downloadableModel,
          modelsDir,
        );

    final rng = Random();
    final primarySeed = rng.nextInt(1 << 31);
    final summarySeed = rng.nextInt(1 << 31);

    final primaryOptions = platform.buildRuntimeOptions(
      profile: modelProfile,
      cowPaths: cowPaths,
      seed: primarySeed,
    );

    final summaryOptions = platform.buildRuntimeOptions(
      profile: summaryModelProfile,
      cowPaths: cowPaths,
      seed: summarySeed,
      maxOutputTokensOverride: _summaryMaxTokens,
    );

    final modelServer = await ModelServer.spawn();

    return AppInfo(
      platform: platform,
      toolRegistry: toolRegistry,
      modelProfile: modelProfile,
      summaryModelProfile: summaryModelProfile,
      primaryOptions: primaryOptions,
      summaryOptions: summaryOptions,
      requiredProfilesPresent: requiredProfilesPresent,
      cowPaths: cowPaths,
      modelServer: modelServer,
      primarySeed: primarySeed,
      summarySeed: summarySeed,
      systemPrompt:
          'You are Cow, a helpful AI assistant. '
          'Feel free to spice things up by using cow-inspired jargon '
          'and emoji. English only.',
      summarySystemPrompt:
          'You are a summarization assistant. '
          'Summarize the given text as concisely as possible.',
    );
  }

  static AppInfo of(BuildContext context) => Provider.of<AppInfo>(context);
}
