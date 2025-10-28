import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProductService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Cria um produto e (opcionalmente) registra entrada inicial
  static Future<String> createProduct({
    required String tenantId,
    required String nome,
    double preco = 0,
    int quantidade = 0,
    int estoqueMinimo = 0,
  }) async {
    final doc = await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .add({
      'nome': nome,
      'nomeLower': nome.toLowerCase(),
      'categoria': '',
      'sku': '',
      'preco': preco,
      'quantidade': quantidade,
      'estoqueMinimo': estoqueMinimo,
      'ativo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _uid,
    });

    if (quantidade > 0) {
      await _db
          .collection('tenants')
          .doc(tenantId)
          .collection('movimentos')
          .add({
        'tipo': 'entrada',
        'quantidade': quantidade,
        'produtoId': doc.id,
        'produtoNome': nome,
        'usuarioId': _uid,
        'origem': 'chat_create',
        'motivo': 'entrada inicial (chat)',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return doc.id;
  }

  /// Atualiza campos livres (preco, estoqueMinimo, nome…)
  static Future<void> updateProductFields({
    required String tenantId,
    required String productId,
    required Map<String, dynamic> data,
  }) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['updatedBy'] = _uid;

    if (data.containsKey('nome')) {
      data['nomeLower'] = (data['nome'] as String).toLowerCase();
    }

    await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(productId)
        .update(data);
  }

  /// Ajusta quantidade (+/-) e registra movimento
  static Future<void> adjustQuantityWithLog({
    required String tenantId,
    required String productId,
    required String produtoNome,
    required int delta, // +entrada / -saida
    String origem = 'chat_adjust',
    String motivo = '',
  }) async {
    final prodRef = _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(productId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(prodRef);
      if (!snap.exists) throw Exception('Produto não encontrado.');
      final atual = (snap['quantidade'] ?? 0) as int;
      final novo = atual + delta;
      if (novo < 0) throw Exception('Estoque insuficiente.');

      tx.update(prodRef, {
        'quantidade': novo,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _uid,
      });
    });

    await _db.collection('tenants').doc(tenantId).collection('movimentos').add({
      'tipo': delta >= 0 ? 'entrada' : 'saida',
      'quantidade': delta.abs(),
      'produtoId': productId,
      'produtoNome': produtoNome,
      'usuarioId': _uid,
      'origem': origem,
      'motivo': motivo,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteProduct({
    required String tenantId,
    required String productId,
  }) async {
    await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(productId)
        .delete();
  }

  /// Busca por nome (case-insensitive via `nomeLower`)
  static Future<String?> findProductIdByName({
    required String tenantId,
    required String nome,
  }) async {
    final q = await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .where('nomeLower', isEqualTo: nome.toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id;
  }

  static Future<Map<String, dynamic>?> getProductById({
    required String tenantId,
    required String productId,
  }) async {
    final d = await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(productId)
        .get();
    return d.data();
  }
}
