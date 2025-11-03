class ChatMessage {
  final String id;
  final String from; // 'user' | 'bot' | 'system'
  final String text;

  const ChatMessage({required this.id, required this.from, required this.text});
}

class ChatRequest {
  final String id;
  final String tenantId;
  final String role;
  final String text;
  const ChatRequest({
    required this.id,
    required this.tenantId,
    required this.role,
    required this.text,
  });
}

class ChatReply {
  final String message;
  const ChatReply(this.message);
}
