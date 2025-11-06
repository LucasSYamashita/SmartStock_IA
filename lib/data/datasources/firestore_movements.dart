import 'package:cloud_firestore/cloud_firestore.dart';

/// Movimentações de estoque (entrada/saída/ajuste) + atualização de produto.
/// - Sem salvar `descricao` (use `motivo`/`paymentNote`)
/// - Idempotência via `requestId`
/// - Saída trava em zero (ou lança erro)
class FirestoreMovements {
  final FirebaseFirestore db;
  final String tenantId;
  const FirestoreMovements(this.db, this.tenantId);

  DocumentReference<Map<String, dynamic>> _prodRef(String id) =>
      db.collection('tenants').doc(tenantId).collection('produtos').doc(id);

  CollectionReference<Map<String, dynamic>> get _movCol =>
      db.collection('tenants').doc(tenantId).collection('movimentos');

  /// [tipo] = 'entrada' | 'saida' | 'ajuste'
  Future<void> applyMovement({
    required String produtoId,
    required String tipo,
    required int quantidade,
    required String usuarioId,
    String? motivo,
    String? origem,
    String? mensagemOriginal, // será concatenada ao motivo
    bool throwOnInsufficient = false,
    String? requestId,
    String? paymentMethod,
    String? paymentNote,
    double? preco,
  }) async {
    if (quantidade <= 0) {
      throw ArgumentError.value(quantidade, 'quantidade', 'deve ser > 0');
    }

    final prodRef = _prodRef(produtoId);
    final movRef = requestId != null ? _movCol.doc(requestId) : _movCol.doc();

    await db.runTransaction((tx) async {
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
      int applied = quantidade;

      switch (tipo) {
        case 'entrada':
          next = current + quantidade;
          break;
        case 'saida':
          next = current - quantidade;
          if (next < 0) {
            if (throwOnInsufficient) {
              throw StateError(
                  'Estoque insuficiente (atual: $current, tentativa: $quantidade).');
            }
            applied = current;
            next = 0;
          }
          break;
        case 'ajuste':
          next = current + quantidade;
          if (next < 0) next = 0;
          break;
        default:
          throw ArgumentError.value(
              tipo, 'tipo', 'inválido (entrada|saida|ajuste)');
      }

      // Atualiza produto (rules pedem updatedAt/updatedBy no update)
      tx.update(prodRef, {
        'quantidade': next,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      final movData = <String, dynamic>{
        'produtoId': produtoId,
        'produtoNome': nome,
        'tipo': tipo,
        'quantidade': applied,
        'motivo': _composeMotivo(motivo, mensagemOriginal),
        'origem': origem,
        'usuarioId': usuarioId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (paymentMethod != null && paymentMethod.isNotEmpty) {
        movData['paymentMethod'] = paymentMethod;
      }
      if (paymentNote != null && paymentNote.isNotEmpty) {
        movData['paymentNote'] = paymentNote;
      }
      if (preco != null) {
        movData['preco'] = preco;
      }
      if (requestId != null) {
        movData['requestId'] = requestId;
      }

      tx.set(movRef, movData);
    });
  }

  String? _composeMotivo(String? motivo, String? msg) {
    final m = (motivo ?? '').trim();
    final s = (msg ?? '').trim();
    if (m.isNotEmpty && s.isNotEmpty) return '$m • $s';
    if (m.isNotEmpty) return m;
    if (s.isNotEmpty) return s;
    return null;
  }
}
