class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final bool pending; // para dar um estilo "enviando..." se quiser

  ChatMessage({
    required this.role,
    required this.content,
    this.pending = false,
  });

  ChatMessage copyWith({String? role, String? content, bool? pending}) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      pending: pending ?? this.pending,
    );
  }
}
