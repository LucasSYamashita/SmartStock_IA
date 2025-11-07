import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/feature_flags.dart';
import 'fallback_inventory.dart';

class ChatResult {
  final String message;
  final String intent;
  final String? produto;
  final int? quantidade;
  final double? preco;

  ChatResult({
    required this.message,
    required this.intent,
    this.produto,
    this.quantidade,
    this.preco,
  });

  factory ChatResult.fromMap(Map<String, dynamic> map) => ChatResult(
        message: map['message'] ?? '',
        intent: map['intent'] ?? 'geral',
        produto: map['produto'],
        quantidade: map['quantidade'],
        preco: (map['preco'] is num)
            ? (map['preco'] as num).toDouble()
            : double.tryParse('${map['preco'] ?? ''}'),
      );
}

abstract class ChatBackend {
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  });
}

/// 🔹 BACKEND PRINCIPAL: Cloud Function (IA + Firestore remoto)
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
    try {
      print(
          '🛰 Enviando para chatRespond: tenant=$tenantId user=$userId text=$text');

      final callable = functions.httpsCallable('chatRespond');
      final res = await callable.call({
        'tenantId': tenantId,
        'userId': userId,
        'text': text,
        'enableVertex': kEnableVertex,
      });

      final data = Map<String, dynamic>.from(res.data ?? {});
      print('✅ chatRespond retorno: $data');
      return ChatResult.fromMap(data);
    } catch (e) {
      print('⚠️ Erro Cloud Function: $e — usando fallback local');
      return fallback.respond(
        tenantId: tenantId,
        userId: userId,
        text: text,
      );
    }
  }
}

/// 🔹 FALLBACK LOCAL: usa Firestore direto (sem função)
class LocalChatBackend implements ChatBackend {
  final FirebaseFirestore db;
  final FallbackInventory inventory;
  LocalChatBackend(this.db) : inventory = FallbackInventory(db);

  @override
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  }) async {
    final t = text.toLowerCase().trim();
    final match = RegExp(r'entrada\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$')
        .firstMatch(t);

    if (match != null) {
      final qtd = int.tryParse(match.group(1)!) ?? 0;
      final nome = match.group(2)!.trim();
      final preco = match.group(3) != null
          ? double.tryParse(match.group(3)!.replaceAll(',', '.'))
          : null;

      print('⚙️ Fallback: registrando $qtd x $nome no tenant $tenantId');
      await inventory.registrar(
        tenantId: tenantId,
        nome: nome, // já existe no seu match do RegExp
        quantidade: qtd, // idem
        tipo: "entrada",
        preco: preco,
      );

      return ChatResult(
        message:
            '✅ Entrada registrada localmente: ${qtd}x $nome ${preco != null ? "a R\$${preco.toStringAsFixed(2)}" : ""}.',
        intent: 'entrada',
        produto: nome,
        quantidade: qtd,
        preco: preco,
      );
    }

    if (t.contains('baixo estoque')) {
      return ChatResult(
        message: 'Verificando baixo estoque...',
        intent: 'consulta',
      );
    }

    return ChatResult(
      message:
          'Posso ajudar com **estoque, vendas e sugestões**. Ex: "entrada 10 coca a 8,50".',
      intent: 'geral',
    );
  }
}

/// 🔹 Usa Function + Fallback automático
ChatBackend makeChatBackend(FirebaseFirestore db) {
  return CloudFunctionsChatBackend(fallback: LocalChatBackend(db));
}
