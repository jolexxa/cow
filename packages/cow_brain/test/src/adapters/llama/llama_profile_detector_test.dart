import 'package:cow_brain/src/adapters/llama/llama_profile_detector.dart';
import 'package:cow_brain/src/adapters/llama/llama_profiles.dart';
import 'package:test/test.dart';

void main() {
  const detector = LlamaProfileDetector();

  group('LlamaProfileDetector', () {
    test('detects ChatML/Qwen from im_start token', () {
      const template =
          '{% for msg in messages %} '
          '<|im_start|>{{ msg.role }}\n'
          '{{ msg.content }}<|im_end|>\n{% endfor %}';
      expect(detector.detect(template), same(LlamaProfiles.qwen3));
    });

    test('returns null for unknown template', () {
      const template = 'some random template format {{ content }}';
      expect(detector.detect(template), isNull);
    });
  });
}
