// lib/features/chat/fallback_inventory.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FallbackInventory {
  final FirebaseFirestore _db;
  FallbackInventory([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  Future<String> upsertProductAndEntry({
    required String tenantId,
    required String nome,
    required int quantidade,
    double? preco,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final prodCol =
        _db.collection('tenants').doc(tenantId).collection('produtos');

    final snap = await prodCol
        .where('nomeLower', isEqualTo: nome.toLowerCase())
        .limit(1)
        .get();

    DocumentReference<Map<String, dynamic>> doc;
    if (snap.docs.isEmpty) {
      doc = await prodCol.add({
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'categoria': '',
        'sku': '',
        'preco': preco ?? 0.0,
        'quantidade': quantidade,
        'estoqueMinimo': 1,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } else {
      doc = snap.docs.first.reference;
      await doc.update({
        if (preco != null) 'preco': preco,
        'quantidade': FieldValue.increment(quantidade),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    }

    await _db.collection('tenants').doc(tenantId).collection('movimentos').add({
      'tipo': 'entrada',
      'quantidade': quantidade,
      'produtoId': doc.id,
      'produtoNome': nome,
      'usuarioId': uid,
      'origem': 'chat-fallback',
      'motivo': 'compra',
      'preco': preco,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }
}
