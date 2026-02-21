sealed class StartupOutput {
  const StartupOutput();
}

final class StateUpdated extends StartupOutput {
  const StateUpdated();
}

final class CheckFilesRequested extends StartupOutput {
  const CheckFilesRequested();
}

final class StartDownloadRequested extends StartupOutput {
  const StartDownloadRequested();
}

final class CancelDownloadRequested extends StartupOutput {
  const CancelDownloadRequested();
}
