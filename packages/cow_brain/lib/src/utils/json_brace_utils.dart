/// Finds the position of the closing brace `}` matching the one at [start].
///
/// Returns null if [start] doesn't point to `{` or no matching brace is found.
/// Correctly handles JSON string escaping and nested braces.
int? findMatchingBrace(String text, int start) {
  if (start >= text.length || text.codeUnitAt(start) != 0x7B /* { */ ) {
    return null;
  }

  var depth = 0;
  var inString = false;
  var escape = false;

  for (var i = start; i < text.length; i++) {
    final c = text.codeUnitAt(i);

    if (escape) {
      escape = false;
      continue;
    }

    if (c == 0x5C /* \ */ && inString) {
      escape = true;
      continue;
    }

    if (c == 0x22 /* " */ ) {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (c == 0x7B /* { */ ) {
      depth++;
    } else if (c == 0x7D /* } */ ) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// Checks whether all braces `{}` and brackets `[]` in [text] are balanced.
///
/// Returns true if the text contains at least one brace/bracket and all are
/// properly closed. Correctly handles JSON string escaping.
bool areBracesBalanced(String text) {
  var depth = 0;
  var inString = false;
  var escape = false;
  var hasBraces = false;

  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);

    if (escape) {
      escape = false;
      continue;
    }

    if (c == 0x5C /* \ */ && inString) {
      escape = true;
      continue;
    }

    if (c == 0x22 /* " */ ) {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (c == 0x7B /* { */ || c == 0x5B /* [ */ ) {
      depth++;
      hasBraces = true;
    } else if (c == 0x7D /* } */ || c == 0x5D /* ] */ ) {
      depth--;
    }
  }

  return hasBraces && depth == 0;
}
