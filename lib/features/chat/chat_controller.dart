import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/tenant/tenant_provider.dart';
import 'chat_service.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const ChatMessage({required this.role, required this.content});

  Map<String, String> toMap() => {'role': role, 'content': content};
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, List<ChatMessage>>(
  (ref) => ChatController(ref, const ChatService()),
);

class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._ref, this._svc) : super(const []);
  final Ref _ref;
  final ChatService _svc;

  // último dryRun pendente para confirmar
  Map<String, dynamic>? _pendingParsed;
  String? _pendingAssistantText;

  void _append(String role, String text) {
    state = [...state, ChatMessage(role: role, content: text)];
  }

  /// Chat livre: só conversa
  Future<void> send(String text) async {
    final input = text.trim();
    if (input.isEmpty) return;

    state = [...state, ChatMessage(role: 'user', content: input)];

    try {
      final answer = await _svc.chatOnce(
        history: state.map((m) => m.toMap()).toList(),
      );
      _append('assistant', answer);
    } catch (e) {
      _append('assistant', 'Erro: $e');
    }
  }

  /// Propor ação (dryRun=true): IA interpreta e só “propõe”
  Future<void> proposeAction(String userText) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _append('assistant', '⚠️ Faça login.');
      return;
    }
    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) {
      _append('assistant', '⚠️ Selecione uma loja (tenant).');
      return;
    }

    state = [...state, ChatMessage(role: 'user', content: userText)];

    try {
      final result = await _svc.act(
        messages: state.map((m) => m.toMap()).toList(),
        tenantId: tenantId,
        role: 'staff', // ajuste conforme seu controle de papéis
        uid: uid,
        dryRun: true,
        confirm: false,
      );
      _pendingParsed = result['parsed'] as Map<String, dynamic>?;
      _pendingAssistantText = result['assistant_text']?.toString();
      _append(
          'assistant', _pendingAssistantText ?? 'Proposta gerada. Confirma?');
    } catch (e) {
      _append('assistant', 'Erro: $e');
    }
  }

  /// Confirmar a última proposta pendente (executa no Firestore)
  Future<void> confirmPending({bool createIfMissing = true}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _append('assistant', '⚠️ Faça login.');
      return;
    }
    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) {
      _append('assistant', '⚠️ Selecione uma loja (tenant).');
      return;
    }
    if (_pendingParsed == null) {
      _append('assistant', 'Não há operação pendente para confirmar.');
      return;
    }

    try {
      final result = await _svc.act(
        messages: state.map((m) => m.toMap()).toList(),
        tenantId: tenantId,
        role: 'staff',
        uid: uid,
        dryRun: false,
        confirm: true,
        createIfMissing: createIfMissing,
      );
      final text = (result['assistant_text'] ?? 'OK').toString();
      _append('assistant', text);

      // limpamos o pending
      _pendingParsed = null;
      _pendingAssistantText = null;
    } catch (e) {
      _append('assistant', 'Erro: $e');
    }
  }

  /// Cancela a última proposta pendente
  void cancelPending() {
    if (_pendingParsed != null) {
      _pendingParsed = null;
      _pendingAssistantText = null;
      _append('assistant', '✅ Operação cancelada.');
    }
  }
}
