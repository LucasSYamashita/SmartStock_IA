import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../config/feature_flags.dart';
import 'fallback_inventory.dart';

/// Resultado padronizado do chat (tanto IA quanto fallback)
class ChatResult {
  final String message;
  final String
      intent; // 'entrada' | 'saida' | 'consulta' | 'sugestao' | 'geral'
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

/// Backend genérico do chat
abstract class ChatBackend {
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  });
}

/// BACKEND PRINCIPAL: usa Cloud Function `chatRespond` (IA + Vertex)
/// e, se a IA entender que é entrada/saída, grava o movimento via `FallbackInventory`.
class CloudFunctionsChatBackend implements ChatBackend {
  final FirebaseFunctions functions;
  final FallbackInventory inventory;
  final ChatBackend fallback;

  CloudFunctionsChatBackend({
    required FirebaseFirestore db,
    required this.fallback,
  })  : functions = FirebaseFunctions.instanceFor(region: 'us-central1'),
        inventory = FallbackInventory(db);

  @override
  Future<ChatResult> respond({
    required String tenantId,
    required String userId,
    required String text,
  }) async {
    try {
      print(
          '🛰 [chat] Enviando para chatRespond: tenant=$tenantId user=$userId enableVertex=$kEnableVertex text="$text"');

      final callable = functions.httpsCallable('chatRespond');
      final res = await callable.call({
        'tenantId': tenantId,
        'userId': userId,
        'text': text,
        'enableVertex': kEnableVertex,
      });

      final data = Map<String, dynamic>.from(res.data ?? {});
      print('✅ [chat] chatRespond retorno: $data');

      final result = ChatResult.fromMap(data);

      // Se a IA entendeu como entrada/saída, registramos o movimento aqui.
      final isMov = result.intent == 'entrada' || result.intent == 'saida';

      if (isMov &&
          result.produto != null &&
          result.quantidade != null &&
          result.quantidade! > 0) {
        print(
          '📦 [chat] Registrando via IA: '
          '${result.intent} ${result.quantidade}x ${result.produto} '
          '(preço=${result.preco})',
        );

        await inventory.registrar(
          tenantId: tenantId,
          nome: result.produto!,
          quantidade: result.quantidade!,
          tipo: result.intent, // 'entrada' | 'saida'
          preco: result.preco,
        );
      }

      return result;
    } catch (e, st) {
      print(
          '⚠️ [chat] Erro na Cloud Function chatRespond: $e\n$st\n→ usando fallback local');
      return fallback.respond(
        tenantId: tenantId,
        userId: userId,
        text: text,
      );
    }
  }
}

/// FALLBACK LOCAL: só entra se a Function falhar.
/// Sintaxe simples:
///   - "entrada 10 coca a 4,25"
///   - "saida 3 coca a 5"
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
    print('🛟 [chat] Fallback local acionado para texto: "$text"');

    final t = text.toLowerCase().trim();

    final entrada =
        RegExp(r'entrada\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$');
    final saida =
        RegExp(r'(saida|venda)\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$');

    if (entrada.hasMatch(t)) {
      final m = entrada.firstMatch(t)!;
      final qtd = int.parse(m.group(1)!);
      final nome = m.group(2)!.trim();
      final preco = m.group(3) != null
          ? double.tryParse(m.group(3)!.replaceAll(',', '.'))
          : null;

      print('⚙️ [chat] Fallback: registrando ENTRADA localmente $qtd x $nome');

      await inventory.registrar(
        tenantId: tenantId,
        nome: nome,
        quantidade: qtd,
        tipo: 'entrada',
        preco: preco,
      );

      return ChatResult(
        message:
            '✅ Entrada registrada localmente (fallback): +$qtd x $nome${preco != null ? " a R\$${preco.toStringAsFixed(2)}" : ""}.',
        intent: 'entrada',
        produto: nome,
        quantidade: qtd,
        preco: preco,
      );
    }

    if (saida.hasMatch(t)) {
      final m = saida.firstMatch(t)!;
      final qtd = int.parse(m.group(2)!);
      final nome = m.group(3)!.trim();
      final preco = m.group(4) != null
          ? double.tryParse(m.group(4)!.replaceAll(',', '.'))
          : null;

      print('⚙️ [chat] Fallback: registrando SAÍDA localmente $qtd x $nome');

      await inventory.registrar(
        tenantId: tenantId,
        nome: nome,
        quantidade: qtd,
        tipo: 'saida',
        preco: preco,
      );

      return ChatResult(
        message:
            '✅ Saída registrada localmente (fallback): -$qtd x $nome${preco != null ? " a R\$${preco.toStringAsFixed(2)}" : ""}.',
        intent: 'saida',
        produto: nome,
        quantidade: qtd,
        preco: preco,
      );
    }

    if (t.contains('baixo estoque') || t.contains('sugest')) {
      return ChatResult(
        message: 'Verificando produtos com estoque baixo (fallback)...',
        intent: 'sugestao',
      );
    }

    if (t.contains('quanto') || t.contains('tem')) {
      return ChatResult(
        message:
            'Use: "quanto tem de [produto]" para consultar estoque (fallback).',
        intent: 'consulta',
      );
    }

    return ChatResult(
      message:
          'Posso ajudar com **entrada**, **saída**, **consulta** e **sugestão**. '
          'Ex: "entrada 10 coca a 8,50", "venda 3 coca", "o que repor?".',
      intent: 'geral',
    );
  }
}

/// Factory: usa Function + fallback automático
ChatBackend makeChatBackend() {
  final db = FirebaseFirestore.instance;
  final local = LocalChatBackend(db);
  return CloudFunctionsChatBackend(db: db, fallback: local);
}
