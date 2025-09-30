// lib/features/chat/chat_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_service.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  ChatMessage({required this.role, required this.content});

  Map<String, String> toMap() => {'role': role, 'content': content};
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, List<ChatMessage>>(
  (ref) => ChatController(const ChatService()),
);

class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._svc) : super(const []);
  final ChatService _svc;

  bool _streaming = false;

  Future<void> send(String text) async {
    final input = text.trim();
    if (input.isEmpty) return;

    final history = [...state, ChatMessage(role: 'user', content: input)];
    state = history;

    try {
      final answer = await _svc.chatOnce(
        history: history.map((m) => m.toMap()).toList(),
      );
      state = [...history, ChatMessage(role: 'assistant', content: answer)];
    } catch (e) {
      state = [...history, ChatMessage(role: 'assistant', content: 'Erro: $e')];
    }
  }

  Future<void> sendStreaming(String text) async {
    final input = text.trim();
    if (input.isEmpty || _streaming) return;

    final history = [...state, ChatMessage(role: 'user', content: input)];
    state = [...history, ChatMessage(role: 'assistant', content: '')];

    final idx = state.length - 1;
    _streaming = true;
    try {
      final stream = _svc.chatStream(
        history: history.map((m) => m.toMap()).toList(),
      );
      await for (final delta in stream) {
        final curr = state[idx].content + delta;
        final updated = [...state];
        updated[idx] = ChatMessage(role: 'assistant', content: curr);
        state = updated;
      }
    } catch (e) {
      final updated = [...state];
      updated[idx] = ChatMessage(role: 'assistant', content: 'Erro: $e');
      state = updated;
    } finally {
      _streaming = false;
    }
  }

  Future<void> actFromText(String text) async {
    final history = [...state, ChatMessage(role: 'user', content: text)];
    state = history;
    try {
      final result = await _svc.act(
        messages: history.map((m) => m.toMap()).toList(),
      );
      final msg = (result['assistant_text'] ?? 'OK').toString();
      state = [...history, ChatMessage(role: 'assistant', content: msg)];
    } catch (e) {
      state = [...history, ChatMessage(role: 'assistant', content: 'Erro: $e')];
    }
  }
}
