import 'dart:convert';
import 'dart:io';

import 'package:cow_brain/cow_brain.dart';

/// What kind of streaming content we're currently writing.
enum _OutputMode { none, thinking, assistant }

/// Session logger that writes a clean transcript to a file.
///
/// Uses synchronous file I/O so every write hits disk immediately.
/// The log file is overwritten each time the app starts, so it only
/// contains the current session. Useful for reproducing crashes.
///
/// Streaming text deltas go through a chunked UTF-8 encoder that
/// carries lone high surrogates across calls — supplementary-plane
/// emoji split across deltas encode correctly instead of producing
/// U+FFFD replacement characters.
class SessionLog {
  SessionLog(String path)
    : _file = File(path).openSync(mode: FileMode.write);

  final RandomAccessFile _file;

  /// Chunked UTF-8 encoder that handles surrogate pairs split across
  /// successive `add()` calls. Bytes are written to the file immediately.
  late final StringConversionSink _deltaSink =
      utf8.encoder.startChunkedConversion(_FileByteSink(_file));

  _OutputMode _mode = _OutputMode.none;
  bool _seenFirstToken = false;
  DateTime? _turnStartTime;

  // ── Core writing ─────────────────────────────────────────────────

  void _write(String line) {
    final ts = DateTime.now().toIso8601String();
    _file.writeStringSync('[$ts] $line\n');
  }

  /// Terminate any in-progress streaming block with a newline so the
  /// next timestamped line starts on its own line.
  void _ensureBlockEnd() {
    if (_mode != _OutputMode.none) {
      _file.writeStringSync('\n');
      _mode = _OutputMode.none;
    }
  }

  void _logTtft() {
    if (_seenFirstToken) return;
    _seenFirstToken = true;
    final elapsed = _turnStartTime != null
        ? DateTime.now().difference(_turnStartTime!).inMilliseconds
        : 0;
    _ensureBlockEnd();
    _write('TTFT ${_fmtMs(elapsed)}');
  }

  // ── Session header ───────────────────────────────────────────────

  void header({
    required String backend,
    required String modelId,
    required int primarySeed,
    required int summarySeed,
  }) {
    _write('--- session start ---');
    _write('backend: $backend');
    _write('model: $modelId');
    _write('primarySeed: $primarySeed');
    _write('summarySeed: $summarySeed');
  }

  // ── Turn lifecycle ───────────────────────────────────────────────

  void userMessage(String text) {
    _ensureBlockEnd();
    _write('USER: $text');
  }

  void turnStart() {
    _seenFirstToken = false;
    _mode = _OutputMode.none;
    _turnStartTime = DateTime.now();
  }

  void turnError(String error) {
    _ensureBlockEnd();
    _write('ERROR: $error');
  }

  void isolateDied(String details) {
    _ensureBlockEnd();
    _write('CRASH: isolate died — $details');
  }

  void close() {
    _ensureBlockEnd();
    _deltaSink.close();
    _file.closeSync();
  }

  // ── Agent event dispatcher ───────────────────────────────────────

  void logAgentEvent(AgentEvent event) {
    switch (event) {
      case AgentTextDelta():
        _onTextDelta(event);
      case AgentReasoningDelta():
        _onReasoningDelta(event);
      case AgentToolCalls():
        _onToolCalls(event);
      case AgentToolResult():
        _onToolResult(event);
      case AgentTurnFinished():
        _onTurnFinished(event);
      case AgentError():
        _onError(event);
      default:
        break;
    }
  }

  void _onTextDelta(AgentTextDelta e) {
    if (e.text.isEmpty) return;
    _logTtft();

    if (_mode != _OutputMode.assistant) {
      _ensureBlockEnd();
      _file.writeStringSync('ASSISTANT: ');
      _mode = _OutputMode.assistant;
    }

    _deltaSink.add(e.text);
  }

  void _onReasoningDelta(AgentReasoningDelta e) {
    if (e.text.isEmpty) return;
    _logTtft();

    if (_mode != _OutputMode.thinking) {
      _ensureBlockEnd();
      _file.writeStringSync('THINKING: ');
      _mode = _OutputMode.thinking;
    }

    _deltaSink.add(e.text);
  }

  void _onToolCalls(AgentToolCalls e) {
    _ensureBlockEnd();
    for (final call in e.calls) {
      final args = jsonEncode(call.arguments);
      _write('TOOL: ${call.name}($args)');
    }
  }

  void _onToolResult(AgentToolResult e) {
    final r = e.result;
    if (r.isError) {
      final msg = r.errorMessage ?? r.content;
      _write('TOOL: ${r.name} x $msg');
    } else {
      _write('TOOL: ${r.name} -> ${r.content}');
    }
  }

  void _onTurnFinished(AgentTurnFinished e) {
    _ensureBlockEnd();
    final elapsed = _turnStartTime != null
        ? DateTime.now().difference(_turnStartTime!).inMilliseconds
        : 0;
    _write('COMPLETED ${_fmtMs(elapsed)}');
  }

  void _onError(AgentError e) {
    _ensureBlockEnd();
    _write('ERROR: ${e.error}');
  }

  // ── Helpers ──────────────────────────────────────────────────────

  static String _fmtMs(int ms) {
    if (ms < 1000) return '${ms}ms';
    final secs = ms / 1000;
    return '${secs.toStringAsFixed(2)}s';
  }
}

/// Sink that writes byte chunks directly to a [RandomAccessFile].
final class _FileByteSink implements Sink<List<int>> {
  _FileByteSink(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> data) => _file.writeFromSync(data);

  @override
  void close() {}
}
