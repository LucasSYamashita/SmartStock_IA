import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreMovements {
  final FirebaseFirestore _db;
  final String tenantId;
  FirestoreMovements(this._db, this.tenantId);

  CollectionReference<Map<String, dynamic>> get _mov =>
      _db.collection('tenants').doc(tenantId).collection('movimentacoes');

  CollectionReference<Map<String, dynamic>> get _prod =>
      _db.collection('tenants').doc(tenantId).collection('produtos');

  Future<void> applyMovement({
    required String produtoId,
    required String tipo, // 'entrada' | 'saida'
    required int quantidade,
    required String motivo,
    required String usuarioId,
    required String origem,
    String? mensagemOriginal,
  }) async {
    await _db.runTransaction((tx) async {
      final pRef = _prod.doc(produtoId);
      final pSnap = await tx.get(pRef);
      if (!pSnap.exists) throw Exception('Produto não encontrado');

      final data = pSnap.data()!;
      final atual = (data['quantidade'] as num?)?.toInt() ??
          (data['Quantidade'] as num?)?.toInt() ??
          0;
      final novo = tipo == 'entrada' ? atual + quantidade : atual - quantidade;
      if (novo < 0) throw Exception('Estoque insuficiente');

      tx.update(pRef, {
        'quantidade': novo,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(_mov.doc(), {
        'produtoId': pRef.id,
        'tipo': tipo,
        'quantidade': quantidade,
        'motivo': motivo,
        'usuarioId': usuarioId,
        'origem': origem,
        'mensagemOriginal': mensagemOriginal,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
