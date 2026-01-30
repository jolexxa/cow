import 'package:meta/meta.dart';

@immutable
sealed class StartupEvent {
  const StartupEvent();
}

class AppStartupStarted extends StartupEvent {
  const AppStartupStarted();
}

class AppStartupCancelled extends StartupEvent {
  const AppStartupCancelled();
}

class AppStartupContinue extends StartupEvent {
  const AppStartupContinue();
}
