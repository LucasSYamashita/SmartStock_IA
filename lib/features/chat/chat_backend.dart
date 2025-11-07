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
      final call = functions.httpsCallable('chatRespond');
      final res = await call.call({
        'tenantId': tenantId,
        'userId': userId,
        'text': text,
        'enableVertex': kEnableVertex,
      });
      final data = Map<String, dynamic>.from(res.data ?? {});
      return ChatResult.fromMap(data);
    } catch (e) {
      print('⚠️ Erro Cloud Function: $e → fallback local');
      return fallback.respond(
        tenantId: tenantId,
        userId: userId,
        text: text,
      );
    }
  }
}

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

    final entrada =
        RegExp(r'entrada\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$');
    final saida =
        RegExp(r'(saida|venda)\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$');

    if (entrada.hasMatch(t)) {
      final m = entrada.firstMatch(t)!;
      final qtd = int.parse(m.group(1)!);
      final nome = m.group(2)!;
      final preco = m.group(3) != null
          ? double.tryParse(m.group(3)!.replaceAll(',', '.'))
          : null;

      await inventory.registrar(
        tenantId: tenantId,
        nome: nome,
        quantidade: qtd,
        tipo: 'entrada',
        preco: preco,
      );

      return ChatResult(
        message:
            '✅ Entrada registrada localmente: +${qtd} x $nome${preco != null ? " a R\$${preco.toStringAsFixed(2)}" : ""}.',
        intent: 'entrada',
        produto: nome,
        quantidade: qtd,
        preco: preco,
      );
    }

    if (saida.hasMatch(t)) {
      final m = saida.firstMatch(t)!;
      final qtd = int.parse(m.group(2)!);
      final nome = m.group(3)!;
      final preco = m.group(4) != null
          ? double.tryParse(m.group(4)!.replaceAll(',', '.'))
          : null;

      await inventory.registrar(
        tenantId: tenantId,
        nome: nome,
        quantidade: qtd,
        tipo: 'saida',
        preco: preco,
      );

      return ChatResult(
        message:
            '✅ Saída registrada localmente: -${qtd} x $nome${preco != null ? " a R\$${preco.toStringAsFixed(2)}" : ""}.',
        intent: 'saida',
        produto: nome,
        quantidade: qtd,
        preco: preco,
      );
    }

    if (t.contains('baixo estoque') || t.contains('sugest')) {
      return ChatResult(
        message: 'Verificando produtos com estoque baixo...',
        intent: 'sugestao',
      );
    }

    if (t.contains('quanto') || t.contains('tem')) {
      return ChatResult(
        message: 'Use: "quanto tem de [produto]" para consultar estoque.',
        intent: 'consulta',
      );
    }

    return ChatResult(
      message:
          'Posso ajudar com **entrada**, **saída**, **consulta** e **sugestão**. Ex: "entrada 10 coca a 8,50", "venda 3 coca", "o que repor?".',
      intent: 'geral',
    );
  }
}

ChatBackend makeChatBackend(FirebaseFirestore db) {
  return CloudFunctionsChatBackend(fallback: LocalChatBackend(db));
}
