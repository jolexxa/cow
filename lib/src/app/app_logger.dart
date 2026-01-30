import 'package:logger/logger.dart' as log;

class AppLogger {
  AppLogger({log.Logger? logger, log.Level level = log.Level.info})
    : _level = level {
    if (logger != null) {
      _logger = logger;
    } else {
      _filter = _AppLogFilter(level);
      _logger = log.Logger(filter: _filter);
    }
  }

  late final log.Logger _logger;
  _AppLogFilter? _filter;
  log.Level _level;

  log.Level get level => _level;
  set level(log.Level value) {
    _level = value;
    _filter?.level = value;
  }

  void info(String message) => _logger.i(message);
  void err(String message) => _logger.e(message);
  void detail(String message) => _logger.t(message);

  AppLogProgress progress(String message) {
    _logger.i(message);
    return AppLogProgress(_logger, message);
  }
}

class AppLogProgress {
  AppLogProgress(this._logger, this._message);

  final log.Logger _logger;
  final String _message;

  void complete([String? message]) => _logger.i(message ?? _message);
  void fail([String? message]) => _logger.e(message ?? _message);
}

class _AppLogFilter extends log.LogFilter {
  _AppLogFilter(this.level);

  @override
  log.Level? level;

  @override
  bool shouldLog(log.LogEvent event) {
    final filterLevel = level;
    if (filterLevel == null) {
      return true;
    }
    return event.level.index >= filterLevel.index;
  }
}
