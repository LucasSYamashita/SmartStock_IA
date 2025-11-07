import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FallbackInventory {
  final FirebaseFirestore _db;
  FallbackInventory([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  Future<String> registrar({
    required String tenantId,
    required String nome,
    required int quantidade,
    required String tipo, // "entrada" ou "saida"
    double? preco,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final produtos =
        _db.collection('tenants').doc(tenantId).collection('produtos');

    final snap = await produtos
        .where('nomeLower', isEqualTo: nome.toLowerCase())
        .limit(1)
        .get();

    DocumentReference<Map<String, dynamic>> doc;
    Map<String, dynamic>? data;

    if (snap.docs.isEmpty) {
      doc = await produtos.add({
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'preco': preco ?? 0,
        'quantidade': tipo == 'entrada' ? quantidade : 0,
        'ativo': true,
        'categoria': '',
        'estoqueMinimo': 1,
        'createdBy': uid,
        'updatedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      data = {'quantidade': 0, 'preco': preco ?? 0};
    } else {
      doc = snap.docs.first.reference;
      data = snap.docs.first.data();
    }

    final atual = data?['quantidade'] ?? 0;
    final delta = tipo == 'entrada' ? quantidade : -quantidade;
    final novoEstoque = (atual + delta).clamp(0, double.infinity).toInt();

    await doc.update({
      'quantidade': novoEstoque,
      'preco': preco ?? data?['preco'] ?? 0,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('tenants').doc(tenantId).collection('movimentos').add({
      'tipo': tipo,
      'produtoId': doc.id,
      'produtoNome': nome,
      'quantidade': quantidade,
      'preco': preco ?? data?['preco'] ?? 0,
      'valorTotal': (preco ?? data?['preco'] ?? 0) * quantidade,
      'usuarioId': uid,
      'origem': 'chat-fallback',
      'motivo': 'chatbot',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }
}
