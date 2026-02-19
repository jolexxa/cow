// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

final class StreamChunk {
  const StreamChunk({
    required this.text,
    required this.tokenCountDelta,
  });

  final String text;
  final int tokenCountDelta;
}
