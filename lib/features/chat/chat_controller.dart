import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/datasources/firestore_movements.dart';
import '../tenant/tenant_provider.dart';
import 'nlu.dart' as nlu;

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  ChatMessage(this.role, this.text);
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, List<ChatMessage>>((ref) {
  return ChatController(ref);
});

class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._ref) : super(const []);
  final Ref _ref;

  nlu.Intent? _pending;

  Future<void> send(String text) async {
    state = [...state, ChatMessage('user', text)];
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) {
      state = [
        ...state,
        ChatMessage('assistant', 'Selecione/entre em uma loja primeiro.')
      ];
      return;
    }
    final movements = FirestoreMovements(db, tenantId);

    try {
      // CONFIRMAÇÃO
      if (text.trim().toLowerCase() == 'confirmar' &&
          _pending is nlu.MoveIntent) {
        final intent = _pending as nlu.MoveIntent;
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          state = [
            ...state,
            ChatMessage(
                'assistant', 'Produto "${intent.produtoNome}" não encontrado.')
          ];
          _pending = null;
          return;
        }
        await movements.applyMovement(
          produtoId: prod.id,
          tipo: intent.tipo,
          quantidade: intent.quantidade,
          motivo:
              intent.motivo ?? (intent.tipo == 'entrada' ? 'compra' : 'venda'),
          usuarioId: uid,
          origem: 'chatbot',
          mensagemOriginal: intent.originalText,
        );
        final data = prod.data();
        final nome =
            (data?['nome'] ?? data?['Nome'] ?? '(sem nome)').toString();
        state = [
          ...state,
          ChatMessage('assistant',
              '✅ ${intent.tipo} registrada: ${intent.quantidade} un. de $nome.')
        ];
        _pending = null;
        return;
      }

      // NLU
      final intent = nlu.parseCommand(text);

      if (intent is nlu.QueryIntent) {
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          state = [
            ...state,
            ChatMessage('assistant', 'Não encontrei "${intent.produtoNome}".')
          ];
          return;
        }
        final data = prod.data();
        final nome =
            (data?['nome'] ?? data?['Nome'] ?? '(sem nome)').toString();
        final qAny = data?['quantidade'] ??
            data?['Quantidade'] ??
            data?['qtd'] ??
            data?['Qtd'];
        final q = qAny is num
            ? qAny.toInt()
            : int.tryParse(qAny?.toString() ?? '') ?? 0;
        state = [
          ...state,
          ChatMessage('assistant', 'Em estoque: $q un. de $nome.')
        ];
        return;
      }

      if (intent is nlu.MoveIntent) {
        _pending = intent;
        state = [
          ...state,
          ChatMessage('assistant',
              'Confirma ${intent.tipo} de ${intent.quantidade} un. de "${intent.produtoNome}"? Responda "confirmar".')
        ];
        return;
      }

      state = [
        ...state,
        ChatMessage('assistant',
            'Não entendi. Exemplos: "entrada de 5 do Produto X", "vendi 2 do Produto Y", "quanto tem do Produto Z"')
      ];
    } catch (e) {
      state = [...state, ChatMessage('assistant', 'Erro: ${e.toString()}')];
    }
  }
}

/// Busca por nome dentro do tenant (case-insensitive com nomeLower).
Future<DocumentSnapshot<Map<String, dynamic>>?> resolveProductByName(
  String name,
  FirebaseFirestore db,
  String tenantId,
) async {
  final lower = name.toLowerCase().trim();
  final col = db.collection('tenants').doc(tenantId).collection('produtos');

  var snap = await col.where('nomeLower', isEqualTo: lower).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  snap = await col.where('nome', isEqualTo: name.trim()).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  final sample = await col.limit(50).get();
  for (final d in sample.docs) {
    final data = d.data();
    final n = (data['nome'] as String?) ?? (data['Nome'] as String?);
    if (n != null && n.toLowerCase().trim() == lower) return d;
  }
  return null;
}
