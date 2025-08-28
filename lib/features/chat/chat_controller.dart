import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/datasources/firestore_movements.dart';
import '../tenant/tenant_provider.dart';
import 'nlu.dart' as nlu;

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const ChatMessage(this.role, this.text);
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, List<ChatMessage>>((ref) {
  return ChatController(ref);
});

class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._ref) : super(const []);
  final Ref _ref;

  // intenção pendente por tenant (evita confusão ao trocar de loja)
  nlu.Intent? _pendingIntent;
  String? _pendingTenantId;

  void _say(String text) {
    state = [...state, ChatMessage('assistant', text)];
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    state = [...state, ChatMessage('user', text)];

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _say('Faça login para continuar.');
      return;
    }

    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) {
      _say('Selecione/entre em uma loja primeiro.');
      return;
    }

    final db = FirebaseFirestore.instance;
    final movements = FirestoreMovements(db, tenantId);
    final uid = user.uid;

    try {
      // comandos de controle
      final low = text.toLowerCase();
      final isConfirm =
          low == 'confirmar' || low == 'sim' || low == 'ok' || low == 'confirm';
      final isCancel = low == 'cancelar' || low == 'cancel';

      if (isCancel) {
        _pendingIntent = null;
        _pendingTenantId = null;
        _say('Ok, operação cancelada.');
        return;
      }

      if (isConfirm &&
          _pendingIntent is nlu.MoveIntent &&
          _pendingTenantId == tenantId) {
        final intent = _pendingIntent as nlu.MoveIntent;

        // resolve produto antes de aplicar
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          _say(
              'Produto "${intent.produtoNome}" não encontrado. Tente o nome exato.');
          _pendingIntent = null;
          _pendingTenantId = null;
          return;
        }

        // aplica movimento
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

        // lê quantidade atualizada
        final updated = await prod.reference.get();
        final data = updated.data() ?? {};
        final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();
        final qAny = data['quantidade'] ?? data['Quantidade'] ?? 0;
        final qtd = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;

        _say('✅ ${intent.tipo} registrada: ${intent.quantidade} un. de $nome.\n'
            'Estoque atual: $qtd un.');

        _pendingIntent = null;
        _pendingTenantId = null;
        return;
      }

      // interpreta
      final intent = nlu.parseCommand(text);

      if (intent is nlu.QueryIntent) {
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          final sugg = await suggestProducts(intent.produtoNome, db, tenantId);
          if (sugg.isEmpty) {
            _say('Não encontrei "${intent.produtoNome}".');
          } else {
            _say(
                'Não encontrei exatamente "${intent.produtoNome}". Você quis dizer:\n• ${sugg.join('\n• ')}');
          }
          return;
        }
        final data = prod.data() ?? {};
        final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();
        final qAny = data['quantidade'] ?? data['Quantidade'] ?? 0;
        final minAny = data['estoqueMinimo'] ?? data['EstoqueMinimo'] ?? 0;
        final qtd = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;
        final minimo =
            minAny is num ? minAny.toInt() : int.tryParse('$minAny') ?? 0;

        final status = qtd == 0 ? 'S/E' : (qtd <= minimo ? 'Baixo' : 'OK');

        _say('Estoque de "$nome": $qtd un. (mín: $minimo) • Status: $status');
        return;
      }

      if (intent is nlu.MoveIntent) {
        // tenta resolver já aqui para trazer contexto na confirmação
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          final sugg = await suggestProducts(intent.produtoNome, db, tenantId);
          if (sugg.isEmpty) {
            _say(
                'Produto "${intent.produtoNome}" não encontrado. Tente o nome exato.');
          } else {
            _say(
                'Produto não encontrado. Você quis dizer:\n• ${sugg.join('\n• ')}');
          }
          return;
        }
        final data = prod.data() ?? {};
        final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();
        final qAny = data['quantidade'] ?? data['Quantidade'] ?? 0;
        final qtd = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;

        _pendingIntent = intent;
        _pendingTenantId = tenantId;

        _say('Confirma ${intent.tipo} de ${intent.quantidade} un. de "$nome"? '
            'Estoque atual: $qtd. Responda "confirmar" ou "cancelar".');
        return;
      }

      _say('Não entendi. Exemplos:\n'
          '• entrada de 5 do Produto X\n'
          '• vendi 2 do Produto Y\n'
          '• quanto tem do Produto Z');
    } catch (e) {
      _say('Erro: ${e.toString()}');
    }
  }
}

/// Busca por nome (case-insensitive) com fallback.
Future<DocumentSnapshot<Map<String, dynamic>>?> resolveProductByName(
  String name,
  FirebaseFirestore db,
  String tenantId,
) async {
  final lower = name.toLowerCase().trim();
  final col = db.collection('tenants').doc(tenantId).collection('produtos');

  // 1) nomeLower == lower
  var snap = await col.where('nomeLower', isEqualTo: lower).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  // 2) nome == name (exato, mantendo capitalização)
  snap = await col.where('nome', isEqualTo: name.trim()).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  // 3) prefixo (orderBy + startAt/endAt) — single-field index padrão do Firestore
  try {
    snap = await col
        .orderBy('nomeLower')
        .startAt([lower])
        .endAt(['$lower\uf8ff'])
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return snap.docs.first;
  } catch (_) {
    // se o índice não estiver pronto, ignora
  }

  // 4) fallback: amostra e compara
  final sample = await col.limit(50).get();
  for (final d in sample.docs) {
    final data = d.data();
    final n = (data['nome'] as String?) ?? (data['Nome'] as String?);
    if (n != null && n.toLowerCase().trim() == lower) return d;
  }
  return null;
}

/// Sugere até 5 produtos cujo nomeLower começa com o termo informado.
Future<List<String>> suggestProducts(
  String name,
  FirebaseFirestore db,
  String tenantId, {
  int limit = 5,
}) async {
  final lower = name.toLowerCase().trim();
  if (lower.isEmpty) return const [];

  final col = db.collection('tenants').doc(tenantId).collection('produtos');
  try {
    final snap = await col
        .orderBy('nomeLower')
        .startAt([lower])
        .endAt(['$lower\uf8ff'])
        .limit(limit)
        .get();

    final out = <String>[];
    for (final d in snap.docs) {
      final data = d.data();
      final n = (data['nome'] ?? data['Nome'])?.toString();
      if (n != null && n.isNotEmpty) out.add(n);
    }
    return out;
  } catch (_) {
    // fallback simples: amostra e contém
    final sample = await col.limit(50).get();
    final out = <String>[];
    for (final d in sample.docs) {
      final data = d.data();
      final n = (data['nome'] ?? data['Nome'])?.toString() ?? '';
      if (n.toLowerCase().contains(lower)) {
        out.add(n);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}
