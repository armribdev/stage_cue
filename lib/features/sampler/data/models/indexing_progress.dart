/// État de progression de l'indexation d'un dossier
class IndexingProgress {
  final String path;
  final int current;
  final int total;
  final bool isComplete;
  final String? error;

  IndexingProgress({
    required this.path,
    required this.current,
    required this.total,
    this.isComplete = false,
    this.error,
  });

  double get progress => total > 0 ? current / total : 0.0;

  IndexingProgress copyWith({
    String? path,
    int? current,
    int? total,
    bool? isComplete,
    String? error,
  }) {
    return IndexingProgress(
      path: path ?? this.path,
      current: current ?? this.current,
      total: total ?? this.total,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }
}

