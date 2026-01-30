// Utilities are internal refactors; we keep docs light for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/utils/deep_equals_extensions.dart';

extension MessageListContextExtensions on List<Message> {
  int pinnedPrefixCount({required bool systemApplied}) {
    if (systemApplied || isEmpty) {
      return 0;
    }
    return first.role == Role.system ? 1 : 0;
  }

  int sharedPrefixLength(List<Message> other) {
    final max = length < other.length ? length : other.length;
    var count = 0;
    while (count < max && this[count].deepEquals(other[count])) {
      count += 1;
    }
    return count;
  }
}
