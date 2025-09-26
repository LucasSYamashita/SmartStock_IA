import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class FirestoreProducts {
  final FirebaseFirestore db;
  final String tenantId;
  FirestoreProducts(this.db, this.tenantId);

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('tenants').doc(tenantId).collection('produtos');

  /// Stream de todos os produtos (ordenado por nome)
  Stream<List<Product>> streamAll() {
    return _col.orderBy('nomeLower', descending: false).snapshots().map(
          (s) => s.docs.map((d) => Product.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Lê um produto por ID
  Future<Product?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Product.fromMap(doc.id, doc.data()!);
  }

  /// Cria com timestamps de servidor
  Future<void> createWithServerTimestamps({
    required String id,
    required String nome,
    required String categoria,
    String? sku,
    required double preco,
    required int quantidade,
    required int estoqueMinimo,
    required bool ativo,
  }) async {
    await _col.doc(id).set({
      'nome': nome,
      'nomeLower': nome.toLowerCase(),
      'categoria': categoria,
      'sku': sku,
      'preco': preco,
      'valor': preco, // compat
      'quantidade': quantidade,
      'estoqueMinimo': estoqueMinimo,
      'ativo': ativo,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Atualiza com updatedAt
  Future<void> updateWithServerTimestamp({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    await _col.doc(id).update({
      ...data,
      'nomeLower': (data['nome'] as String).toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Apaga
  Future<void> delete(String id) => _col.doc(id).delete();
}
