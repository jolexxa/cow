import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  test('RoleName extension returns role strings', () {
    expect(Role.system.roleName, 'system');
    expect(Role.user.roleName, 'user');
    expect(Role.assistant.roleName, 'assistant');
    expect(Role.tool.roleName, 'tool');
  });
}
