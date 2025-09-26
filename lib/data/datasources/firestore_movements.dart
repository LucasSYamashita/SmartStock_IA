import 'package:cloud_firestore/cloud_firestore.dart';

/// Movimentações de estoque (entrada/saída/ajuste) + atualização do produto.
/// Garante que quantidade não fique negativa (padrão: "trava em zero").
/// Se preferir bloquear saídas acima do estoque, use `throwOnInsufficient: true`.
class FirestoreMovements {
  final FirebaseFirestore db;
  final String tenantId;
  const FirestoreMovements(this.db, this.tenantId);

  DocumentReference<Map<String, dynamic>> _prodRef(String id) =>
      db.collection('tenants').doc(tenantId).collection('produtos').doc(id);

  CollectionReference<Map<String, dynamic>> get _movCol =>
      db.collection('tenants').doc(tenantId).collection('movimentos');

  /// Aplica uma movimentação ao produto.
  ///
  /// [tipo] = 'entrada' | 'saida' | 'ajuste'
  /// [quantidade] deve ser > 0
  /// [throwOnInsufficient] quando true, lança erro se saída > estoque (não clampa em zero).
  /// [requestId] opcional para idempotência (evita duplicar o mesmo movimento).
  Future<void> applyMovement({
    required String produtoId,
    required String tipo,
    required int quantidade,
    required String usuarioId,
    String? motivo,
    String? origem,
    String? mensagemOriginal,
    bool throwOnInsufficient = false,
    String? requestId,
  }) async {
    if (quantidade <= 0) {
      throw ArgumentError.value(quantidade, 'quantidade', 'deve ser > 0');
    }

    final prodRef = _prodRef(produtoId);
    final movRef = requestId != null ? _movCol.doc(requestId) : _movCol.doc();

    await db.runTransaction((tx) async {
      // Idempotência: se já existir um documento com o mesmo requestId, não reaplica.
      if (requestId != null) {
        final existing = await tx.get(movRef);
        if (existing.exists) return;
      }

      final prodSnap = await tx.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Produto não encontrado.');
      }

      final data = prodSnap.data()!;
      final current = (data['quantidade'] as num?)?.toInt() ?? 0;
      final nome = (data['nome'] ?? data['Nome'] ?? '(sem nome)').toString();

      int next = current;
      int delta = 0;

      switch (tipo) {
        case 'entrada':
          delta = quantidade;
          next = current + quantidade;
          break;

        case 'saida':
          delta = -quantidade;
          next = current - quantidade;
          if (next < 0) {
            if (throwOnInsufficient) {
              throw StateError(
                'Estoque insuficiente (atual: $current, tentativa: $quantidade).',
              );
            }
            // Clampa: aplica apenas o que tem e zera
            delta = -current;
            next = 0;
          }
          break;

        case 'ajuste':
          // Ajuste é soma positiva; se precisar negativo, passe como saída ou trate no chamador.
          delta = quantidade;
          next = current + quantidade;
          if (next < 0) next = 0;
          break;

        default:
          throw ArgumentError.value(
              tipo, 'tipo', 'inválido (use: entrada | saida | ajuste)');
      }

      // Atualiza produto
      tx.update(prodRef, {
        'quantidade': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log/auditoria
      tx.set(movRef, {
        'produtoId': produtoId,
        'produtoNome': nome,
        'tenantId': tenantId,
        'productRef': prodRef.path,
        'tipo': tipo,
        'quantidade': quantidade, // solicitado
        'delta': delta, // efetivamente aplicado (negativo na saída)
        'motivo': motivo,
        'origem': origem,
        'mensagemOriginal': mensagemOriginal,
        'usuarioId': usuarioId,
        'createdAt': FieldValue.serverTimestamp(),
        'snapshot': {
          'antes': current,
          'depois': next,
        },
      });
    });
  }
}
