/// Progress state for model loading.
final class ModelLoadProgress {
  const ModelLoadProgress({
    required this.currentModelIndex,
    required this.totalModels,
    required this.currentProgress,
    required this.currentModelName,
  });

  /// 1-indexed for display.
  final int currentModelIndex;
  final int totalModels;

  /// 0.0-1.0 progress value.
  final double currentProgress;
  final String currentModelName;
}
