import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_service.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  ChatMessage(this.role, this.content);
}

/// estado de preenchimento progressivo (produto -> quantidade -> preço)
class PendingIntent {
  String? produto;
  int? quantidade;
  double? preco;

  Map<String, dynamic> toHint() => {
        if (produto != null) 'produto': produto,
        if (quantidade != null) 'quantidade': quantidade,
        if (preco != null) 'preco': preco,
      };

  void mergeFromText(String text) {
    final low = text.toLowerCase();
    final pProd = RegExp(
            r'(?:entrada\s+(?:de|em)\s+|(?:de|em)\s+)([\p{L}\s\-]+)$',
            unicode: true)
        .firstMatch(low);
    if (pProd != null) {
      produto = pProd.group(1)!.trim();
    }
    final q =
        RegExp(r'(\d+)\s*(?:un|un\.|unidade|unidades)?\b').firstMatch(low);
    if (q != null) {
      quantidade = int.tryParse(q.group(1)!);
    }
    final p = RegExp(r'(?:\ba\s+|\bpor\s+|r\$\s*)(\d+(?:[.,]\d+)?)\b')
        .firstMatch(low);
    if (p != null) {
      preco = double.tryParse(p.group(1)!.replaceAll(',', '.'));
    }
  }
}

class ChatController {
  final ChatService _svc;
  final String tenantId;
  final String role;

  ChatController(
      {required this.tenantId, required this.role, ChatService? service})
      : _svc = service ?? ChatService();

  final List<Map<String, String>> _messages = []; // mantém contexto curto

  Future<String> send(String userText) async {
    _messages.add({'role': 'user', 'content': userText});

    final data = await _svc.actCall(
      tenantId: tenantId,
      role: role,
      messages: _messages,
    );

    final assistant = (data['assistant_text'] ?? '') as String;
    _messages.add({'role': 'assistant', 'content': assistant});
    return assistant;
  }
}

/// Provider para o controller
final chatControllerProvider = StateNotifierProvider.family<ChatController,
    List<ChatMessage>, ({String tenantId, String role})>(
  (ref, args) {
    final svc = ChatServiceImpl();
    return ChatController(svc, args.tenantId, args.role);
  },
);
