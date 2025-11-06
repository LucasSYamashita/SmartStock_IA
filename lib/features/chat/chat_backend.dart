import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../config/feature_flags.dart';

class ChatResult {
  final String reply;
  ChatResult(this.reply);
}

abstract class ChatBackend {
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  });
}

/// BACKEND LOCAL (sem Vertex): útil para respostas rápidas.
class LocalChatBackend implements ChatBackend {
  final FirebaseFirestore db;
  LocalChatBackend(this.db);

  @override
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  }) async {
    final t = text.trim().toLowerCase();

    // Entrada/Saída -> orientar a usar as telas
    final entradaRegex = RegExp(r'\b(entrada|dar entrada|estoque\+)\b');
    final saidaRegex = RegExp(r'\b(sa[ií]da|venda|baixar estoque)\b');
    if (entradaRegex.hasMatch(t)) {
      return ChatResult(
          'Para **entrada**, abra o produto e toque em “Registrar entrada”.');
    }
    if (saidaRegex.hasMatch(t)) {
      return ChatResult(
          'Para **saída/venda**, use o botão **Vender** na tela Início.');
    }

    // Baixo estoque
    if (t.contains('baixo estoque') ||
        t.contains('falta') ||
        t.contains('repor')) {
      final q = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('produtos')
          .where('ativo', isEqualTo: true)
          .orderBy('nomeLower')
          .get();

      final baixos = q.docs.where((d) {
        final m = d.data();
        final qtd = (m['quantidade'] ?? 0) as int;
        final min = (m['estoqueMinimo'] ?? 0) as int;
        return qtd <= min;
      }).toList();

      if (baixos.isEmpty)
        return ChatResult('Bom sinal! Nada em baixo estoque.');
      final lines = baixos.take(10).map((d) {
        final m = d.data();
        return '• ${m['nome']} — qtd ${m['quantidade']} (min ${m['estoqueMinimo']})';
      }).join('\n');
      return ChatResult('Itens em baixo estoque:\n$lines');
    }

    // Sugestão por nome
    if (t.length >= 2) {
      final start = t;
      final end = '$t\uf8ff';
      final q = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('produtos')
          .where('nomeLower', isGreaterThanOrEqualTo: start)
          .where('nomeLower', isLessThanOrEqualTo: end)
          .limit(5)
          .get();
      if (q.docs.isNotEmpty) {
        final lines = q.docs.map((d) => '• ${d.data()['nome']}').join('\n');
        return ChatResult('Você quis dizer:\n$lines');
      }
    }

    return ChatResult(
        'Posso ajudar com consultas de estoque e itens em falta.\n'
        'Para **entrada**, use a tela do produto; para **saída**, use **Vender**.');
  }
}

/// BACKEND VIA CALLABLE (usa Vertex se habilitado)
class CloudFunctionsChatBackend implements ChatBackend {
  final FirebaseFunctions functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');
  final ChatBackend fallback;
  CloudFunctionsChatBackend({required this.fallback});

  @override
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  }) async {
    if (!kEnableVertex) {
      return fallback.respond(tenantId: tenantId, userId: userId, text: text);
    }
    try {
      final call = functions.httpsCallable('chatRespond');
      final res = await call
          .call({'tenantId': tenantId, 'userId': userId, 'text': text});
      final m = (res.data ?? {}) as Map;
      final reply = (m['reply'] ?? '').toString().trim();
      if (reply.isNotEmpty) return ChatResult(reply);
    } catch (_) {/* cai no fallback */}
    return fallback.respond(tenantId: tenantId, userId: userId, text: text);
  }
}

/// Factory
ChatBackend makeChatBackend(FirebaseFirestore db) {
  return CloudFunctionsChatBackend(fallback: LocalChatBackend(db));
}
