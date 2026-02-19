import 'package:cow_brain/src/adapters/extractors/composite_tool_call_extractor.dart';
import 'package:cow_brain/src/adapters/tool_call_extractor.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('CompositeToolCallExtractor', () {
    test('uses first extractor that returns results', () {
      const composite = CompositeToolCallExtractor([
        _EmptyExtractor(),
        _FixedExtractor([
          ToolCall(id: 'a', name: 'search', arguments: {}),
        ]),
        _FixedExtractor([
          ToolCall(id: 'b', name: 'other', arguments: {}),
        ]),
      ]);

      final calls = composite.extract('anything');

      expect(calls, hasLength(1));
      expect(calls.single.id, 'a');
    });

    test('returns empty when no extractor matches', () {
      const composite = CompositeToolCallExtractor([
        _EmptyExtractor(),
        _EmptyExtractor(),
      ]);

      final calls = composite.extract('anything');
      expect(calls, isEmpty);
    });
  });
}

final class _EmptyExtractor implements ToolCallExtractor {
  const _EmptyExtractor();

  @override
  List<ToolCall> extract(String text) => const [];
}

final class _FixedExtractor implements ToolCallExtractor {
  const _FixedExtractor(this._calls);
  final List<ToolCall> _calls;

  @override
  List<ToolCall> extract(String text) => _calls;
}
