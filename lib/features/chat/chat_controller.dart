// lib/features/chat/chat_controller.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'chat_message.dart';
import 'nlu.dart';

class ChatController {
  final String tenantId;
  final String role; // 'admin' | 'staff' | 'viewer'
  final String userId;

  final List<ChatMessage> messages = [];

  // Random.secure() tem pegadinhas no web; use Random() simples aqui
  final _rnd = Random();
  String? _pendingId; // requestId em aberto (idempotência)
  bool _busy = false;

  // guarda a última MoveIntent proposta (para o botão Confirmar)
  MoveIntent? _pendingMove;

  ChatController({
    required this.tenantId,
    required this.role,
    required this.userId,
  });

  bool get hasPendingMove => _pendingMove != null;

  /// ID curta p/ idempotência (tempo + aleatório)
  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = _rnd.nextInt(1000000000).toRadixString(36); // evita 0 no web
    return '$t$r';
  }

  Future<String> _getOrCreateProdutoByName({
    required String name,
    double? preco,
  }) async {
    final db = FirebaseFirestore.instance;
    final products =
        db.collection('tenants').doc(tenantId).collection('produtos');

    final nomeLower = name.toLowerCase().trim();

    // tenta achar por nomeLower
    final q =
        await products.where('nomeLower', isEqualTo: nomeLower).limit(1).get();
    if (q.docs.isNotEmpty) {
      final doc = q.docs.first;
      // se veio um preço novo, atualiza o preço do produto
      if (preco != null && preco >= 0) {
        await doc.reference.update({
          'preco': preco,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': userId,
        });
      }
      return doc.id;
    }

    // cria com campos compatíveis às regras
    final doc = await products.add({
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

    messages.add(ChatMessage(role: 'user', text: text));
    onChange?.call();

    _pendingId ??= _newId();

    // NLU local
    final intent = parseCommand(text);
    if (intent is MoveIntent) {
      _pendingMove = intent;
      final resumo = intent.tipo == 'entrada' ? 'entrada' : 'saída';
      final conf =
          'Proposta: $resumo de ${intent.quantidade} un. em "${intent.produtoNome}"'
          '${intent.preco != null ? ' a ${intent.preco!.toStringAsFixed(2)}' : ''}. Confirmar?';
      messages.add(ChatMessage(role: 'assistant', text: conf));
      onChange?.call();
      return;
    }

    // fallback opcional no backend (callable)
    try {
      final funcs = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = funcs.httpsCallable('actCallV2');
      final resp = await callable.call({
        'requestId': _pendingId,
        'tenantId': tenantId,
        'role': role,
        'text': text,
      });

      final data = Map<String, dynamic>.from(resp.data as Map);
      final msg = (data['message'] as String?) ?? 'Ok.';
      messages.add(ChatMessage(role: 'assistant', text: msg));
      onChange?.call();
    } catch (_) {
      messages.add(
        ChatMessage(
            role: 'assistant', text: 'Falha ao processar. Tente novamente.'),
      );
      onChange?.call();
    }
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
      // garante produto e faz tudo na transação
      await db.runTransaction((tx) async {
        // cria/pega produto
        final produtoId = await _getOrCreateProdutoByName(
          name: move.produtoNome,
          preco: move.preco, // pode ser null
        );

        // idempotência
        final snap = await tx.get(movRef);
        if (snap.exists) {
          throw StateError('already-exists');
        }

        // monta mapa do movimento SEM preco quando não existe
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
        if (move.preco != null) {
          movData['preco'] = move.preco; // só inclui se número
        }

        tx.set(movRef, movData);

        // atualiza estoque do produto
        final prodRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .doc(produtoId);

        tx.update(prodRef, {
          'quantidade': FieldValue.increment(
              move.tipo == 'entrada' ? move.quantidade : -move.quantidade),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': userId,
        });
      });

      messages.add(
        ChatMessage(
          role: 'assistant',
          text:
              '✅ ${move.tipo == 'entrada' ? 'Entrada' : 'Saída'} registrada com sucesso.',
        ),
      );
    } on StateError catch (e) {
      if (e.message == 'already-exists') {
        messages.add(ChatMessage(
          role: 'assistant',
          text: 'ℹ️ Esta movimentação já havia sido registrada (idempotente).',
        ));
      } else {
        messages.add(ChatMessage(
          role: 'assistant',
          text: 'Erro ao confirmar. Tente novamente.',
        ));
      }
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
