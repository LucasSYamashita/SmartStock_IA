// lib/features/chat/chat_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenant/tenant_provider.dart';
import '../../data/datasources/firestore_movements.dart';
import 'nlu.dart' as nlu;

/// Mensagem exibida na UI do chat
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

  nlu.Intent? _pendingIntent;
  String? _pendingTenantId;
  DateTime? _pendingSince;

  void _say(String text) {
    state = [...state, ChatMessage('assistant', text)];
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    state = [...state, ChatMessage('user', text)];

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _say('⚠️ Faça login para continuar.');
      return;
    }

    final tenantId = _ref.read(tenantIdProvider);
    if (tenantId == null) {
      _say('⚠️ Selecione/entre em uma loja primeiro.');
      return;
    }

    final db = FirebaseFirestore.instance;
    final movements = FirestoreMovements(db, tenantId);
    final uid = user.uid;

    try {
      // Normaliza comando de controle
      final low = text.toLowerCase();
      final isConfirm =
          const {'confirmar', 'confirm', 'sim', 'ok'}.contains(low);
      final isCancel = const {'cancelar', 'cancel'}.contains(low);

      // Expira pedido pendente (60s) para evitar confirmações atrasadas
      if (_pendingSince != null &&
          DateTime.now().difference(_pendingSince!).inSeconds > 60) {
        _pendingIntent = null;
        _pendingTenantId = null;
        _pendingSince = null;
      }

      if (isCancel) {
        _pendingIntent = null;
        _pendingTenantId = null;
        _pendingSince = null;
        _say('✅ Operação cancelada.');
        return;
      }

      // Confirmação de movimento pendente
      if (isConfirm &&
          _pendingIntent is nlu.MoveIntent &&
          _pendingTenantId == tenantId) {
        final intent = _pendingIntent as nlu.MoveIntent;

        // resolve produto
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          _say(
              '❌ Produto "${intent.produtoNome}" não encontrado. Tente o nome exato.');
          _pendingIntent = null;
          _pendingTenantId = null;
          _pendingSince = null;
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

        // lê quantidade atualizada
        final updated = await prod.reference.get();
        final data = updated.data() ?? {};
        final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();
        final qAny = data['quantidade'] ?? data['Quantidade'] ?? 0;
        final qtd = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;

        _say(
            '✅ ${intent.tipo} registrada: ${intent.quantidade} un. de "$nome".\n'
            '📦 Estoque atual: $qtd un.');

        _pendingIntent = null;
        _pendingTenantId = null;
        _pendingSince = null;
        return;
      }

      // Interpreta comando
      final intent = nlu.parseCommand(text);

      // Consulta de estoque
      if (intent is nlu.QueryIntent) {
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          final sugg = await suggestProducts(intent.produtoNome, db, tenantId);
          if (sugg.isEmpty) {
            _say('❌ Não encontrei "${intent.produtoNome}".');
          } else {
            _say('❌ Não encontrei exatamente "${intent.produtoNome}".\n'
                'Você quis dizer:\n• ${sugg.join('\n• ')}');
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
        _say(
            '📊 Estoque de "$nome": $qtd un. (mín: $minimo) • Status: $status');
        return;
      }

      // Movimento (entrada/saída)
      if (intent is nlu.MoveIntent) {
        // resolve para confirmar com nome e estoque atual
        final prod =
            await resolveProductByName(intent.produtoNome, db, tenantId);
        if (prod == null) {
          final sugg = await suggestProducts(intent.produtoNome, db, tenantId);
          if (sugg.isEmpty) {
            _say(
                '❌ Produto "${intent.produtoNome}" não encontrado. Tente o nome exato.');
          } else {
            _say(
                '❌ Produto não encontrado. Você quis dizer:\n• ${sugg.join('\n• ')}');
          }
          return;
        }
        final data = prod.data() ?? {};
        final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();
        final qAny = data['quantidade'] ?? data['Quantidade'] ?? 0;
        final qtd = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;

        _pendingIntent = intent;
        _pendingTenantId = tenantId;
        _pendingSince = DateTime.now();

        _say(
            '⚙️ Confirmar ${intent.tipo} de ${intent.quantidade} un. de "$nome"? '
            '(Estoque atual: $qtd)\n'
            'Responda **confirmar** ou **cancelar**.');
        return;
      }

      // fallback
      _say('Não entendi. Exemplos:\n'
          '• entrada de 5 do Produto X\n'
          '• vendi 2 do Produto Y\n'
          '• quanto tem do Produto Z');
    } on FirebaseException catch (e) {
      _say('Erro Firebase: (${e.code}) ${e.message ?? ''}');
    } catch (e) {
      _say('Erro: $e');
    }
  }
}

/// -------------------- Busca de produtos por nome ----------------------------

Future<DocumentSnapshot<Map<String, dynamic>>?> resolveProductByName(
  String name,
  FirebaseFirestore db,
  String tenantId,
) async {
  final lower = name.toLowerCase().trim();
  final col = db.collection('tenants').doc(tenantId).collection('produtos');

  // 1) nomeLower == lower (recomendado ter esse campo)
  var snap = await col.where('nomeLower', isEqualTo: lower).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  // 2) nome == name (exato)
  snap = await col.where('nome', isEqualTo: name.trim()).limit(1).get();
  if (snap.docs.isNotEmpty) return snap.docs.first;

  // 3) prefixo por orderBy (exige índice em nomeLower; se faltar, cai no catch)
  try {
    snap = await col
        .orderBy('nomeLower')
        .startAt([lower])
        .endAt(['$lower\uf8ff'])
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return snap.docs.first;
  } catch (_) {
    // sem índice -> ignora e usa fallback
  }

  // 4) fallback: sample e compara (tolerante)
  final sample = await col.limit(50).get();
  for (final d in sample.docs) {
    final data = d.data();
    final n = (data['nome'] as String?) ?? (data['Nome'] as String?);
    if (n != null && n.toLowerCase().trim() == lower) return d;
  }
  return null;
}

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
    // fallback: contém (sem índice)
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
