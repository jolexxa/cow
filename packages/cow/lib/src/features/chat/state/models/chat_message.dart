class ChatMessage {
  ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.kind,
    this.responseId,
  });

  factory ChatMessage.user(String text, {int? responseId}) {
    return ChatMessage(
      id: _nextId(),
      sender: 'You',
      text: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.user,
      responseId: responseId,
    );
  }

  factory ChatMessage.assistant(String text, {int? responseId}) {
    return ChatMessage(
      id: _nextId(),
      sender: 'Cow',
      text: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.assistant,
      responseId: responseId,
    );
  }

  factory ChatMessage.alert(
    String text, {
    String? id,
    DateTime? timestamp,
    int? responseId,
  }) {
    return ChatMessage(
      id: id ?? _nextId(),
      sender: 'System',
      text: text,
      timestamp: timestamp ?? DateTime.now(),
      kind: ChatMessageKind.system,
      responseId: responseId,
    );
  }

  factory ChatMessage.reasoning(
    String text, {
    String? id,
    DateTime? timestamp,
    int? responseId,
  }) {
    return ChatMessage(
      id: id ?? _nextId(),
      sender: 'Thought',
      text: text,
      timestamp: timestamp ?? DateTime.now(),
      kind: ChatMessageKind.reasoning,
      responseId: responseId,
    );
  }

  factory ChatMessage.summary(
    String text, {
    String? id,
    DateTime? timestamp,
    int? responseId,
  }) {
    return ChatMessage(
      id: id ?? _nextId(),
      sender: 'Thinking',
      text: text,
      timestamp: timestamp ?? DateTime.now(),
      kind: ChatMessageKind.summary,
      responseId: responseId,
    );
  }

  bool get isSystem => kind == ChatMessageKind.system;
  bool get isReasoning => kind == ChatMessageKind.reasoning;
  bool get isSummary => kind == ChatMessageKind.summary;

  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final ChatMessageKind kind;
  final int? responseId;

  ChatMessage append(String chunk) {
    return copyWithText('$text$chunk');
  }

  ChatMessage copyWithText(String value) {
    return ChatMessage(
      id: id,
      sender: sender,
      text: value,
      timestamp: timestamp,
      kind: kind,
      responseId: responseId,
    );
  }

  static int _idCounter = 0;

  static String _nextId() {
    final id = '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
    _idCounter += 1;
    return id;
  }
}

enum ChatMessageKind { user, assistant, system, reasoning, summary }
