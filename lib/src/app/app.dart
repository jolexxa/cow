import 'dart:async';
import 'dart:io';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_info.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/app/app_theme.dart';
import 'package:cow/src/features/chat/chat.dart';
import 'package:cow/src/features/startup/startup.dart';
import 'package:io/io.dart';
import 'package:nocterm/nocterm.dart';

Future<int> runCowApp(List<String> args) async {
  final code = await runZonedGuarded(
    () async {
      final appInfo = await AppInfo.initialize(
        modelProfile: AppModelProfiles.qwen3,
        summaryModelProfile: AppModelProfiles.qwen25_3b,
      );

      await runApp(
        Provider<AppInfo>(
          value: appInfo,
          child: const CowApp(),
        ),
      );

      return ExitCode.success.code;
    },
    (error, stack) {
      stderr
        ..writeln('Unhandled error: $error')
        ..writeln(stack);

      exit(ExitCode.software.code);
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
    return BlocProvider<StartupBloc>.create(
      create: (context) => StartupBloc(
        installProfiles: AppModelProfiles.defaultProfiles,
        cowPaths: AppInfo.of(context).cowPaths,
      ),
      child: const TuiTheme(
        data: appThemeBarnyard,
        child: AppStartupView(),
      ),
    );
  }
}
