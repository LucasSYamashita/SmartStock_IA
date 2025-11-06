// lib/features/chat/chat_controller.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_message.dart';
import 'nlu.dart'; // MoveIntent / parseCommand
import 'chat_backend.dart'; // makeChatBackend()

class ChatController {
  final String tenantId;
  final String role; // 'admin' | 'staff' | 'viewer'
  final String userId;

  final List<ChatMessage> messages = [];

  // Random.secure() pode travar no web; use Random() simples
  final _rnd = Random();
  String? _pendingId; // id de idempotência
  bool _busy = false;

  MoveIntent? _pendingMove; // última proposta pendente
  final ChatBackend _backend = makeChatBackend(FirebaseFirestore.instance);

  ChatController({
    required this.tenantId,
    required this.role,
    required this.userId,
  });

  bool get hasPendingMove => _pendingMove != null;

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = _rnd.nextInt(1 << 30).toRadixString(36);
    return '$t$r';
  }

  Future<String> _getOrCreateProdutoByName({
    required String name,
    double? preco,
  }) async {
    final db = FirebaseFirestore.instance;
    final col = db.collection('tenants').doc(tenantId).collection('produtos');
    final nomeLower = name.toLowerCase().trim();

    final q = await col.where('nomeLower', isEqualTo: nomeLower).limit(1).get();
    if (q.docs.isNotEmpty) {
      final doc = q.docs.first;
      if (preco != null && preco >= 0) {
        await doc.reference.update({
          'preco': preco,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': userId,
        });
      }
      return doc.id;
    }

    final doc = await col.add({
      'nome': name,
      'nomeLower': nomeLower,
      'categoria': '',
      'sku': '',
      'preco': (preco != null && preco >= 0) ? preco : 0.0,
      'quantidade': 0,
      'estoqueMinimo': 1,
      'ativo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
    return doc.id;
  }

  /// Envia texto do usuário
  Future<void> send(String raw, {void Function()? onChange}) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    // atalhos: confirmar/cancelar por texto
    final t = text.toLowerCase();
    if (t == 'confirmar' && _pendingMove != null) {
      await confirmPending(onChange: onChange);
      return;
    }
    if (t == 'cancelar' && _pendingMove != null) {
      cancelPending(onChange: onChange);
      messages.add(
        ChatMessage(role: 'assistant', text: 'Operação cancelada.'),
      );
      onChange?.call();
      return;
    }

    messages.add(ChatMessage(role: 'user', text: text));
    onChange?.call();

    _pendingId ??= _newId();

    // 1) NLU local -> se reconheceu movimento, apenas propõe
    final intent = parseCommand(text);
    if (intent is MoveIntent) {
      _pendingMove = intent;
      final resumo = intent.tipo == 'entrada' ? 'entrada' : 'saída';
      final conf = 'Proposta: $resumo de ${intent.quantidade} un. em '
          '"${intent.produtoNome}"'
          '${intent.preco != null ? ' a ${intent.preco!.toStringAsFixed(2)}' : ''}. '
          'Confirmar?';
      messages.add(ChatMessage(role: 'assistant', text: conf));
      onChange?.call();
      return;
    }

    // 2) Qualquer outra coisa -> backend (Functions com fallback local)
    try {
      final res = await _backend.respond(
        tenantId: tenantId,
        userId: userId,
        text: text,
      );
      messages.add(ChatMessage(role: 'assistant', text: res.reply));
    } catch (_) {
      messages.add(ChatMessage(
        role: 'assistant',
        text: 'Não consegui responder agora. Tente novamente.',
      ));
    }
    onChange?.call();
  }

  /// Confirma a última movimentação proposta (idempotente)
  Future<void> confirmPending({void Function()? onChange}) async {
    final move = _pendingMove;
    if (move == null || _busy) return;

    _busy = true;
    final id = _pendingId ?? _newId();

    final db = FirebaseFirestore.instance;
    final movRef =
        db.collection('tenants').doc(tenantId).collection('movimentos').doc(id);

    try {
      await db.runTransaction((tx) async {
        final produtoId = await _getOrCreateProdutoByName(
          name: move.produtoNome,
          preco: move.preco,
        );

        // idempotência
        final exists = await tx.get(movRef);
        if (exists.exists) {
          throw StateError('already-exists');
        }

        final movData = <String, dynamic>{
          'tipo': move.tipo, // 'entrada' | 'saida'
          'produtoId': produtoId,
          'produtoNome': move.produtoNome,
          'quantidade': move.quantidade,
          'usuarioId': userId,
          'origem': 'chat',
          'motivo': move.motivo ?? 'chatbot',
          'requestId': id,
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (move.preco != null) movData['preco'] = move.preco;

        tx.set(movRef, movData);

        final prodRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .doc(produtoId);

        tx.update(prodRef, {
          'quantidade': FieldValue.increment(
            move.tipo == 'entrada' ? move.quantidade : -move.quantidade,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': userId,
        });
      });

      messages.add(ChatMessage(
        role: 'assistant',
        text:
            '✅ ${move.tipo == 'entrada' ? 'Entrada' : 'Saída'} registrada com sucesso.',
      ));
    } on StateError catch (e) {
      messages.add(ChatMessage(
        role: 'assistant',
        text: e.message == 'already-exists'
            ? 'ℹ️ Esta movimentação já havia sido registrada (idempotente).'
            : 'Erro ao confirmar. Tente novamente.',
      ));
    } catch (_) {
      messages.add(ChatMessage(
        role: 'assistant',
        text: 'Erro ao confirmar. Tente novamente.',
      ));
    } finally {
      _busy = false;
      _pendingId = null;
      _pendingMove = null;
      onChange?.call();
    }
  }

  void cancelPending({void Function()? onChange}) {
    _pendingId = null;
    _pendingMove = null;
    onChange?.call();
  }
}
