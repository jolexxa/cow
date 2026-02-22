import 'dart:async';
import 'dart:io';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_info.dart';
import 'package:cow/src/app/app_theme.dart';
import 'package:cow/src/app/session_log.dart';
import 'package:cow/src/features/chat/chat.dart';
import 'package:cow/src/features/startup/startup.dart';
import 'package:cow/src/platforms/platform.dart';
import 'package:io/io.dart';
import 'package:nocterm/nocterm.dart';

Future<int> runCowApp(List<String> args, OSPlatform platform) async {
  final code = await runZonedGuarded(
    () async {
      final appInfo = await AppInfo.initialize(
        platform: platform,
      );

      final sessionLog = SessionLog(appInfo.cowPaths.sessionLogFile)
        ..header(
          backend: appInfo.primaryOptions.backend.name,
          modelId: appInfo.modelProfile.downloadableModel.id,
          primarySeed: appInfo.primarySeed,
          summarySeed: appInfo.summarySeed,
        );

      await runApp(
        Provider<SessionLog>(
          value: sessionLog,
          child: Provider<AppInfo>(
            value: appInfo,
            child: const CowApp(),
          ),
        ),
      );

      return ExitCode.success.code;
    },
    (error, stack) {
      stderr
        ..writeln('Unhandled error: $error')
        ..writeln(stack);

      platform.exit(ExitCode.software.code);
    },
  );

  return code ?? ExitCode.software.code;
}

class CowApp extends StatelessComponent {
  const CowApp({super.key});

  @override
  Component build(BuildContext context) {
    final appInfo = AppInfo.of(context);
    if (appInfo.requiredProfilesPresent) {
      return const TuiTheme(
        data: appThemeBarnyard,
        child: ChatPageView(),
      );
    }
    return BlocProvider<StartupCubit>.create(
      create: (context) => StartupCubit(
        installProfiles: [
          appInfo.modelProfile.downloadableModel,
          appInfo.summaryModelProfile.downloadableModel,
        ],
        cowPaths: AppInfo.of(context).cowPaths,
        logic: StartupLogic(),
      ),
      child: const TuiTheme(
        data: appThemeBarnyard,
        child: AppStartupView(),
      ),
    );
  }
}
