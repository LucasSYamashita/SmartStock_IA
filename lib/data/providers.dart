// lib/data/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/tenant/tenant_provider.dart';
import '../data/models/product.dart';

final productsStreamProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  final db = FirebaseFirestore.instance;

  if (tenantId == null) return const Stream.empty();

  return db
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .orderBy('nomeLower', descending: false)
      .snapshots()
      .map((s) => s.docs.map((d) => Product.fromDoc(d.id, d.data())).toList());
});
