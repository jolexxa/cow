import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';
import 'package:test/test.dart';

void main() {
  group('ToolRegistry', () {
    ToolDefinition definition(String name) => ToolDefinition(
      name: name,
      description: 'tool $name',
      parameters: const {},
    );

    test('definitions exposes registered tools in order', () {
      final registry = ToolRegistry()
        ..register(definition('a'), (_) => 'A')
        ..register(definition('b'), (_) => 'B');

      expect(registry.definitions.map((d) => d.name), ['a', 'b']);
    });

    test('register rejects duplicate tool names', () {
      final registry = ToolRegistry()..register(definition('dup'), (_) => 'ok');

      expect(
        () => registry.register(definition('dup'), (_) => 'nope'),
        throwsArgumentError,
      );
    });

    test('executeAll runs in parallel but preserves call ordering', () async {
      final registry = ToolRegistry()
        ..register(
          definition('slow'),
          (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return 'slow';
          },
        )
        ..register(
          definition('fast'),
          (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            return 'fast';
          },
        );

      final results = await registry.executeAll(const [
        ToolCall(id: '1', name: 'slow', arguments: {}),
        ToolCall(id: '2', name: 'fast', arguments: {}),
      ]);

      expect(results.map((r) => r.toolCallId), ['1', '2']);
      expect(results.map((r) => r.content), ['slow', 'fast']);
    });

    test('executeAll captures handler exceptions as error results', () async {
      final registry = ToolRegistry()
        ..register(definition('boom'), (_) => throw StateError('bad'));

      final results = await registry.executeAll(const [
        ToolCall(id: '1', name: 'boom', arguments: {}),
      ]);

      final result = results.single;
      expect(result.isError, isTrue);
      expect(result.errorMessage, contains('StateError'));
    });

    test('executeAll returns an error when the tool is missing', () async {
      final registry = ToolRegistry();

      final results = await registry.executeAll(const [
        ToolCall(id: '1', name: 'missing', arguments: {}),
      ]);

      final result = results.single;
      expect(result.isError, isTrue);
      expect(result.errorMessage, contains('missing'));
    });
  });
}
