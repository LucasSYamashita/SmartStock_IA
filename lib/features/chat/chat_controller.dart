import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_service.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  ChatMessage(this.role, this.content);
}

class ChatState {
  final List<ChatMessage> items;
  const ChatState({this.items = const []});
  ChatState add(ChatMessage m) => ChatState(items: [...items, m]);
}

class ChatController extends StateNotifier<ChatState> {
  final ChatService _svc;
  final String tenantId;
  final String role;

  ChatController({
    required ChatService service,
    required this.tenantId,
    required this.role,
  })  : _svc = service,
        super(const ChatState());

  void addLocal(String role, String text) {
    if (!mounted) return;
    state = state.add(ChatMessage(role, text));
  }

  Future<void> send(String text) async {
    addLocal('user', text);
    try {
      final replies = await _svc.actStepwise(
        tenantId: tenantId,
        role: role,
        text: text,
      );
      for (final r in replies) {
        if (!mounted) return;
        state = state.add(ChatMessage('assistant', r));
      }
    } catch (e) {
      if (!mounted) return;
      state = state.add(ChatMessage('assistant', 'ERRO: $e'));
    }
  }
}
