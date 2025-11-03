import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'dart:math';

class ChatArgs {
  final String tenantId;
  final String role;
  const ChatArgs({required this.tenantId, required this.role});
}

class ChatController extends StateNotifier<List<ChatMessage>> {
  final ChatService _svc;
  final ChatArgs _args;

  ChatController(this._svc, this._args) : super(const []);

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final reqId = _makeRequestId();
    // mostra a mensagem do usuário imediatamente
    state = [
      ...state,
      ChatMessage(id: reqId, from: 'user', text: trimmed),
    ];

    try {
      final reply = await _svc.send(
        tenantId: _args.tenantId,
        role: _args.role,
        text: trimmed,
        requestId: reqId,
      );
      state = [
        ...state,
        ChatMessage(
            id: 'bot_${reply.requestId}', from: 'bot', text: reply.message),
      ];
    } catch (e) {
      state = [
        ...state,
        ChatMessage(
            id: 'err_$reqId',
            from: 'system',
            text: 'Erro ao chamar função: $e'),
      ];
    }
  }
}

/// Provider family para injetar tenant/role
final chatControllerProvider =
    StateNotifierProvider.family<ChatController, List<ChatMessage>, ChatArgs>(
  (ref, args) => ChatController(ChatService(), args),
);

/// mesmo gerador usado no service (evita nextInt(0))
String _makeRequestId() => _makeRequestIdStatic();
String _makeRequestIdStatic() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
}
