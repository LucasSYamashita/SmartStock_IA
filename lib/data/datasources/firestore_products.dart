import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class FirestoreProducts {
  final FirebaseFirestore db;
  final String tenantId;
  FirestoreProducts(this.db, this.tenantId);

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('tenants').doc(tenantId).collection('produtos');

  Stream<List<Product>> streamAll() {
    return _col.orderBy('nome').snapshots().map(
          (s) => s.docs.map((d) => Product.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<void> create(Product p) => _col.doc(p.id).set(p.toMap());
  Future<void> update(Product p) => _col.doc(p.id).update(p.toMap());
  Future<void> delete(String id) => _col.doc(id).delete();
}
